"""Fixed-host, GET-only Binance Spot and standard USD-M transport."""

from __future__ import annotations

import hashlib
import hmac
import http.client
import json
import re
import threading
import time
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any, Callable
from urllib.parse import urlencode

from ..okx import _HTTPSConnectionPool
from .contracts import AdapterError


_PRODUCTS = frozenset({"SPOT", "USD_M"})
_ENDPOINTS = {
    "SPOT": frozenset({
        ("GET", "/api/v3/time", False),
        ("GET", "/api/v3/account", True),
        ("GET", "/sapi/v1/account/apiRestrictions", True),
        ("GET", "/api/v3/openOrders", True),
        ("GET", "/api/v3/exchangeInfo", False),
        ("GET", "/api/v3/ticker/price", False),
    }),
    "USD_M": frozenset({
        ("GET", "/fapi/v1/time", False),
        ("GET", "/fapi/v2/account", True),
        ("GET", "/fapi/v2/balance", True),
        ("GET", "/fapi/v2/positionRisk", True),
        ("GET", "/fapi/v1/openOrders", True),
        ("GET", "/fapi/v1/exchangeInfo", False),
        ("GET", "/fapi/v1/ticker/price", False),
    }),
}
_HOSTS = {
    "live": {"SPOT": "api.binance.com", "USD_M": "fapi.binance.com"},
    "demo": {"SPOT": "demo-api.binance.com", "USD_M": "demo-fapi.binance.com"},
}
_SAFE_RETRY_AFTER = re.compile(r"[0-9]{1,6}\Z")
_CLOCK_OFFSET_TTL_SECONDS = 30.0


class BinanceTransportError(AdapterError):
    """Sanitized Binance error that never carries the response body."""


