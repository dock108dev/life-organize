# Backend Deployment

Production deployment covers only the FastAPI backend and Postgres. iOS GitHub Actions builds, tests, checks coverage, and compares screenshots, but does not sign, archive, upload, or deploy the iOS app.

The backend deployment flow is:

1. `Backend CI/CD` runs backend tests, Ruff, dependency audit, committed-secret scanning, and Python compilation.
2. Backend coverage and Docker Compose smoke run before image publishing.
3. On `main` pushes for backend paths, or manual dispatch with `full_deploy=true`, it builds and pushes `ghcr.io/dock108dev/life-organize-api:<short-sha>` and `latest`.
4. The deploy job SSHes to the server, resets the checkout in `DEPLOY_PATH` to the target branch, updates the `life.dock108.dev` Caddy site block when needed, pulls the image, runs Alembic migrations, starts Compose, waits for `lifeorganize-api` to become healthy, verifies the running image, and smokes `https://life.dock108.dev/healthz`.
5. A separate `prod / healthz smoke` job repeats the public `/healthz` check after deploy. While DNS is being created or propagated, both smoke checks fall back to `curl -k --resolve life.dock108.dev:443:$DEPLOY_HOST`.

See [Branch protection checks](branch-protection.md) for the status-check contract. Pull request protection should require only checks that run on pull requests; deploy-only checks such as `backend / docker publish`, `backend / deploy`, and `prod / healthz smoke` belong to main or deployment monitoring, not PR required checks.

## Required GitHub Secrets

- `DEPLOY_HOST`: server host, for example `37.27.222.59`.
- `DEPLOY_USER`: SSH user, for example `mike`.
- `DEPLOY_SSH_KEY`: private SSH key for the deploy user.
- `DEPLOY_PATH`: server checkout path, recommended `/opt/life-organize`.

GHCR build and deploy authentication uses the built-in `GITHUB_TOKEN`; no
custom `GHCR_TOKEN` repository secret is required.

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
Device token auto-enrollment is no longer supported. Populate expected device token hashes in `device_clients` with `status='active'`; unknown tokens are rejected.

## Caddy

`Backend/infra/Caddyfile` owns only the `life.dock108.dev` site block and routes to `127.0.0.1:8787`. On the shared SDA server this avoids colliding with SDA's API on port `8000`.

`Backend/infra/scripts/update_caddy_site_block.py` replaces or appends only the matching `life.dock108.dev` site block in the host Caddyfile.

The deploy workflow checks `sudo -n true` before updating the active Caddy config. The deploy user also needs passwordless sudo for:

- `python3 Backend/infra/scripts/update_caddy_site_block.py` when writing `/etc/caddy/Caddyfile`
- `caddy validate`
- `systemctl reload caddy`

## Manual Deploy

Deploy an existing image from GitHub Actions with `Deploy Recent Backend Image`.
Leave `run_migrations=false` for rollback-style image changes. Set
`run_migrations=true` only for normal manual deploys or after schema
compatibility has been checked.

To deploy manually on the server with migrations:

```sh
cd /opt/life-organize/Backend/infra
docker compose --env-file ../.env --profile prod pull --policy always
docker compose --env-file ../.env --profile prod run --rm migrate
docker compose --env-file ../.env --profile prod up -d --remove-orphans --force-recreate postgres api
curl -fsS https://life.dock108.dev/healthz
# If DNS/cert issuance is not live yet:
curl -k -fsS --resolve life.dock108.dev:443:37.27.222.59 https://life.dock108.dev/healthz
docker compose --env-file ../.env --profile prod ps
```

## Rollback

Use `Deploy Recent Backend Image` with a previous SHA tag and
`run_migrations=false`, or run:

```sh
cd /opt/life-organize/Backend/infra
IMAGE_TAG=<previous-sha> docker compose --env-file ../.env --profile prod pull --policy always
IMAGE_TAG=<previous-sha> docker compose --env-file ../.env --profile prod up -d --remove-orphans --force-recreate api
curl -fsS https://life.dock108.dev/healthz
# If DNS/cert issuance is not live yet:
curl -k -fsS --resolve life.dock108.dev:443:37.27.222.59 https://life.dock108.dev/healthz
```

Only run migrations during rollback when the schema compatibility has been checked.
