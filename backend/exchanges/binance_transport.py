"""Fixed-host Binance transport with fixture-only native write support."""

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
        ("GET", "/fapi/v1/positionSide/dual", True),
        ("GET", "/fapi/v1/order", True),
        ("GET", "/fapi/v1/openOrders", True),
        ("GET", "/fapi/v1/exchangeInfo", False),
        ("GET", "/fapi/v1/ticker/price", False),
        ("POST", "/fapi/v1/order", True),
        ("DELETE", "/fapi/v1/order", True),
    }),
}
_WRITE_ENDPOINTS = frozenset({("POST", "/fapi/v1/order"), ("DELETE", "/fapi/v1/order")})
_WRITE_PARAMETERS = {
    ("POST", "/fapi/v1/order"): frozenset({
        "symbol", "side", "type", "quantity", "positionSide", "reduceOnly", "newClientOrderId",
    }),
    ("DELETE", "/fapi/v1/order"): frozenset({"symbol", "orderId"}),
}
_DEFINITE_503_MESSAGES = frozenset({
    "Service Unavailable.",
    "Internal error; unable to process your request. Please try again.",
})
_HOSTS = {
    "live": {"SPOT": "api.binance.com", "USD_M": "fapi.binance.com"},
    "demo": {"SPOT": "demo-api.binance.com", "USD_M": "demo-fapi.binance.com"},
}
_SAFE_RETRY_AFTER = re.compile(r"[0-9]{1,6}\Z")
_CLOCK_OFFSET_TTL_SECONDS = 30.0


class BinanceTransportError(AdapterError):
    """Sanitized Binance error that never carries the response body."""

    def __init__(
        self,
        status: int,
        code: str,
        message: str,
        *,
        retry_after: str | None = None,
        http_status: int | None = None,
        native_code: int | None = None,
        definite_failure: bool = False,
    ):
        super().__init__(status, code, message, retry_after=retry_after)
        self.http_status = http_status
        self.native_code = native_code
        self.definite_failure = definite_failure


class BinanceTransport:
    """Signer and bounded transport for Binance endpoints.

    Native writes require an explicitly injected transport; real HTTPS remains read-only.
    """

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

    @property
    def has_injected_transport(self) -> bool:
        return self._transport is not None

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
        return self.request(product, method, path, params, signed=signed)

    def post(self, product: str, path: str, params: dict[str, Any] | None = None, *, signed: bool = False) -> Any:
        return self.request(product, "POST", path, params, signed=signed)

    def delete(self, product: str, path: str, params: dict[str, Any] | None = None, *, signed: bool = False) -> Any:
        return self.request(product, "DELETE", path, params, signed=signed)

    def request(
        self,
        product: str,
        method: str,
        path: str,
        params: dict[str, Any] | None = None,
        *,
        signed: bool = False,
    ) -> Any:
        method = method.upper() if isinstance(method, str) else ""
        endpoint = (method, path, bool(signed))
        if product not in _PRODUCTS or endpoint not in _ENDPOINTS[product]:
            raise AdapterError(422, "capability_unsupported", "The requested exchange operation is unsupported.")
        if (method, path) in _WRITE_ENDPOINTS and self._transport is None:
            raise AdapterError(422, "capability_unsupported", "Native exchange writes are unavailable.")
        if method != "GET" and (method, path) not in _WRITE_ENDPOINTS:
            raise AdapterError(422, "capability_unsupported", "The requested exchange operation is unsupported.")
        if (method, path) in _WRITE_ENDPOINTS:
            allowed = _WRITE_PARAMETERS[(method, path)]
            if not isinstance(params, dict) or not set(params) <= allowed:
                raise AdapterError(400, "invalid_query", "The exchange query is invalid.")
        if signed and (not self._api_key or not self._api_secret):
            raise AdapterError(422, "capability_unsupported", "Private exchange credentials are unavailable.")
        if (method, path) in _WRITE_ENDPOINTS and not signed:
            raise AdapterError(422, "capability_unsupported", "Native exchange writes require signing.")
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
            raise BinanceTransportError(
                502, "exchange_unavailable", "The exchange operation is unavailable.",
                http_status=None, definite_failure=False,
            ) from None
        if isinstance(payload, dict) and payload.get("code") is not None:
            native_code = self._native_code(payload.get("code"))
            if native_code is not None and native_code < 0:
                raise self._operation_error(payload, http_status=200)
        return payload

    @staticmethod
    def _native_code(value: Any) -> int | None:
        if isinstance(value, bool) or not isinstance(value, (str, int)):
            return None
        token = str(value)
        if not re.fullmatch(r"-?[0-9]{1,8}", token):
            return None
        try:
            return int(token)
        except ValueError:
            return None

    @classmethod
    def _operation_error(
        cls, payload: Any, *, http_status: int | None, retry_after: str | None = None,
    ) -> BinanceTransportError:
        native_code = cls._native_code(payload.get("code")) if isinstance(payload, dict) else None
        native_message = payload.get("msg") if isinstance(payload, dict) else None
        if native_code in {-1000, -1006, -1007, -4116, -2013}:
            category, definite = "outcome_unknown", False
        elif native_code in {-1008, -2022, -4118}:
            category, definite = "exchange_rejected", True
        elif http_status == 503 and isinstance(native_message, str) and native_message in _DEFINITE_503_MESSAGES:
            category, definite = "exchange_rejected", True
        elif native_code is not None and native_code < 0:
            category, definite = "outcome_unknown", False
        elif http_status == 503 or (http_status is not None and http_status >= 500):
            category, definite = "outcome_unknown", False
        elif http_status is not None and 400 <= http_status < 500:
            category, definite = "exchange_rejected", True
        else:
            category, definite = "outcome_unknown", False
        safe_status = 429 if http_status == 429 else 502
        public_code = "rate_limited" if http_status == 429 else category
        return BinanceTransportError(
            safe_status, public_code, "The exchange operation could not be confirmed.",
            retry_after=retry_after, http_status=http_status, native_code=native_code,
            definite_failure=definite,
        )

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
        if method != "GET":
            raise BinanceTransportError(422, "capability_unsupported", "Native exchange writes are unavailable.")
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
            try:
                decoded = json.loads(body.decode("utf-8"))
            except (UnicodeError, json.JSONDecodeError):
                if response.status < 200 or response.status >= 300:
                    raise self._operation_error({}, http_status=response.status, retry_after=retry_after) from None
                raise BinanceTransportError(502, "malformed_response", "The exchange response is unavailable.") from None
            if not isinstance(decoded, (dict, list)):
                raise BinanceTransportError(502, "malformed_response", "The exchange response is unavailable.")
            if response.status < 200 or response.status >= 300:
                raise self._operation_error(decoded, http_status=response.status, retry_after=retry_after)
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
