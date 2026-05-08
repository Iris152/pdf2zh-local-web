const form = document.querySelector("#translateForm");
const fileInput = document.querySelector("#pdfFile");
const dropZone = document.querySelector("#dropZone");
const selectedFile = document.querySelector("#selectedFile");
const fileName = document.querySelector("#fileName");
const fileSize = document.querySelector("#fileSize");
const serviceSelect = document.querySelector("#service");
const openaiSettings = document.querySelector("#openaiSettings");
const submitButton = document.querySelector("#submitButton");
const engineStatus = document.querySelector("#engineStatus");
const statePill = document.querySelector("#statePill");
const jobMeta = document.querySelector("#jobMeta");
const stageText = document.querySelector("#stageText");
const progressText = document.querySelector("#progressText");
const progressBar = document.querySelector("#progressBar");
const resultList = document.querySelector("#resultList");
const outputPath = document.querySelector("#outputPath");
const logBox = document.querySelector("#logBox");
const copyLog = document.querySelector("#copyLog");

let pollTimer = null;
let activeJobId = null;

function formatBytes(bytes) {
  if (!Number.isFinite(bytes)) return "";
  const units = ["B", "KB", "MB", "GB"];
  let value = bytes;
  let idx = 0;
  while (value >= 1024 && idx < units.length - 1) {
    value /= 1024;
    idx += 1;
  }
  return `${value.toFixed(idx === 0 ? 0 : 2)} ${units[idx]}`;
}

async function loadHealth() {
  try {
    const response = await fetch("/api/health");
    const health = await response.json();
    engineStatus.className = `engine-status ${health.ok ? "ok" : "bad"}`;
    engineStatus.querySelector("span:last-child").textContent = health.ok
      ? "本地引擎可用"
      : "未找到 pdf2zh 引擎";
    if (health.defaultOutputDir) {
      document.querySelector("#outputDir").value = health.defaultOutputDir;
    }
  } catch (error) {
    engineStatus.className = "engine-status bad";
    engineStatus.querySelector("span:last-child").textContent = "服务未启动";
  }
}

function updateFileDisplay(file) {
  if (!file) {
    selectedFile.hidden = true;
    return;
  }
  selectedFile.hidden = false;
  fileName.textContent = file.name;
  fileSize.textContent = formatBytes(file.size);
}

fileInput.addEventListener("change", () => updateFileDisplay(fileInput.files[0]));

for (const eventName of ["dragenter", "dragover"]) {
  dropZone.addEventListener(eventName, (event) => {
    event.preventDefault();
    dropZone.classList.add("dragover");
  });
}

for (const eventName of ["dragleave", "drop"]) {
  dropZone.addEventListener(eventName, (event) => {
    event.preventDefault();
    dropZone.classList.remove("dragover");
  });
}

dropZone.addEventListener("drop", (event) => {
  const file = event.dataTransfer.files[0];
  if (!file) return;
  const transfer = new DataTransfer();
  transfer.items.add(file);
  fileInput.files = transfer.files;
  updateFileDisplay(file);
});

serviceSelect.addEventListener("change", () => {
  openaiSettings.hidden = serviceSelect.value !== "openai";
});

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (!fileInput.files[0]) return;

  stopPolling();
  resetStatusForRun();
  submitButton.disabled = true;

  const formData = new FormData(form);
  try {
    const response = await fetch("/api/jobs", {
      method: "POST",
      body: formData,
    });
    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload.detail || "任务创建失败");
    }
    activeJobId = payload.id;
    renderJob(payload);
    pollTimer = window.setInterval(() => pollJob(activeJobId), 1800);
  } catch (error) {
    renderFailure(error.message);
    submitButton.disabled = false;
  }
});

copyLog.addEventListener("click", async () => {
  await navigator.clipboard.writeText(logBox.textContent);
  copyLog.textContent = "已复制";
  window.setTimeout(() => {
    copyLog.textContent = "复制日志";
  }, 1400);
});

async function pollJob(jobId) {
  try {
    const response = await fetch(`/api/jobs/${jobId}`);
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.detail || "读取任务状态失败");
    renderJob(payload);
    if (payload.status === "completed" || payload.status === "failed") {
      stopPolling();
      submitButton.disabled = false;
    }
  } catch (error) {
    stopPolling();
    renderFailure(error.message);
    submitButton.disabled = false;
  }
}

function stopPolling() {
  if (pollTimer) {
    window.clearInterval(pollTimer);
    pollTimer = null;
  }
}

function resetStatusForRun() {
  statePill.className = "state-pill running";
  statePill.textContent = "运行中";
  jobMeta.textContent = "任务已提交。";
  stageText.textContent = "准备中";
  progressText.textContent = "3%";
  progressBar.style.width = "3%";
  logBox.textContent = "正在创建任务...";
  resultList.innerHTML = '<div class="empty-state">任务运行中，完成后显示下载按钮。</div>';
  outputPath.textContent = "";
}

function renderJob(job) {
  statePill.className = `state-pill ${job.status}`;
  statePill.textContent = statusLabel(job.status);
  jobMeta.textContent = `${job.originalName} · ${job.service}${job.elapsedSeconds ? ` · ${job.elapsedSeconds}s` : ""}`;
  stageText.textContent = job.stage || "运行中";
  const progress = Math.max(0, Math.min(100, job.progress || 0));
  progressText.textContent = `${progress}%`;
  progressBar.style.width = `${progress}%`;
  outputPath.textContent = job.outputDir ? `输出目录：${job.outputDir}` : "";
  logBox.textContent = job.logs?.length ? job.logs.join("\n") : "等待日志...";
  logBox.scrollTop = logBox.scrollHeight;
  renderResults(job.results);
  if (job.status === "failed" && job.error) {
    logBox.textContent += `\n错误：${job.error}`;
  }
}

function statusLabel(status) {
  if (status === "running") return "运行中";
  if (status === "completed") return "完成";
  if (status === "failed") return "失败";
  if (status === "queued") return "排队中";
  return "就绪";
}

function renderFailure(message) {
  statePill.className = "state-pill failed";
  statePill.textContent = "失败";
  stageText.textContent = "任务失败";
  progressText.textContent = "0%";
  progressBar.style.width = "0";
  logBox.textContent = message;
}

function renderResults(results) {
  const files = [
    ["mono", "单语中文 PDF", results?.mono],
    ["dual", "中英对照 PDF", results?.dual],
  ].filter((entry) => entry[2]);

  if (!files.length) {
    resultList.innerHTML = '<div class="empty-state">翻译完成后会在这里显示下载按钮。</div>';
    return;
  }

  resultList.innerHTML = files
    .map(([, label, file]) => {
      return `
        <div class="result-item">
          <span class="file-badge">PDF</span>
          <div>
            <strong>${label}</strong>
            <span>${escapeHtml(file.name)} · ${formatBytes(file.size)}</span>
          </div>
          <a class="download-button" href="${file.downloadUrl}">下载</a>
        </div>
      `;
    })
    .join("");
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

loadHealth();
