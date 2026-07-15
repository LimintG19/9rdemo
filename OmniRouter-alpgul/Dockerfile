FROM node:22-bookworm-slim AS builder
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates curl && \
    rm -rf /var/lib/apt/lists/* && \
    git clone https://github.com/diegosouzapw/OmniRoute .
    
# RUN curl -o my-fix.patch https://github.com/diegosouzapw/OmniRoute/pull/123.patch && \
#     git apply --check my-fix.patch 2>/dev/null \
#     && git apply my-fix.patch \
#     || true
RUN if [ -f package-lock.json ]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi
RUN mkdir -p /app/data && npm run build

FROM node:22-bookworm-slim AS runner-base
WORKDIR /app
LABEL org.opencontainers.image.title="omniroute" \
  org.opencontainers.image.description="Unified AI proxy — route any LLM through one endpoint" \
  org.opencontainers.image.url="https://omniroute.online" \
  org.opencontainers.image.source="https://github.com/diegosouzapw/OmniRoute" \
  org.opencontainers.image.licenses="MIT"
ENV NODE_ENV=production
ENV PORT=20128
ENV HOSTNAME=0.0.0.0
ENV DATA_DIR=/app/data
RUN mkdir -p /app/data
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/.next/standalone ./
EXPOSE 20128
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:20128/api/settings').then(r=>{if(!r.ok)throw r.status}).catch(()=>process.exit(1))"
CMD ["node", "server.js"]

FROM runner-base AS runner-cli
RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && git config --system url."https://github.com/".insteadOf "ssh://git@github.com/"
RUN npm install -g --no-audit --no-fund @openai/codex @anthropic-ai/claude-code droid openclaw@latest @kilocode/cli

FROM runner-cli
# System tools
RUN apt-get update && apt-get install -yqq --no-install-recommends \
    python3 python3-pip coreutils socat \
 && rm -rf /var/lib/apt/lists/*
 # Hugging Face Hub CLI
RUN pip3 install --no-cache-dir huggingface_hub --break-system-packages
COPY --chmod=644 .env /app/.env
WORKDIR /app
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh
EXPOSE 20128
CMD ["/app/entrypoint.sh"]