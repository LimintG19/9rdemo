#!/bin/sh
set -e

echo "=== FreeLLMAPI Dataset Persistence Manager ==="

# 使用虚拟环境中的 Python（PATH 已在 Dockerfile 中设置）
# 如需额外安装，也用 /opt/venv/bin/pip，但 Dockerfile 中已预装 huggingface-hub

# 1. 启动时：从 Dataset 还原数据库
python3 /app/backup_manager.py restore

# 2. 启动后台备份守护进程
python3 /app/backup_manager.py daemon &
BACKUP_PID=$!
echo "Backup daemon started (PID: $BACKUP_PID, mode: ${BACKUP_MODE:-scheduled})"

# 3. 捕获终止信号，优雅关闭时执行最终备份
cleanup() {
    echo "Shutdown signal received, running final backup..."
    python3 /app/backup_manager.py backup || true
    kill $BACKUP_PID 2>/dev/null || true
    wait $BACKUP_PID 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

# 4. 启动 FreeLLMAPI（前台进程）
echo "Starting FreeLLMAPI..."
exec node server/dist/index.js