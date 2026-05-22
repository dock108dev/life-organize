from __future__ import annotations

from app.auth import hash_device_token


def test_hash_device_token_is_stable_and_not_raw_token() -> None:
    token = "device-token-1234567890"

    first = hash_device_token(token)
    second = hash_device_token(token)

    assert first == second
    assert token not in first
    assert len(first) == 64
