---
title: Grok2Api
emoji: 📊
colorFrom: red
colorTo: red
sdk: docker
pinned: false
app_port: 8000
---

Grok2API v3 on Hugging Face Spaces, deployed from
[chenyme/grok2api](https://github.com/chenyme/grok2api).

The container is pinned to upstream commit `1a21edbf13014854655967611ffeb94855d66d5e`
and uses the Space's external PostgreSQL database. Runtime configuration is
generated from Space Secrets so credentials are not committed to this repository.

Required Space Secrets:

- `ACCOUNT_POSTGRESQL_URL` (the legacy v2 SQLAlchemy URL is converted automatically),
  or `GROK2API_DATABASE_DSN`
- `GROK2API_JWT_SECRET`
- `GROK2API_CREDENTIAL_KEY`
- `GROK2API_ADMIN_PASSWORD`

Optional Space variables:

- `GROK2API_ADMIN_USERNAME` (defaults to `admin`)
- `GROK2API_PUBLIC_URL` (defaults to this Space's public URL)
