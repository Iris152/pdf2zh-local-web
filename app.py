from __future__ import annotations

import os
import re
import shutil
import subprocess
import threading
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles


APP_DIR = Path(__file__).resolve().parent
STATIC_DIR = APP_DIR / "static"


def default_path(preferred: str, fallback: str) -> str:
    drive = Path(preferred).drive
    if drive and Path(f"{drive}\\").exists():
        return preferred
    return fallback


USER_HOME = str(Path.home())
DEFAULT_TOOL_ROOT = default_path(r"G:\CodexTools", str(Path(USER_HOME) / "CodexTools"))
DEFAULT_JOB_ROOT = default_path(
    r"G:\CodexOutputs\pdf2zh-web-jobs",
    str(Path(USER_HOME) / "CodexOutputs" / "pdf2zh-web-jobs"),
)
DEFAULT_TRANSLATED_OUTPUT = default_path(
    r"E:\Download\PDF2ZH_Output",
    str(Path(USER_HOME) / "Downloads" / "PDF2ZH_Output"),
)

PDF2ZH_EXE = Path(
    os.environ.get(
        "PDF2ZH_EXE",
        str(Path(DEFAULT_TOOL_ROOT) / "pdf2zh-venv" / "Scripts" / "pdf2zh.exe"),
    )
)
TOOL_ROOT = Path(os.environ.get("PDF2ZH_TOOL_ROOT", DEFAULT_TOOL_ROOT))
TOOL_HOME = Path(os.environ.get("PDF2ZH_TOOL_HOME", str(TOOL_ROOT / "home")))
TOOL_TMP = Path(os.environ.get("PDF2ZH_TOOL_TMP", str(TOOL_ROOT / "tmp")))
HF_HOME = Path(os.environ.get("HF_HOME", str(TOOL_ROOT / "hf-cache")))
XDG_CACHE_HOME = Path(os.environ.get("XDG_CACHE_HOME", str(TOOL_ROOT / "xdg-cache")))

JOB_ROOT = Path(os.environ.get("PDF2ZH_JOB_ROOT", DEFAULT_JOB_ROOT))
DEFAULT_OUTPUT_DIR = os.environ.get("PDF2ZH_DEFAULT_OUTPUT", DEFAULT_TRANSLATED_OUTPUT)

SAFE_NAME_RE = re.compile(r"[^A-Za-z0-9._\-\u4e00-\u9fff]+")
PAGES_RE = re.compile(r"^[0-9,\-\s]+$")
PROGRESS_RE = re.compile(r"(\d{1,3})%")


def now_label() -> str:
    return datetime.now().strftime("%H:%M:%S")


def safe_stem(name: str) -> str:
    stem = Path(name).stem.strip() or "document"
    cleaned = SAFE_NAME_RE.sub("_", stem).strip("._-")
    return cleaned[:90] or "document"


@dataclass
class Job:
    id: str
    original_name: str
    input_path: Path
    output_dir: Path
    service_label: str
    status: str = "queued"
    progress: int = 0
    stage: str = "等待开始"
    created_at: float = field(default_factory=time.time)
    started_at: float | None = None
    finished_at: float | None = None
    logs: list[str] = field(default_factory=list)
    mono_pdf: Path | None = None
    dual_pdf: Path | None = None
    error: str | None = None
    return_code: int | None = None

    def add_log(self, text: str) -> None:
        text = text.strip()
        if not text:
            return
        self.logs.append(f"[{now_label()}] {text}")
        if len(self.logs) > 600:
            self.logs = self.logs[-600:]

    def as_dict(self) -> dict[str, Any]:
        elapsed = None
        if self.started_at:
            end = self.finished_at or time.time()
            elapsed = round(end - self.started_at, 1)
        return {
            "id": self.id,
            "originalName": self.original_name,
            "status": self.status,
            "progress": self.progress,
            "stage": self.stage,
            "service": self.service_label,
            "outputDir": str(self.output_dir),
            "logs": self.logs,
            "error": self.error,
            "elapsedSeconds": elapsed,
            "results": {
                "mono": file_payload(self.id, "mono", self.mono_pdf),
                "dual": file_payload(self.id, "dual", self.dual_pdf),
            },
        }


