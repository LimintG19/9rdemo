FROM node:26.3.0-alpine

# 安装 Python3、构建工具、sqlite3 CLI，以及 py3-virtualenv（用于创建 venv）
RUN apk add --no-cache \
    git \
    python3 \
    py3-pip \
    py3-virtualenv \
    make \
    g++ \
    sqlite

WORKDIR /app

# 克隆 FreeLLMAPI
ARG FREELLMAPI_VERSION="v0.2.8"
RUN apk add --no-cache curl && \
    curl -L "https://github.com/tashfeenahmed/freellmapi/archive/refs/tags/${FREELLMAPI_VERSION}.tar.gz" | \
    tar xz --strip-components=1

# 安装 Node 依赖并构建
RUN npm install && npm run build

# 确保数据目录存在
RUN mkdir -p /app/server/data

# 创建 Python 虚拟环境，并安装 huggingface-hub
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --upgrade pip && \
    /opt/venv/bin/pip install huggingface-hub

# 复制备份系统
COPY backup_manager.py /app/backup_manager.py
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 7860

# 默认环境变量
ENV PORT=7860
ENV NODE_ENV=production
# 改为 freeapi.db
ENV DB_PATH=/app/server/data/freeapi.db  
ENV BACKUP_MODE=scheduled
ENV BACKUP_INTERVAL=300
ENV REALTIME_CHECK_INTERVAL=30
ENV MIN_BACKUP_INTERVAL=60
ENV KEEP_BACKUPS=10
# 将 venv 加入 PATH，让 entrypoint.sh 可以直接用 python3/pip
ENV PATH="/opt/venv/bin:$PATH"

ENTRYPOINT ["/entrypoint.sh"]