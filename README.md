# PDF2ZH Local Web

一个本地运行的 PDF 论文翻译网页工具。后端调用 [PDFMathTranslate / pdf2zh](https://github.com/Byaidu/PDFMathTranslate)，尽量保留原 PDF 的版面、公式、图片和表格，并输出单语中文 PDF 与中英对照 PDF。

这个仓库不提交虚拟环境、模型缓存、上传文件和翻译结果；这些内容由安装脚本在本机生成，避免仓库过大或泄露本地文档。

## 功能

- 拖拽或点击上传 PDF。
- 支持 Google 翻译服务，以及 OpenAI 兼容接口。
- 支持页码范围，例如 `1-3` 或 `1,5,8`。
- 每个任务生成独立输出目录。
- 翻译完成后提供 `*-mono.pdf` 和 `*-dual.pdf` 下载。
- Windows 下可双击 `启动 PDF2ZH Local.bat` 自动启动服务并打开浏览器。

## 环境要求

- Windows 10/11。
- Python 3.10 或更高版本，推荐 Python 3.11。
- 网络连接：首次安装依赖、首次下载版面模型、使用在线翻译服务时需要联网。
- 推荐把工具和缓存放在 G 盘。默认脚本会优先使用：
  - 工具与虚拟环境：`G:\CodexTools`
  - 任务缓存：`G:\CodexOutputs\pdf2zh-web-jobs`
  - 翻译输出：`E:\Download\PDF2ZH_Output`

如果对应盘符不存在，脚本会自动回退到当前用户目录下的 `CodexTools`、`CodexOutputs` 和 `Downloads\PDF2ZH_Output`。

## 一键安装

在 PowerShell 中进入项目目录，然后运行：

```powershell
.\install.ps1
```

安装脚本会完成这些事：

- 检测 Python 3.10+。
- 创建 `pdf2zh-venv` 虚拟环境。
- 安装 `pdf2zh`、`fastapi`、`uvicorn` 和上传文件所需依赖。
- 生成本机专用的 `local.config.ps1`。

如果想手动指定安装目录：

```powershell
.\install.ps1 `
  -InstallRoot "G:\CodexTools" `
  -JobRoot "G:\CodexOutputs\pdf2zh-web-jobs" `
  -DefaultOutput "E:\Download\PDF2ZH_Output"
```

如果机器没有 Python，脚本会尝试通过 `winget` 安装 Python 3.11。Python 本体的安装位置由 Windows/winget 决定；虚拟环境、缓存和输出仍会按上面的目录配置。

## 启动

安装完成后，双击：

```text
启动 PDF2ZH Local.bat
```

它会在后台启动本地服务，并自动打开：

```text
http://127.0.0.1:7861
```

也可以在命令行前台运行，方便查看服务日志：

```powershell
.\run.ps1
```

## 使用

1. 打开网页后上传英文论文 PDF。
2. 默认选择 `Google` 翻译服务。
3. 可按需填写页码范围，只翻译部分页面用于测试。
4. 点击 `开始翻译`。
5. 完成后下载单语中文 PDF 或中英对照 PDF。

## OpenAI 兼容服务

页面中选择 `OpenAI 兼容服务` 后填写：

- API 基础地址，例如 `https://api.openai.com/v1`
- API Key
- 模型名

API Key 只会传给当前翻译任务的后端进程，不会写入 `local.config.ps1`，也不会写入仓库。

## 常用配置

安装脚本会生成 `local.config.ps1`，其中保存本机路径：

```powershell
$env:PDF2ZH_TOOL_ROOT = "G:\CodexTools"
$env:PDF2ZH_PYTHON = "G:\CodexTools\pdf2zh-venv\Scripts\python.exe"
$env:PDF2ZH_EXE = "G:\CodexTools\pdf2zh-venv\Scripts\pdf2zh.exe"
$env:PDF2ZH_JOB_ROOT = "G:\CodexOutputs\pdf2zh-web-jobs"
$env:PDF2ZH_DEFAULT_OUTPUT = "E:\Download\PDF2ZH_Output"
```

需要迁移目录时，可以重新运行 `install.ps1`，或手动编辑 `local.config.ps1`。

## 项目结构

```text
.
├─ app.py                    # FastAPI 后端，负责上传、任务状态、调用 pdf2zh
├─ static/                   # 前端页面、样式和图标
├─ scripts/
│  ├─ env.ps1                # 运行时加载本机路径配置
│  └─ setup.ps1              # 一键安装 pdf2zh 环境
├─ install.ps1               # setup.ps1 的便捷入口
├─ launch.ps1                # 后台启动服务并打开浏览器
├─ run.ps1                   # 前台启动服务
└─ 启动 PDF2ZH Local.bat      # 双击启动入口
```

## 说明

PDF 版面恢复、公式保留和图片保留能力来自 `pdf2zh` / PDFMathTranslate。本项目主要提供本地网页、任务管理、路径配置和 Windows 启动脚本。
