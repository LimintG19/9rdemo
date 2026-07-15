---
title: FreeLLMAPI with Dataset Persistence
emoji: 🔥
colorFrom: indigo
colorTo: red
sdk: docker
pinned: false
---

Check out the configuration reference at https://huggingface.co/docs/hub/spaces-config-reference

# FreeLLMAPI with Dataset Persistence

在 [Hugging Face Spaces](https://huggingface.co/spaces) 上部署的 [FreeLLMAPI](https://github.com/tashfeenahmed/freellmapi)，使用 **Private Dataset** 实现 SQLite 数据库的持久化备份与自动恢复。

> **FreeLLMAPI** 是一个 OpenAI 兼容的代理服务，将 16+ 家 LLM 提供商的免费额度聚合到单个 `/v1/chat/completions` 端点，支持智能路由、自动故障转移和加密密钥存储。

---

## ✨ 特性

- **OpenAI 兼容** — 直接替换 `base_url` 即可使用任何 OpenAI SDK
- **16+ 免费提供商** — Google、Groq、Cerebras、SambaNova、Mistral、OpenRouter、GitHub Models、Cloudflare、Cohere、NVIDIA、HuggingFace、Z.ai、Ollama 等
- **智能路由** — 自动选择可用模型，速率限制时自动故障转移
- **加密存储** — 上游 API Key 使用 AES-256-GCM 加密后存入 SQLite
- **Dataset 持久化** — 利用 Hugging Face Dataset 免费存储空间，实现：
  - 启动时自动从 Dataset 恢复数据库
  - 定时备份（Scheduled）或即时检测备份（Realtime）
  - SQLite 一致性快照（`sqlite3 .backup`），避免并发冲突
  - 自动清理历史备份，保留指定数量

---

## 🚀 快速开始

### 1. 创建 Private Dataset（用于备份）

1. 访问 [huggingface.co/new-dataset](https://huggingface.co/new-dataset)
2. 命名格式：`你的用户名/freellmapi-db`
3. **License**: 任意（如 `apache-2.0`）
4. ✅ **勾选 Private**，确保数据安全
5. 创建后无需上传任何文件，保持空仓库即可

### 2. 创建 Hugging Face Space

1. 点击头像 → **New Space**
2. 填写名称，**SDK** 选择 `Docker`
3. **Space hardware** 保持默认免费 CPU（2vCPU / 16GB RAM）
4. 点击 **Create Space**
5. 将本项目的 `Dockerfile`、`entrypoint.sh`、`backup_manager.py` 上传至 Space 文件目录

### 3. 配置环境变量（Secrets）

进入 Space → **Settings → Variables and secrets**，添加以下变量：

| 变量名 | 必填 | 说明 |
|--------|:----:|------|
| `HF_TOKEN` | ✅ | Hugging Face Access Token（需 `write` 权限） |
| `HF_DATASET_REPO` | ✅ | 备份 Dataset 仓库名，如 `username/freellmapi-db` |
| `ENCRYPTION_KEY` | ✅ | 64 位十六进制字符串，用于 AES-256-GCM 加密 |
| `BACKUP_MODE` | ❌ | `scheduled`（定时，默认）或 `realtime`（即时检测） |
| `BACKUP_INTERVAL` | ❌ | 定时备份间隔（秒），默认 `300`（5 分钟） |
| `REALTIME_CHECK_INTERVAL` | ❌ | 即时模式检测间隔（秒），默认 `30` |
| `MIN_BACKUP_INTERVAL` | ❌ | 即时模式最小备份间隔（秒），默认 `60` |
| `KEEP_BACKUPS` | ❌ | 保留历史备份数量，默认 `10` |

#### 生成 ENCRYPTION_KEY

在本地终端执行：

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

将输出的 64 位字符串填入 `ENCRYPTION_KEY`。

> ⚠️ **务必保存好此密钥**。Space 重建后必须使用相同的 `ENCRYPTION_KEY`，否则已加密的 Provider API Key 将无法解密。

---

## 📦 备份系统说明

### 数据库文件

FreeLLMAPI 的 SQLite 数据库文件名为 **`freeapi.db`**，位于 `/app/server/data/` 目录下。

### 启动流程

```
Space 启动
  ├── 检测 Dataset 中是否存在 freeapi.db
  │     ├── 存在 → 下载到本地 /app/server/data/freeapi.db
  │     └── 不存在 → 继续启动（首次运行）
  ├── 启动后台备份守护进程
  └── 启动 FreeLLMAPI 服务
```

### 备份模式

#### 模式一：Scheduled（定时备份，默认）

每隔固定时间执行一次完整备份，无论数据是否变化。

- 适合：配置不常变动的场景
- 配置：`BACKUP_MODE=scheduled`, `BACKUP_INTERVAL=300`

#### 模式二：Realtime（即时检测备份）

持续检测数据库文件变化，仅在检测到变化且超过最小间隔时触发备份。

- 适合：频繁使用 Playground、Analytics 或经常修改配置的场景
- 配置：`BACKUP_MODE=realtime`, `CHECK_INTERVAL=30`, `MIN_BACKUP_INTERVAL=60`

### 备份内容

每次备份会同时上传两个文件到 Dataset：

1. **`freeapi.db`** — 主恢复文件，始终覆盖，用于下次启动自动还原
2. **`freeapi.db.YYYYMMDD_HHMMSS`** — 带时间戳的历史版本，用于手动回滚

### 自动清理

系统会自动清理旧的历史备份文件，只保留最新的 `KEEP_BACKUPS` 个（默认 10 个）。清理操作在每次备份后执行。

### 一致性保证

备份时优先使用 `sqlite3 .backup` 命令创建一致性快照，避免在并发写入时复制到损坏的数据库。如果 `sqlite3` CLI 不可用，则回退到文件复制（FreeLLMAPI 为单进程应用，风险可控）。

### 优雅关闭

Space 收到终止信号（SIGTERM/SIGINT）时，会执行一次最终备份，最大限度减少数据丢失。

---

## 🔧 使用指南

### 首次配置

1. 部署成功后，打开 Space 提供的 URL（如 `https://用户名-space名.hf.space`）
2. 首次访问需要设置管理员邮箱和密码（FreeLLMAPI 内置的单用户认证）
3. 进入 **Keys** 页面，添加各 LLM 提供商的 API Key
4. 在 **Fallback** 页面调整模型路由优先级
5. 从 **Keys** 页面头部复制统一的 `freellmapi-…` API Key

### API 调用示例

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://你的用户名-space名.hf.space/v1",
    api_key="freellmapi-你的统一密钥",
)

resp = client.chat.completions.create(
    model="auto",  # 让路由器自动选择
    messages=[{"role": "user", "content": "Hello!"}],
)
print(resp.choices[0].message.content)
```

```bash
curl https://你的用户名-space名.hf.space/v1/chat/completions   -H "Authorization: Bearer freellmapi-你的统一密钥"   -H "Content-Type: application/json"   -d '{"model": "auto", "messages": [{"role": "user", "content": "hi"}]}'
```

---

## 🔄 手动恢复旧版本

如果当前数据库损坏或误删配置，可以从 Dataset 历史版本中恢复：

1. 访问 `https://huggingface.co/datasets/你的用户名/freellmapi-db`
2. 进入 **Files and versions** → 点击某个历史备份（如 `freeapi.db.20250606_143000`）
3. 下载到本地，重新上传为 `freeapi.db` 覆盖当前版本
4. 重启 Space 即可还原到该时间点

---

## ⚠️ 注意事项

1. **单用户设计** — FreeLLMAPI 没有多租户认证，请勿将 Dashboard 暴露给不可信用户。建议将 Space 设为 **Private**。
2. **数据隐私** — 虽然 API Key 值已加密，但数据库元数据仍应通过 Private Dataset 保护。
3. **免费限制** — Hugging Face 免费 Space 在不活跃后会进入睡眠状态，首次访问需等待 10-30 秒冷启动。
4. **并发风险** — 虽然备份使用 `sqlite3 .backup` 创建一致性快照，但 Space 被强制 kill 时仍可能丢失最后一次备份后的数据（取决于备份间隔）。
5. **不要修改 `PORT`** — Dockerfile 中已固定为 `7860`，这是 Hugging Face Spaces Docker 模式的强制要求。

---

## 📁 文件说明

| 文件 | 说明 |
|------|------|
| `Dockerfile` | 构建 Node.js 环境 + Python 虚拟环境 + 预装依赖 |
| `entrypoint.sh` | 启动入口：还原 → 启动守护进程 → 启动主服务 |
| `backup_manager.py` | 备份引擎：还原、备份（快照+上传）、清理、双模式守护 |

---

## 📝 技术栈

- **后端**: Node.js 20 + Express + TypeScript + Drizzle ORM
- **数据库**: SQLite (better-sqlite3) + Dataset 持久化
- **前端**: React 19 + Vite + Tailwind CSS
- **备份**: Python 3 + huggingface-hub + sqlite3 CLI

---

## 🔗 相关链接

- **FreeLLMAPI 源码**: [github.com/tashfeenahmed/freellmapi](https://github.com/tashfeenahmed/freellmapi)
- **Hugging Face Spaces 文档**: [huggingface.co/docs/hub/spaces](https://huggingface.co/docs/hub/spaces)
- **Hugging Face Datasets 文档**: [huggingface.co/docs/hub/datasets](https://huggingface.co/docs/hub/datasets)

---

*本项目基于 FreeLLMAPI 开源协议，Dataset 持久化模块为独立扩展。*

