#!/bin/sh
set -eu

umask 077

required_secret() {
  name="$1"
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "missing required Space secret: $name" >&2
    exit 1
  fi
}

yaml_quote() {
  printf '%s' "$1" | sed "s/'/''/g"
}

required_secret GROK2API_JWT_SECRET
required_secret GROK2API_CREDENTIAL_KEY
required_secret GROK2API_ADMIN_PASSWORD

database_dsn="${GROK2API_DATABASE_DSN:-${ACCOUNT_POSTGRESQL_URL:-}}"
if [ -z "$database_dsn" ]; then
  echo "missing PostgreSQL Space secret: set GROK2API_DATABASE_DSN or keep ACCOUNT_POSTGRESQL_URL" >&2
  exit 1
fi

# v2 used SQLAlchemy's postgresql+asyncpg URL; pgx expects a standard URL.
case "$database_dsn" in
  postgresql+asyncpg://*) database_dsn="postgres://${database_dsn#postgresql+asyncpg://}" ;;
  postgresql://*) database_dsn="postgres://${database_dsn#postgresql://}" ;;
esac

admin_username="${GROK2API_ADMIN_USERNAME:-admin}"
public_url="${GROK2API_PUBLIC_URL:-https://xingshang3084-grok2api.hf.space}"

mkdir -p /run/grok2api /tmp/grok2api-media
chown grok2api:grok2api /tmp/grok2api-media

cat > /run/grok2api/config.yaml <<EOF
server:
  listen: "127.0.0.1:8001"
secrets:
  jwtSecret: '$(yaml_quote "$GROK2API_JWT_SECRET")'
  credentialEncryptionKey: '$(yaml_quote "$GROK2API_CREDENTIAL_KEY")'
bootstrapAdmin:
  username: '$(yaml_quote "$admin_username")'
  password: '$(yaml_quote "$GROK2API_ADMIN_PASSWORD")'
frontend:
  publicApiBaseURL: '$(yaml_quote "$public_url")'
database:
  driver: postgres
  postgres:
    dsn: '$(yaml_quote "$database_dsn")'
    maxOpenConns: 8
    maxIdleConns: 4
auth:
  secureCookies: true
media:
  local:
    path: "/tmp/grok2api-media"
EOF

/usr/local/bin/grok2api-entrypoint "$@" &
app_pid=$!

nginx -g 'daemon off;' &
proxy_pid=$!

terminate() {
  kill -TERM "$app_pid" "$proxy_pid" 2>/dev/null || true
}
trap terminate TERM INT

set +e
wait "$app_pid"
status=$?
set -e
kill -TERM "$proxy_pid" 2>/dev/null || true
wait "$proxy_pid" 2>/dev/null || true
exit "$status"