class BinanceTransport:
    """Signer and bounded transport for the documented read endpoint allowlist."""

    MAX_RESPONSE_BYTES = 2 * 1024 * 1024
    CONNECTION_TIMEOUT_SECONDS = 10
    MAX_CONNECTIONS_PER_HOST = 4
    RECV_WINDOW_MS = 5000

    def __init__(
        self,
        api_key: str,
        api_secret: str,
        *,
        environment: str,
        region: str,
        transport: Callable[[str, str, dict[str, str], bytes | None], Any] | None = None,
        clock: Callable[[], float] = time.time,
        monotonic_clock: Callable[[], float] = time.monotonic,
    ):
        if environment not in _HOSTS or region != "global":
            raise AdapterError(400, "connection_invalid", "The exchange route is unsupported.")
        if not isinstance(api_key, str) or len(api_key) > 256:
            raise AdapterError(400, "connection_invalid", "Exchange credentials are unavailable.")
        if not isinstance(api_secret, str) or len(api_secret) > 512:
            raise AdapterError(400, "connection_invalid", "Exchange credentials are unavailable.")
        self._api_key = api_key
        try:
            self._api_key.encode("ascii", "strict")
            self._api_secret = api_secret.encode("ascii", "strict")
        except UnicodeEncodeError:
            raise AdapterError(400, "connection_invalid", "Exchange credentials are unavailable.") from None
        self.environment = environment
        self.region = region
        self._transport = transport
        self._clock = clock
        self._monotonic = monotonic_clock
        self._pools: dict[str, _HTTPSConnectionPool] = {}
        self._pool_lock = threading.Lock()
        self._offsets: dict[str, tuple[float, int]] = {}
        self._offset_lock = threading.Lock()

    def host_for(self, product: str) -> str:
        if product not in _PRODUCTS:
            raise AdapterError(400, "unsupported_product", "The exchange product is unsupported.")
        return _HOSTS[self.environment][product]

    def get(
        self,
        product: str,
        path: str,
        params: dict[str, Any] | None = None,
        *,
        signed: bool = False,
        method: str = "GET",
    ) -> Any:
        method = method.upper() if isinstance(method, str) else ""
        endpoint = (method, path, bool(signed))
        if product not in _PRODUCTS or endpoint not in _ENDPOINTS[product]:
            raise AdapterError(422, "capability_unsupported", "The requested exchange read is unsupported.")
        if method != "GET":
            raise AdapterError(422, "capability_unsupported", "This exchange adapter is read-only.")
        if signed and (not self._api_key or not self._api_secret):
            raise AdapterError(422, "capability_unsupported", "Private exchange credentials are unavailable.")
        query_values = self._query_values(params or {})
        if signed:
            offset = self._server_offset(product)
            query_values.update({
                "recvWindow": str(self.RECV_WINDOW_MS),
                "timestamp": str(int(self._clock() * 1000) + offset),
            })
            canonical = urlencode(sorted(query_values.items()), doseq=False)
            signature = hmac.new(self._api_secret, canonical.encode("ascii"), hashlib.sha256).hexdigest()
            request_path = f"{path}?{canonical}&signature={signature}"
            headers = {
                "Accept": "application/json",
                "X-MBX-APIKEY": self._api_key,
                "User-Agent": "trading-balance-private-api/1.0",
            }
        else:
            request_path = path + ("?" + urlencode(sorted(query_values.items()), doseq=False) if query_values else "")
            headers = {"Accept": "application/json", "User-Agent": "trading-balance-private-api/1.0"}
        try:
            payload = self._send(product, method, request_path, headers)
        except BinanceTransportError:
            raise
        except (OSError, http.client.HTTPException, TimeoutError):
            raise BinanceTransportError(502, "exchange_unavailable", "The exchange read is unavailable.") from None
        if isinstance(payload, dict) and payload.get("code") is not None:
            code = payload.get("code")
            if isinstance(code, (str, int)) and str(code).startswith("-"):
                raise BinanceTransportError(502, "exchange_rejected", "The exchange read was rejected.")
        return payload

    @staticmethod
    def _query_values(params: dict[str, Any]) -> dict[str, str]:
        if not isinstance(params, dict) or len(params) > 16:
            raise AdapterError(400, "invalid_query", "The exchange query is invalid.")
        values: dict[str, str] = {}
        for key, value in params.items():
            if not isinstance(key, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9]{0,31}", key):
                raise AdapterError(400, "invalid_query", "The exchange query is invalid.")
            if isinstance(value, bool) or not isinstance(value, (str, int)):
                raise AdapterError(400, "invalid_query", "The exchange query is invalid.")
            token = str(value)
            if len(token) > 256 or "\x00" in token:
                raise AdapterError(400, "invalid_query", "The exchange query is invalid.")
            values[key] = token
        return values

    def _server_offset(self, product: str) -> int:
        now = self._monotonic()
        with self._offset_lock:
            cached = self._offsets.get(product)
            if cached is not None and cached[0] > now:
                return cached[1]
        path = "/api/v3/time" if product == "SPOT" else "/fapi/v1/time"
        started = self._clock()
        payload = self.get(product, path)
        finished = self._clock()
        if (
            not isinstance(payload, dict)
            or isinstance(payload.get("serverTime"), bool)
            or not isinstance(payload.get("serverTime"), int)
            or payload["serverTime"] <= 0
        ):
            raise BinanceTransportError(502, "clock_unavailable", "Exchange clock synchronization is unavailable.")
        midpoint_ms = int(((started + finished) / 2) * 1000)
        offset = payload["serverTime"] - midpoint_ms
        if abs(offset) > 300_000:
            raise BinanceTransportError(502, "clock_unavailable", "Exchange clock synchronization is unavailable.")
        with self._offset_lock:
            self._offsets[product] = (self._monotonic() + _CLOCK_OFFSET_TTL_SECONDS, offset)
        return offset

    def _send(self, product: str, method: str, request_path: str, headers: dict[str, str]) -> Any:
        if self._transport is not None:
            return self._transport(method, request_path, headers, None)
        host = self.host_for(product)
        with self._pool_lock:
            pool = self._pools.get(host)
            if pool is None:
                pool = _HTTPSConnectionPool(
                    host,
                    timeout=self.CONNECTION_TIMEOUT_SECONDS,
                    max_connections=self.MAX_CONNECTIONS_PER_HOST,
                )
                self._pools[host] = pool
        connection = None
        discard = True
        try:
            connection = pool.acquire()
            connection.request(method, request_path, headers=headers)
            response = connection.getresponse()
            body = response.read(self.MAX_RESPONSE_BYTES + 1)
            if len(body) > self.MAX_RESPONSE_BYTES:
                raise BinanceTransportError(502, "response_oversized", "The exchange response is unavailable.")
            retry_after = self._retry_after(response.getheader("Retry-After"))
            if response.status < 200 or response.status >= 300:
                status = 429 if response.status == 429 else 502
                code = "rate_limited" if response.status == 429 else "exchange_rejected"
                raise BinanceTransportError(
                    status, code, "The exchange read is unavailable.", retry_after=retry_after
                )
            try:
                decoded = json.loads(body.decode("utf-8"))
            except (UnicodeError, json.JSONDecodeError):
                raise BinanceTransportError(502, "malformed_response", "The exchange response is unavailable.") from None
            if not isinstance(decoded, (dict, list)):
                raise BinanceTransportError(502, "malformed_response", "The exchange response is unavailable.")
            discard = bool(getattr(response, "will_close", False))
            return decoded
        except BinanceTransportError:
            raise
        except (OSError, http.client.HTTPException, TimeoutError):
            raise BinanceTransportError(502, "exchange_unavailable", "The exchange read is unavailable.") from None
        finally:
            if connection is not None:
                pool.release(connection, discard=discard)

    @staticmethod
    def _retry_after(value: Any) -> str | None:
        if isinstance(value, str) and _SAFE_RETRY_AFTER.fullmatch(value.strip()):
            return value.strip()
        if isinstance(value, str):
            try:
                parsed = parsedate_to_datetime(value)
                if parsed.tzinfo is None:
                    parsed = parsed.replace(tzinfo=timezone.utc)
                seconds = max(0, min(86_400, int((parsed - datetime.now(timezone.utc)).total_seconds())))
                return str(seconds) if seconds else None
            except (TypeError, ValueError, OverflowError):
                return None
        return None
