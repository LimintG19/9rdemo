FROM eceasy/cli-proxy-api-plus:latest

USER root

# 安装必要依赖
RUN apk add --no-cache bash libc6-compat gcompat

WORKDIR /app

# 复制二进制文件
RUN cp /CLIProxyAPI/CLIProxyAPIPlus ./cli-proxy-api-plus && chmod +x ./cli-proxy-api-plus

# 创建必要目录
RUN mkdir -p /tmp/.cli-proxy-api /tmp/logs /tmp/pg_cache/pgstore \
    && chmod -R 777 /tmp

# 复制配置文件
COPY config.yaml /app/config.yaml

# 关键：程序启动时需要此文件，否则报错
RUN cp /app/config.yaml /app/config.example.yaml

ENV TZ=Asia/Shanghai
EXPOSE 7860

# 直接运行，不使用 Nginx
CMD ["./cli-proxy-api-plus", "--config", "/app/config.yaml"]