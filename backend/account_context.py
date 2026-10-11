"""Verified, per-connection OKX account contexts for v2 private work."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .exchanges import AdapterError, BinanceSpotAdapter, BinanceTransport, BinanceUSDMAdapter
from .okx import OKXClient, OKXError, Transport


SUPPORTED_EXCHANGES = frozenset({"OKX", "BINANCE"})
SUPPORTED_ENVIRONMENTS = frozenset({"live", "demo"})
SUPPORTED_REGIONS = frozenset({"global"})


class AccountContextError(ValueError):
    def __init__(
        self, message: str, *, status: int = 400, code: str = "verification_failed",
        headers: list[tuple[str, str]] | None = None,
    ):
        super().__init__(message)
        self.status = status
        self.code = code
        self.headers = headers or []


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


VerifiedExchangeIdentity = VerifiedOKXIdentity


@dataclass(frozen=True, slots=True)
class BinanceClientBundle:
    transport: BinanceTransport
    spot: BinanceSpotAdapter
    usdm: BinanceUSDMAdapter
    environment: str
    region: str


def create_exchange_client(
    credentials: dict[str, str],
    *,
    exchange: str,
    environment: str,
    region: str,
    transport: Any = None,
    clock: Any = None,
) -> Any:
    if exchange == "OKX":
        return create_okx_client(
            credentials, exchange=exchange, environment=environment, region=region,
            transport=transport, clock=clock,
        )
    if exchange != "BINANCE":
        raise AccountContextError("unsupported exchange")
    if environment not in SUPPORTED_ENVIRONMENTS:
        raise AccountContextError("unsupported exchange environment")
    if region not in SUPPORTED_REGIONS:
        raise AccountContextError("unsupported exchange region")
    if not isinstance(credentials, dict) or set(credentials) != {"apiKey", "apiSecret"}:
        raise AccountContextError("exchange credentials are unavailable")
    try:
        signer = BinanceTransport(
            credentials["apiKey"], credentials["apiSecret"],
            environment=environment, region=region, transport=transport,
            clock=clock if clock is not None else __import__("time").time,
        )
    except (TypeError, UnicodeError, ValueError):
        raise AccountContextError("exchange credentials or route are unavailable") from None
    return BinanceClientBundle(
        signer,
        BinanceSpotAdapter(signer, environment=environment, region=region),
        BinanceUSDMAdapter(signer, environment=environment, region=region),
        environment,
        region,
    )


def verify_exchange_identity(client: Any) -> VerifiedExchangeIdentity:
    if isinstance(client, OKXClient):
        try:
            return verify_okx_identity(client)
        except OKXError as error:
            status = 429 if error.http_status == 429 else 503
            code = "rate_limited" if status == 429 else "verification_unavailable"
            headers = [] if not error.retry_after else [("Retry-After", error.retry_after)]
            raise AccountContextError(
                "Exchange identity verification is unavailable.", status=status, code=code, headers=headers
            ) from None
    if not isinstance(client, BinanceClientBundle):
        raise AccountContextError("exchange client is unavailable")
    if client.environment == "demo":
        raise AccountContextError(
            "Binance demo private identity verification is unavailable",
            status=503,
            code="verification_unavailable",
        )
    try:
        account = client.spot.account()
        restrictions = client.spot.restrictions()
    except AdapterError as error:
        headers = [] if not error.retry_after else [("Retry-After", error.retry_after)]
        code = "rate_limited" if error.status == 429 else "verification_unavailable"
        status = 429 if error.status == 429 else 503
        raise AccountContextError(
            "Exchange identity verification is unavailable.", status=status, code=code, headers=headers
        ) from None
    uid_value = account.get("uid")
    if isinstance(uid_value, bool) or not isinstance(uid_value, (int, str)):
        raise AccountContextError("exchange account identity is unavailable")
    uid = str(uid_value)
    if not uid.isascii() or not uid.isdigit() or uid.startswith("0") or len(uid) > 20:
        raise AccountContextError("exchange account identity is unavailable")
    if restrictions.get("enableReading") is not True or restrictions.get("enableWithdrawals") is not False:
        raise AccountContextError("exchange permission metadata is unavailable")
    capabilities = ["read", "read:SPOT"]
    futures = restrictions.get("enableFutures")
    if futures is True:
        try:
            client.usdm.account()
        except AdapterError:
            # Spot-only onboarding is valid; derivative capability is not inferred.
            pass
        else:
            capabilities.append("read:USD_M")
    elif futures is not False and futures is not None:
        raise AccountContextError("exchange permission metadata is unavailable")
    return VerifiedExchangeIdentity(uid, "read", None, tuple(capabilities))


def create_okx_client(
    credentials: dict[str, str],
    *,
    exchange: str,
    environment: str,
    region: str,
    transport: Transport | None = None,
    clock: Any = None,
) -> ScopedOKXClient:
    if exchange != "OKX":
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