def file_payload(job_id: str, kind: str, path: Path | None) -> dict[str, Any] | None:
    if not path or not path.exists():
        return None
    return {
        "name": path.name,
        "size": path.stat().st_size,
        "downloadUrl": f"/api/jobs/{job_id}/download/{kind}",
    }


jobs: dict[str, Job] = {}
jobs_lock = threading.Lock()

app = FastAPI(title="PDF2ZH Local", version="1.0.0")


@app.get("/api/health")
def health() -> dict[str, Any]:
    return {
        "ok": PDF2ZH_EXE.exists(),
        "pdf2zhExe": str(PDF2ZH_EXE),
        "toolHome": str(TOOL_HOME),
        "jobRoot": str(JOB_ROOT),
        "defaultOutputDir": DEFAULT_OUTPUT_DIR,
    }


@app.post("/api/jobs")
async def create_job(
    file: UploadFile = File(...),
    service: str = Form("google"),
    thread_count: int = Form(2),
    output_dir: str = Form(DEFAULT_OUTPUT_DIR),
    pages: str = Form(""),
    compatible: bool = Form(False),
    ignore_cache: bool = Form(False),
    openai_base_url: str = Form(""),
    openai_api_key: str = Form(""),
    openai_model: str = Form(""),
) -> dict[str, Any]:
    if not PDF2ZH_EXE.exists():
        raise HTTPException(500, f"pdf2zh executable not found: {PDF2ZH_EXE}")
    if not file.filename or not file.filename.lower().endswith(".pdf"):
        raise HTTPException(400, "Only PDF files are supported.")
    if thread_count < 1 or thread_count > 8:
        raise HTTPException(400, "Thread count must be between 1 and 8.")

    pages = pages.strip()
    if pages and not PAGES_RE.match(pages):
        raise HTTPException(400, "Page range only supports numbers, commas, spaces, and hyphens.")

    service = service.strip().lower()
    if service not in {"google", "openai"}:
        raise HTTPException(400, "Unsupported translation service.")
    if service == "openai" and not openai_api_key.strip():
        raise HTTPException(400, "OpenAI-compatible service requires an API key.")

    job_id = uuid.uuid4().hex
    stem = safe_stem(file.filename)
    job_dir = JOB_ROOT / "jobs" / job_id
    input_dir = job_dir / "input"
    input_dir.mkdir(parents=True, exist_ok=True)

    input_path = input_dir / f"{stem}.pdf"
    with input_path.open("wb") as out:
        shutil.copyfileobj(file.file, out)

    requested_output = Path(output_dir.strip() or DEFAULT_OUTPUT_DIR)
    dated_output_dir = requested_output / f"{stem}_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{job_id[:8]}"
    dated_output_dir.mkdir(parents=True, exist_ok=True)

    label = "Google" if service == "google" else f"OpenAI-compatible ({openai_model or 'default model'})"
    job = Job(
        id=job_id,
        original_name=file.filename,
        input_path=input_path,
        output_dir=dated_output_dir,
        service_label=label,
    )
    job.add_log(f"文件上传成功：{file.filename}")

    with jobs_lock:
        jobs[job_id] = job

    worker_args = {
        "service": service,
        "thread_count": thread_count,
        "pages": pages,
        "compatible": compatible,
        "ignore_cache": ignore_cache,
        "openai_base_url": openai_base_url.strip(),
        "openai_api_key": openai_api_key.strip(),
        "openai_model": openai_model.strip(),
    }
    thread = threading.Thread(target=run_translation, args=(job_id, worker_args), daemon=True)
    thread.start()
    return job.as_dict()


@app.get("/api/jobs/{job_id}")
def get_job(job_id: str) -> dict[str, Any]:
    job = get_job_or_404(job_id)
    return job.as_dict()


@app.get("/api/jobs/{job_id}/download/{kind}")
def download_job_file(job_id: str, kind: str) -> FileResponse:
    job = get_job_or_404(job_id)
    if kind == "mono":
        path = job.mono_pdf
    elif kind == "dual":
        path = job.dual_pdf
    else:
        raise HTTPException(404, "Unknown result type.")
    if not path or not path.exists():
        raise HTTPException(404, "Result file is not available yet.")
    return FileResponse(path, media_type="application/pdf", filename=path.name)


def get_job_or_404(job_id: str) -> Job:
    with jobs_lock:
        job = jobs.get(job_id)
    if not job:
        raise HTTPException(404, "Job not found.")
    return job


