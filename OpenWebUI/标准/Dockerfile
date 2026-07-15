FROM ghcr.io/open-webui/open-webui:main-ollama
RUN apt-get update && apt-get install -yqq --no-install-recommends \
    git python3 python3-pip coreutils socat \
 && rm -rf /var/lib/apt/lists/*
RUN pip3 install --no-cache-dir huggingface_hub --break-system-packages
COPY hf_sync.sh hf_sync.sh
RUN chmod +x hf_sync.sh

RUN \
    chmod -R 777 ./data && \
    chmod -R 777 ./open_webui && \
    sed -i "1r hf_sync.sh" ./start.sh