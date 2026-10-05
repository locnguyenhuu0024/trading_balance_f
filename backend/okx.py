"""Small OKX REST client with injectable transport for offline tests."""

from __future__ import annotations

import base64
import datetime as dt
import hashlib
import hmac
import http.client
import json
import re
import time
from typing import Any, Callable, Optional
from urllib.parse import urlencode

from . import diagnostics


_OKX_ERROR_CODE = re.compile(r"[0-9]{1,12}\Z")


def bounded_error_code(value: Any) -> str | None:
    """Return a short numeric exchange error code without exposing response text."""
    if isinstance(value, bool) or not isinstance(value, (str, int)):
        return None
    token = str(value)
    return token if _OKX_ERROR_CODE.fullmatch(token) else None


class OKXError(RuntimeError):
    """Safe, content-free error raised for a rejected or malformed response."""

    def __init__(
        self,
        message: str,
        *,
        error_code: str | None = None,
        diagnostic_category: str | None = None,
        http_status: int | None = None,
        ack_shape: str | None = None,
    ):
        super().__init__(message)
        self.error_code = bounded_error_code(error_code)
        self.diagnostic_category = diagnostic_category
        self.http_status = http_status if isinstance(http_status, int) and not isinstance(http_status, bool) and 100 <= http_status <= 599 else None
        self.ack_shape = ack_shape


class OKXTransportError(OKXError):
    """Transport failed; callers must treat a write's outcome as unknown."""


Transport = Callable[[str, str, dict[str, str], Optional[bytes]], dict[str, Any]]