def run_translation(job_id: str, args: dict[str, Any]) -> None:
    job = get_job_or_404(job_id)
    job.status = "running"
    job.stage = "解析文档"
    job.progress = 5
    job.started_at = time.time()

    env = os.environ.copy()
    for path in (TOOL_HOME, TOOL_TMP, HF_HOME, XDG_CACHE_HOME):
        path.mkdir(parents=True, exist_ok=True)
    env.update(
        {
            "USERPROFILE": str(TOOL_HOME),
            "HOME": str(TOOL_HOME),
            "TEMP": str(TOOL_TMP),
            "TMP": str(TOOL_TMP),
            "HF_HOME": str(HF_HOME),
            "XDG_CACHE_HOME": str(XDG_CACHE_HOME),
            "PYTHONIOENCODING": "utf-8",
        }
    )

    service_arg = "google"
    if args["service"] == "openai":
        if args["openai_base_url"]:
            env["OPENAI_BASE_URL"] = args["openai_base_url"]
        env["OPENAI_API_KEY"] = args["openai_api_key"]
        if args["openai_model"]:
            env["OPENAI_MODEL"] = args["openai_model"]
            service_arg = f"openai:{args['openai_model']}"
        else:
            service_arg = "openai"

    command = [
        str(PDF2ZH_EXE),
        str(job.input_path),
        "-li",
        "en",
        "-lo",
        "zh",
        "-s",
        service_arg,
        "-t",
        str(args["thread_count"]),
        "-o",
        str(job.output_dir),
    ]
    if args["pages"]:
        command.extend(["-p", args["pages"]])
    if args["compatible"]:
        command.append("--compatible")
    if args["ignore_cache"]:
        command.append("--ignore-cache")

    job.add_log(f"开始翻译：服务={job.service_label}，输出目录={job.output_dir}")
    job.add_log("命令已启动，正在等待 pdf2zh 返回进度。")

    try:
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env,
            cwd=str(APP_DIR),
            bufsize=1,
        )
        assert process.stdout is not None
        redact_values = [args.get("openai_api_key", "")]
        for raw_line in iter(process.stdout.readline, ""):
            line = raw_line.replace("\r", "\n").strip()
            if not line:
                continue
            handle_process_line(job, line, redact_values)
        job.return_code = process.wait()
    except Exception as exc:
        job.status = "failed"
        job.stage = "失败"
        job.error = str(exc)
        job.finished_at = time.time()
        job.add_log(f"任务失败：{exc}")
        return

    discover_results(job)
    job.finished_at = time.time()
    if job.return_code == 0 and (job.mono_pdf or job.dual_pdf):
        job.status = "completed"
        job.stage = "完成"
        job.progress = 100
        job.add_log("任务完成，结果文件已生成。")
    else:
        job.status = "failed"
        job.stage = "失败"
        job.error = f"pdf2zh exited with code {job.return_code}."
        job.add_log(job.error)


def handle_process_line(job: Job, line: str, redact_values: list[str] | None = None) -> None:
    if "use font" in line:
        job.stage = "加载中文字体"
        job.progress = max(job.progress, 12)
    elif "doclayout" in line.lower() or "onnx model" in line.lower():
        job.stage = "加载版面模型"
        job.progress = max(job.progress, 10)
    elif "Namespace(" in line:
        job.stage = "解析文档"
        job.progress = max(job.progress, 15)

    match = PROGRESS_RE.search(line)
    if match:
        percent = max(0, min(100, int(match.group(1))))
        job.stage = "翻译与排版"
        job.progress = max(job.progress, min(95, percent))

    cleaned = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", line)
    for secret in redact_values or []:
        if secret and secret in cleaned:
            cleaned = cleaned.replace(secret, "***")
    job.add_log(cleaned)


def discover_results(job: Job) -> None:
    mono = list(job.output_dir.glob("*-mono.pdf"))
    dual = list(job.output_dir.glob("*-dual.pdf"))
    if mono:
        job.mono_pdf = max(mono, key=lambda p: p.stat().st_mtime)
    if dual:
        job.dual_pdf = max(dual, key=lambda p: p.stat().st_mtime)


app.mount("/", StaticFiles(directory=STATIC_DIR, html=True), name="static")
