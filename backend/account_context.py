"""Verified, per-connection OKX account contexts for v2 private work."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .okx import OKXClient, Transport


SUPPORTED_EXCHANGES = frozenset({"OKX"})
SUPPORTED_ENVIRONMENTS = frozenset({"live", "demo"})
SUPPORTED_REGIONS = frozenset({"global"})


class AccountContextError(ValueError):
    pass


class ScopedOKXClient(OKXClient):
    """OKX client pinned to the fixed supported host and environment."""

    def __init__(
        self,
        api_key: str,
        api_secret: str,
        passphrase: str,
        *,
        environment: str,
        transport: Transport | None = None,
        clock: Any = None,
    ):
        if environment not in SUPPORTED_ENVIRONMENTS:
            raise AccountContextError("unsupported exchange environment")
        self.environment = environment
        options: dict[str, Any] = {"transport": transport}
        if clock is not None:
            options["clock"] = clock
        super().__init__(api_key, api_secret, passphrase, **options)

    def _signed_headers(self, method: str, request_path: str, body: bytes | None) -> dict[str, str]:
        headers = super()._signed_headers(method, request_path, body)
        if self.environment == "demo":
            headers["x-simulated-trading"] = "1"
        return headers


@dataclass(frozen=True, slots=True)
class VerifiedOKXIdentity:
    uid: str
    permission: str
    position_mode: str | None
    capabilities: tuple[str, ...]


def create_okx_client(
    credentials: dict[str, str],
    *,
    exchange: str,
    environment: str,
    region: str,
    transport: Transport | None = None,
    clock: Any = None,
) -> ScopedOKXClient:
    if exchange not in SUPPORTED_EXCHANGES:
        raise AccountContextError("unsupported exchange")
    if environment not in SUPPORTED_ENVIRONMENTS:
        raise AccountContextError("unsupported exchange environment")
    if region not in SUPPORTED_REGIONS:
        raise AccountContextError("unsupported exchange region")
    if not isinstance(credentials, dict) or set(credentials) != {"apiKey", "apiSecret", "passphrase"}:
        raise AccountContextError("exchange credentials are unavailable")
    return ScopedOKXClient(
        credentials["apiKey"], credentials["apiSecret"], credentials["passphrase"],
        environment=environment, transport=transport, clock=clock,
    )


def verify_okx_identity(client: OKXClient) -> VerifiedOKXIdentity:
    configuration = client.account_config()
    uid = configuration.get("uid")
    permission = configuration.get("perm")
    if not isinstance(uid, str) or not uid.isascii() or not uid.isdigit() or len(uid) > 128:
        raise AccountContextError("exchange account identity is unavailable")
    if not isinstance(permission, str) or len(permission) > 96:
        raise AccountContextError("exchange permission metadata is unavailable")
    permission_tokens = [part.strip() for part in permission.split(",")]
    allowed = {"read_only", "trade", "withdraw"}
    if (
        not permission_tokens
        or any(not token for token in permission_tokens)
        or len(set(permission_tokens)) != len(permission_tokens)
        or any(token not in allowed for token in permission_tokens)
        or not ("read_only" in permission_tokens or "trade" in permission_tokens)
    ):
        raise AccountContextError("exchange permission metadata is unavailable")
    if "withdraw" in permission_tokens:
        raise AccountContextError("withdraw-capable API credentials are not supported")
    capabilities = ("read", "trade") if "trade" in permission_tokens else ("read",)
    position_mode = configuration.get("posMode")
    if position_mode is not None and (not isinstance(position_mode, str) or len(position_mode) > 32):
        position_mode = None
    return VerifiedOKXIdentity(uid, permission, position_mode, capabilities)


@dataclass(frozen=True, slots=True)
class AccountContext:
    user_id: str
    connection_id: str
    exchange: str
    environment: str
    region: str
    credential_version: int
    permission_version: int
    capabilities: tuple[str, ...]
    client: ScopedOKXClient