class OKXClient:
    BASE_HOST = "www.okx.com"
    MAX_RESPONSE_BYTES = 2 * 1024 * 1024

    def __init__(
        self,
        api_key: str,
        api_secret: str,
        passphrase: str,
        *,
        transport: Transport | None = None,
        clock: Callable[[], float] = time.time,
    ):
        self._api_key = api_key
        self._api_secret = api_secret
        self._passphrase = passphrase
        self._transport = transport
        self._clock = clock

    def _timestamp(self) -> str:
        value = dt.datetime.fromtimestamp(self._clock(), tz=dt.timezone.utc)
        return value.isoformat(timespec="milliseconds").replace("+00:00", "Z")

    def _signed_headers(self, method: str, request_path: str, body: bytes | None) -> dict[str, str]:
        timestamp = self._timestamp()
        body_text = "" if body is None else body.decode("utf-8")
        prehash = f"{timestamp}{method.upper()}{request_path}{body_text}".encode("utf-8")
        digest = hmac.new(self._api_secret.encode("utf-8"), prehash, hashlib.sha256).digest()
        signature = base64.b64encode(digest).decode("ascii")
        return {
            "OK-ACCESS-KEY": self._api_key,
            "OK-ACCESS-SIGN": signature,
            "OK-ACCESS-TIMESTAMP": timestamp,
            "OK-ACCESS-PASSPHRASE": self._passphrase,
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "trading-balance-private-api/1.0",
        }

    def _network_transport(
        self, method: str, request_path: str, headers: dict[str, str], body: bytes | None
    ) -> dict[str, Any]:
        connection = http.client.HTTPSConnection(self.BASE_HOST, timeout=10)
        try:
            connection.request(method, request_path, body=body, headers=headers)
            response = connection.getresponse()
            response_body = response.read(self.MAX_RESPONSE_BYTES + 1)
            if len(response_body) > self.MAX_RESPONSE_BYTES:
                raise OKXTransportError(
                    "exchange returned an unusable HTTP response",
                    diagnostic_category="response_oversized",
                    http_status=response.status,
                )
            if response.status < 200 or response.status >= 300:
                raise OKXTransportError(
                    "exchange returned an unusable HTTP response",
                    diagnostic_category="http_rejected",
                    http_status=response.status,
                )
            try:
                decoded = json.loads(response_body.decode("utf-8"))
            except (UnicodeError, json.JSONDecodeError):
                raise OKXTransportError(
                    "exchange returned malformed JSON",
                    diagnostic_category="malformed_json",
                    http_status=response.status,
                ) from None
            if not isinstance(decoded, dict):
                raise OKXTransportError(
                    "exchange returned an unexpected response",
                    diagnostic_category="nonobject_response",
                    http_status=response.status,
                )
            return decoded
        except OKXTransportError:
            raise
        except (OSError, http.client.HTTPException, TimeoutError):
            raise OKXTransportError("exchange transport failed") from None
        finally:
            connection.close()

    def request(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, str] | None = None,
        body: dict[str, Any] | list[dict[str, Any]] | None = None,
        private: bool | None = None,
        allow_nonzero_codes: frozenset[str] = frozenset(),
    ) -> dict[str, Any]:
        query = ""
        if params:
            query = "?" + urlencode(sorted(params.items()))
        request_path = path + query
        body_bytes = None if body is None else json.dumps(body, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        is_private = not path.startswith("/api/v5/public/") if private is None else private
        headers = self._signed_headers(method, request_path, body_bytes) if is_private else {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "trading-balance-private-api/1.0",
        }
        transport = self._transport or self._network_transport
        endpoint = diagnostics.endpoint_for_path(path)
        context = diagnostics.current_context()
        log_request = endpoint is not None and context is not None
        started = time.monotonic()

        def log_result(
            outcome: str,
            reason: str | None = None,
            *,
            error_code: Any = None,
            http_status: Any = None,
            top_code: Any = None,
            data_count: Any = None,
            ack_shape: str | None = None,
        ) -> None:
            if not log_request or endpoint is None:
                return
            diagnostics.emit_event(
                "okx_request",
                stage=endpoint[1],
                outcome=outcome,
                reason=reason,
                endpoint=endpoint[0],
                method=method.upper() if method.upper() in {"GET", "POST"} else "other",
                top_code=top_code,
                item_code=error_code,
                http_status=http_status,
                data_count=data_count,
                ack_shape=ack_shape,
                elapsed_ms=max(0, int((time.monotonic() - started) * 1000)),
            )

        try:
            response = transport(method.upper(), request_path, headers, body_bytes)
        except OKXError as exc:
            outcome, reason = diagnostics.okx_category_reason(
                exc.diagnostic_category or ("exchange_rejected" if exc.error_code else "transport_failure")
            )
            log_result(
                outcome, reason, error_code=exc.error_code, http_status=exc.http_status,
                ack_shape=exc.ack_shape,
            )
            raise
        except Exception:
            # A thrown transport error after a write may mean the exchange
            # completed it. Never surface the exception text or retry here.
            error = OKXTransportError(
                "exchange transport failed", diagnostic_category="transport_failure"
            )
            outcome, reason = diagnostics.okx_category_reason(error.diagnostic_category)
            log_result(outcome, reason)
            raise error from None
        if not isinstance(response, dict):
            error = OKXTransportError(
                "exchange returned an unexpected response",
                diagnostic_category="nonobject_response",
            )
            outcome, reason = diagnostics.okx_category_reason(error.diagnostic_category)
            log_result(outcome, reason)
            raise error
        code = str(response.get("code", ""))
        if code != "0" and code not in allow_nonzero_codes:
            error = OKXError(
                "exchange rejected the request", error_code=code,
                diagnostic_category="exchange_rejected",
                ack_shape="valid" if bounded_error_code(code) is not None else "invalid_code",
            )
            outcome, reason = diagnostics.okx_category_reason(error.diagnostic_category)
            log_result(
                outcome, reason, error_code=error.error_code, top_code=error.error_code,
                ack_shape=error.ack_shape,
            )
            raise error
        data = response.get("data")
        if data is not None and not isinstance(data, list):
            error = OKXTransportError(
                "exchange returned an unexpected response",
                diagnostic_category="malformed_data",
                ack_shape="invalid_data_type",
            )
            outcome, reason = diagnostics.okx_category_reason(error.diagnostic_category)
            log_result(
                outcome, reason, top_code=bounded_error_code(code), ack_shape=error.ack_shape
            )
            raise error
        log_result(
            "success", top_code=bounded_error_code(code),
            data_count=len(data) if isinstance(data, list) else 0,
            ack_shape="valid",
        )
        return response

    def account_config(self) -> dict[str, Any]:
        response = self.request("GET", "/api/v5/account/config")
        data = response.get("data", [])
        if not data or not isinstance(data[0], dict):
            raise OKXTransportError("exchange account configuration is unavailable")
        return data[0]

    def positions(self, instrument_type: str) -> list[dict[str, Any]]:
        response = self.request(
            "GET", "/api/v5/account/positions", params={"instType": instrument_type}
        )
        return [item for item in response.get("data", []) if isinstance(item, dict)]

    def instruments(self, instrument_type: str) -> list[dict[str, Any]]:
        response = self.request(
            "GET", "/api/v5/public/instruments", params={"instType": instrument_type}
        )
        return [item for item in response.get("data", []) if isinstance(item, dict)]

    def ticker(self, instrument_id: str) -> dict[str, Any]:
        response = self.request(
            "GET", "/api/v5/market/ticker", params={"instId": instrument_id}, private=False
        )
        data = response.get("data", [])
        if not data or not isinstance(data[0], dict):
            raise OKXTransportError("exchange ticker is unavailable")
        return data[0]

    def market_candles(
        self,
        instrument_id: str,
        bar: str,
        *,
        after: str | None = None,
        limit: int = 300,
    ) -> list[Any]:
        """Read one UTC-aligned public candle page for Strategy generation."""
        if bar not in {"6Hutc", "1Dutc", "1Wutc"}:
            raise ValueError("unsupported public candle interval")
        if isinstance(limit, bool) or not isinstance(limit, int) or not 1 <= limit <= 300:
            raise ValueError("public candle page limit is invalid")
        if after is not None and (not isinstance(after, str) or not after.isdigit()):
            raise ValueError("public candle cursor is invalid")
        params = {"instId": instrument_id, "bar": bar, "limit": str(limit)}
        if after is not None:
            params["after"] = after
        response = self.request(
            "GET", "/api/v5/market/candles", params=params, private=False
        )
        data = response.get("data", [])
        if not isinstance(data, list):
            raise OKXTransportError("exchange candle data is unavailable")
        return data

    def pending_orders(self, instrument_id: str) -> list[dict[str, Any]]:
        response = self.request(
            "GET", "/api/v5/trade/orders-pending", params={"instType": "SWAP", "instId": instrument_id}
        )
        return [item for item in response.get("data", []) if isinstance(item, dict)]

    def account_balance(self) -> list[dict[str, Any]]:
        response = self.request("GET", "/api/v5/account/balance", params={"ccy": "USDT"})
        data = response.get("data", [])
        if not isinstance(data, list) or any(not isinstance(item, dict) for item in data):
            raise OKXTransportError("exchange balance data is unavailable")
        return data

    def trade_fee(self, instrument_family: str) -> dict[str, Any]:
        response = self.request(
            "GET", "/api/v5/account/trade-fee",
            params={"instType": "SWAP", "instFamily": instrument_family},
        )
        data = response.get("data", [])
        if not isinstance(data, list) or len(data) != 1 or not isinstance(data[0], dict):
            raise OKXTransportError("exchange fee metadata is unavailable")
        return data[0]

    def position_tiers(self, instrument_family: str) -> list[dict[str, Any]]:
        response = self.request(
            "GET", "/api/v5/public/position-tiers",
            params={"instType": "SWAP", "tdMode": "isolated", "instFamily": instrument_family},
            private=False,
        )
        return [item for item in response.get("data", []) if isinstance(item, dict)]

    def order_details(self, instrument_id: str, client_order_id: str) -> dict[str, Any] | None:
        response = self.request(
            "GET",
            "/api/v5/trade/order",
            params={"instId": instrument_id, "clOrdId": client_order_id},
        )
        data = response.get("data", [])
        if not data or not isinstance(data[0], dict):
            return None
        return data[0]

    def add_margin(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self.request("POST", "/api/v5/account/position/margin-balance", body=payload)

    def order_details_by_id(self, instrument_id: str, order_id: str) -> dict[str, Any] | None:
        response = self.request(
            "GET", "/api/v5/trade/order", params={"instId": instrument_id, "ordId": order_id}
        )
        data = response.get("data")
        if not isinstance(data, list) or len(data) != 1 or not isinstance(data[0], dict):
            return None
        return data[0]

    def cancel_order(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self.request("POST", "/api/v5/trade/cancel-order", body=payload)

    def place_order(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self.request("POST", "/api/v5/trade/order", body=payload)

    def set_leverage(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self.request("POST", "/api/v5/account/set-leverage", body=payload)

    def place_batch_orders(self, payload: list[dict[str, Any]]) -> dict[str, Any]:
        # Batch placement reports per-order outcomes even when the top-level
        # response marks the batch partial. Preserve those rows for the strategy
        # result parser instead of converting them into a blanket rejection.
        return self.request(
            "POST", "/api/v5/trade/batch-orders", body=payload,
            allow_nonzero_codes=frozenset({"1", "2"}),
        )

    def close_position(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self.request("POST", "/api/v5/trade/close-position", body=payload)
