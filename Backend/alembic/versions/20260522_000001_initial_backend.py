from __future__ import annotations

import sqlalchemy as sa

from alembic import op

revision = "20260522_000001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "device_clients",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("token_hash", sa.String(length=128), nullable=False),
        sa.Column(
            "first_seen_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "last_seen_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("request_count", sa.Integer(), nullable=False, server_default="0"),
        sa.UniqueConstraint("token_hash"),
    )
    op.create_index("ix_device_clients_token_hash", "device_clients", ["token_hash"])

    op.create_table(
        "ai_request_logs",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("token_hash", sa.String(length=128), nullable=False),
        sa.Column("endpoint", sa.String(length=64), nullable=False),
        sa.Column("status_code", sa.Integer(), nullable=False),
        sa.Column("latency_ms", sa.Integer(), nullable=False),
        sa.Column("model_name", sa.String(length=128), nullable=True),
        sa.Column("openai_request_id", sa.String(length=256), nullable=True),
        sa.Column("error_code", sa.String(length=64), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("notes", sa.Text(), nullable=True),
    )
    op.create_index("ix_ai_request_logs_token_hash", "ai_request_logs", ["token_hash"])
    op.create_index("ix_ai_request_logs_created_at", "ai_request_logs", ["created_at"])


def downgrade() -> None:
    op.drop_index("ix_ai_request_logs_created_at", table_name="ai_request_logs")
    op.drop_index("ix_ai_request_logs_token_hash", table_name="ai_request_logs")
    op.drop_table("ai_request_logs")
    op.drop_index("ix_device_clients_token_hash", table_name="device_clients")
    op.drop_table("device_clients")
