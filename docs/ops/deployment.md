# Backend Deployment

Production deploys only the FastAPI backend and Postgres. iOS CI/CD is intentionally out of scope.

The deployment flow mirrors the sports-data-admin backend:

1. `Backend CI/CD` runs backend tests, Ruff, and Python compilation.
2. On `main` pushes, or manual dispatch with `full_deploy=true`, it builds `ghcr.io/dock108dev/life-organize-api:<sha>` and `latest`.
3. The deploy job SSHes to the server, syncs the repo into `DEPLOY_PATH`, optionally updates the `life.dock108.dev` Caddy site block, pulls the image, runs migrations, starts Compose, and waits for `lifeorganize-api` to become healthy.

## Required GitHub Secrets

- `GHCR_TOKEN`: token with package read/write and repository read access.
- `DEPLOY_HOST`: server host, for example `37.27.222.59`.
- `DEPLOY_USER`: SSH user, for example `mike`.
- `DEPLOY_SSH_KEY`: private SSH key for the deploy user.
- `DEPLOY_PATH`: server checkout path, recommended `/opt/life-organize`.

## Required Server Files

Create `Backend/.env` in `DEPLOY_PATH` on the server. It is intentionally not committed.

```sh
ENVIRONMENT=production
POSTGRES_DB=lifeorganize
POSTGRES_USER=lifeorganize
POSTGRES_PASSWORD=<strong-password>
POSTGRES_PORT=5433
API_PORT=8787
RUN_MIGRATIONS=false

OPENAI_API_KEY=<provider-key>
OPENAI_MODEL=gpt-5.5
LIFE_ORGANIZE_ADMIN_API_KEY=<admin-key>
DEVICE_TOKEN_SIGNING_SECRET=<long-random-secret>
DEVICE_RATE_LIMIT_REQUESTS=60
DEVICE_RATE_LIMIT_WINDOW_SECONDS=3600
```

The Compose file uses the internal database URL automatically, so `DATABASE_URL` is optional for Docker deploys.

## Caddy

`Backend/infra/Caddyfile` owns only the `life.dock108.dev` site block and routes to `127.0.0.1:8787`. On the shared SDA server this avoids colliding with SDA's API on port `8000`.

The deploy user needs passwordless sudo for:

- `python3` when writing `/etc/caddy/Caddyfile`
- `caddy validate`
- `systemctl reload caddy`

## Manual Deploy

Deploy the latest image from GitHub Actions with `Deploy Recent Backend Image`, or run the equivalent server commands:

```sh
cd /opt/life-organize/Backend/infra
docker compose --env-file ../.env --profile prod pull --policy always
docker compose --env-file ../.env --profile prod run --rm migrate
docker compose --env-file ../.env --profile prod up -d --remove-orphans --force-recreate postgres api
docker compose --env-file ../.env --profile prod ps
```

## Rollback

Use `Deploy Recent Backend Image` with a previous SHA tag, or run:

```sh
cd /opt/life-organize/Backend/infra
IMAGE_TAG=<previous-sha> docker compose --env-file ../.env --profile prod pull --policy always
IMAGE_TAG=<previous-sha> docker compose --env-file ../.env --profile prod up -d --remove-orphans --force-recreate api
```

Only run migrations during rollback when the schema compatibility has been checked.
