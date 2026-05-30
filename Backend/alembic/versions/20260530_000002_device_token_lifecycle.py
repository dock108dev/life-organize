from __future__ import annotations

import sqlalchemy as sa

from alembic import op

revision = "20260530_000002"
down_revision = "20260522_000001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "device_clients",
        sa.Column("status", sa.String(length=32), nullable=False, server_default="active"),
    )
    op.add_column("device_clients", sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column("device_clients", "revoked_at")
    op.drop_column("device_clients", "status")
