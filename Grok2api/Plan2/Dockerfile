FROM ghcr.io/chenyme/grok2api:main@sha256:f0e228e680ab7cf9fd6b96244df49ed91609b1974836c92d84f7c515d110043b

USER root

RUN apk add --no-cache nginx

COPY nginx.conf /etc/nginx/nginx.conf
COPY --chmod=0755 start-hf.sh /usr/local/bin/start-hf

RUN nginx -t

ENTRYPOINT ["/usr/local/bin/start-hf"]
CMD ["/app/grok2api", "--config", "/app/config.yaml", "--listen", "127.0.0.1:8001"]
