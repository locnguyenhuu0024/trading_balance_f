"""Fixed-host public currency-rate client with no exchange credentials."""

from __future__ import annotations

import http.client
import json
from decimal import Decimal, InvalidOperation
from typing import Any, Callable


CurrencyTransport = Callable[[str, str, dict[str, str]], dict[str, Any]]


class CurrencyClientError(RuntimeError):
    """Safe, content-free error raised for an unusable currency response."""


class CurrencyClient:
    BASE_HOST = "api.coingecko.com"
    REQUEST_PATH = "/api/v3/simple/price?ids=tether&vs_currencies=vnd"
    MAX_RESPONSE_BYTES = 64 * 1024

    def __init__(self, *, transport: CurrencyTransport | None = None):
        self._transport = transport

    def _network_transport(
        self, method: str, request_path: str, headers: dict[str, str]
    ) -> dict[str, Any]:
        connection = http.client.HTTPSConnection(self.BASE_HOST, timeout=8)
        try:
            connection.request(method, request_path, headers=headers)
            response = connection.getresponse()
            response_body = response.read(self.MAX_RESPONSE_BYTES + 1)
            if len(response_body) > self.MAX_RESPONSE_BYTES or response.status != 200:
                raise CurrencyClientError("currency source is unavailable")
            try:
                decoded = json.loads(response_body.decode("utf-8"))
            except (UnicodeError, json.JSONDecodeError):
                raise CurrencyClientError("currency source returned invalid data") from None
            if not isinstance(decoded, dict):
                raise CurrencyClientError("currency source returned invalid data")
            return decoded
        except CurrencyClientError:
            raise
        except (OSError, http.client.HTTPException, TimeoutError):
            raise CurrencyClientError("currency source is unavailable") from None
        finally:
            connection.close()

    @staticmethod
    def _rate_text(payload: Any) -> str:
        if not isinstance(payload, dict):
            raise CurrencyClientError("currency source returned invalid data")
        tether = payload.get("tether")
        if not isinstance(tether, dict):
            raise CurrencyClientError("currency source returned invalid data")
        value = tether.get("vnd")
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise CurrencyClientError("currency source returned invalid data")
        try:
            rate = Decimal(str(value))
        except (InvalidOperation, ValueError):
            raise CurrencyClientError("currency source returned invalid data") from None
        if not rate.is_finite() or rate <= 0:
            raise CurrencyClientError("currency source returned invalid data")
        return format(rate.normalize(), "f")

    def usdt_vnd_rate(self) -> str:
        transport = self._transport or self._network_transport
        try:
            payload = transport(
                "GET",
                self.REQUEST_PATH,
                {"Accept": "application/json", "User-Agent": "trading-balance-currency/1.0"},
            )
        except CurrencyClientError:
            raise
        except Exception:
            raise CurrencyClientError("currency source is unavailable") from None
        return self._rate_text(payload)
