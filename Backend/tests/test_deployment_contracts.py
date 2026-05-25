from __future__ import annotations

from pathlib import Path

import pytest

from infra.scripts.update_caddy_site_block import extract_site_block, replace_or_append_site_block

ROOT = Path(__file__).resolve().parents[2]
SITE_HEADER = "life.dock108.dev"
PUBLIC_HEALTHZ_CURL = "curl -fsS https://life.dock108.dev/healthz"
PUBLIC_HEALTHZ_RESOLVE = '-k -fsS --resolve "life.dock108.dev:443:${DEPLOY_HOST}"'
SOURCE_BLOCK = """life.dock108.dev {
\tencode gzip

\theader {
\t\tX-Frame-Options "DENY"
\t}

\treverse_proxy 127.0.0.1:8787
}
"""


def read_repo_file(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def test_caddy_helper_extracts_site_block_with_nested_directives() -> None:
    content = f"""
# Shared host config.

{SOURCE_BLOCK}

other.example.test {{
\trespond "ok"
}}
"""

    assert extract_site_block(content, SITE_HEADER) == SOURCE_BLOCK


def test_caddy_helper_replaces_standalone_site_block_and_preserves_neighbors() -> None:
    target = """other.example.test {
\trespond "before"
}

life.dock108.dev {
\treverse_proxy 127.0.0.1:9999
}

another.example.test {
\trespond "after"
}
"""

    updated = replace_or_append_site_block(target, SITE_HEADER, SOURCE_BLOCK)

    assert 'other.example.test {\n\trespond "before"\n}' in updated
    assert SOURCE_BLOCK in updated
    assert "127.0.0.1:9999" not in updated
    assert 'another.example.test {\n\trespond "after"\n}' in updated


def test_caddy_helper_appends_when_standalone_site_block_is_absent() -> None:
    target = """other.example.test {
\trespond "ok"
}

# life.dock108.dev is intentionally managed elsewhere.
"""

    updated = replace_or_append_site_block(target, SITE_HEADER, SOURCE_BLOCK)

    assert updated == (
        """other.example.test {
\trespond "ok"
}

# life.dock108.dev is intentionally managed elsewhere.

"""
        + SOURCE_BLOCK
    )


def test_caddy_helper_rejects_malformed_source_block() -> None:
    source = """life.dock108.dev {
\theader {
\t\tX-Frame-Options "DENY"
}
"""

    with pytest.raises(RuntimeError, match="closing brace"):
        extract_site_block(source, SITE_HEADER)


def test_caddy_helper_rejects_malformed_target_block() -> None:
    target = """life.dock108.dev {
\theader {
\t\tX-Frame-Options "DENY"
}
"""

    with pytest.raises(RuntimeError, match="unmatched braces"):
        replace_or_append_site_block(target, SITE_HEADER, SOURCE_BLOCK)


def test_caddy_helper_requires_standalone_safe_target_header_shape() -> None:
    target = """https://life.dock108.dev {
\trespond "prefixed header must not be rewritten"
}

life.dock108.dev, www.life.dock108.dev {
\trespond "combined header must not be rewritten"
}
"""

    updated = replace_or_append_site_block(target, SITE_HEADER, SOURCE_BLOCK)

    assert 'respond "prefixed header must not be rewritten"' in updated
    assert 'respond "combined header must not be rewritten"' in updated
    assert updated.endswith("\n" + SOURCE_BLOCK)


def test_caddy_helper_rejects_header_without_same_line_opening_brace() -> None:
    source = """life.dock108.dev
{
\treverse_proxy 127.0.0.1:8787
}
"""

    with pytest.raises(RuntimeError, match="opening brace"):
        extract_site_block(source, SITE_HEADER)


def test_backend_deploy_validates_and_reloads_caddy_before_continuing() -> None:
    text = read_repo_file(".github/workflows/backend-ci-cd.yml")

    assert 'if [ "${GH_EVENT_NAME:-}" = "workflow_dispatch" ]; then' in text
    update = text.index("update_caddy_site_block.py")
    validate = text.index("sudo caddy validate --config /etc/caddy/Caddyfile")
    reload = text.index("sudo systemctl reload caddy")
    env_check = text.index('if [ ! -f "Backend/.env" ]; then')

    assert update < validate < reload < env_check


def test_backend_deploy_smokes_public_health_after_container_health() -> None:
    text = read_repo_file(".github/workflows/backend-ci-cd.yml")

    container_health = text.index('FINAL_STATUS=$(docker inspect lifeorganize-api')
    image_sha = text.index('echo "Verifying container image SHA..."')
    public_smoke = text.index('echo "Verifying public health endpoint..."')
    cleanup = text.index('echo "Post-deploy cleanup..."')

    assert PUBLIC_HEALTHZ_CURL in text
    assert PUBLIC_HEALTHZ_RESOLVE in text
    assert "DEPLOY_HOST: ${{ secrets.DEPLOY_HOST }}" in text
    assert "DEPLOY_HOST" in text[text.index("envs:") :]
    assert container_health < image_sha < public_smoke < cleanup
    assert 'json.load(sys.stdin) == {"ok": True}' in text


def test_backend_deploy_exposes_stable_prod_healthz_smoke_status() -> None:
    text = read_repo_file(".github/workflows/backend-ci-cd.yml")

    smoke_job = text.index("prod-healthz-smoke:")
    smoke_name = text.index("name: prod / healthz smoke", smoke_job)
    needs_deploy = text.index("needs: deploy", smoke_job)
    curl = text.index(PUBLIC_HEALTHZ_CURL, smoke_job)
    forced_resolve = text.index(PUBLIC_HEALTHZ_RESOLVE, smoke_job)

    assert smoke_job < smoke_name < needs_deploy < curl
    assert curl < forced_resolve


def test_recent_image_workflow_requires_explicit_migration_approval() -> None:
    text = read_repo_file(".github/workflows/deploy-recent-image.yml")

    assert "run_migrations:" in text
    assert "default: false" in text
    assert "RUN_MIGRATIONS: ${{ github.event.inputs.run_migrations }}" in text
    assert 'if [ "${RUN_MIGRATIONS}" = "true" ]; then' in text
    assert "Schema compatibility was checked; running migrations" in text

    migrate = text.index("docker compose --env-file ../.env --profile prod run --rm migrate")
    start = text.index("docker compose --env-file ../.env --profile prod up -d")
    assert migrate < start


def test_recent_image_workflow_smokes_public_health_after_container_health() -> None:
    text = read_repo_file(".github/workflows/deploy-recent-image.yml")

    container_health = text.index('FINAL_STATUS=$(docker inspect lifeorganize-api')
    public_smoke = text.index('echo "Verifying public health endpoint..."')
    compose_status = text.index("docker compose --env-file ../.env --profile prod ps")

    assert PUBLIC_HEALTHZ_CURL in text
    assert PUBLIC_HEALTHZ_RESOLVE in text
    assert "DEPLOY_HOST: ${{ secrets.DEPLOY_HOST }}" in text
    assert container_health < public_smoke < compose_status
    assert 'json.load(sys.stdin) == {"ok": True}' in text


def test_recent_image_workflow_updates_caddy_before_selected_image_deploy() -> None:
    text = read_repo_file(".github/workflows/deploy-recent-image.yml")

    update = text.index("update_caddy_site_block.py")
    validate = text.index("sudo caddy validate --config /etc/caddy/Caddyfile")
    reload = text.index("sudo systemctl reload caddy")
    pull = text.index("docker compose --env-file ../.env --profile prod pull --policy always")

    assert update < validate < reload < pull


def test_compose_keeps_runtime_migrations_out_of_api_startup() -> None:
    compose = read_repo_file("Backend/infra/docker-compose.yml")
    recent_workflow = read_repo_file(".github/workflows/deploy-recent-image.yml")

    assert "DEPLOY_PATH: ${{ secrets.DEPLOY_PATH }}" in recent_workflow
    assert "IMAGE_TAG: ${{ github.event.inputs.image_tag }}" in recent_workflow
    assert "docker compose --env-file ../.env --profile prod" in recent_workflow
    assert "image: ghcr.io/dock108dev/life-organize-api:${IMAGE_TAG:-latest}" in compose
    assert "RUN_MIGRATIONS: ${RUN_MIGRATIONS:-false}" in compose
    assert 'command: ["alembic", "-c", "/app/alembic.ini", "upgrade", "head"]' in compose
    assert 'RUN_MIGRATIONS: "false"' in compose
