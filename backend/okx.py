"""Small OKX REST client with injectable transport for offline tests."""

from __future__ import annotations

import base64
import datetime as dt
import hashlib
import hmac
import http.client
import json
import time
from typing import Any, Callable, Optional
from urllib.parse import urlencode


class OKXError(RuntimeError):
    """Safe, content-free error raised for a rejected or malformed response."""


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
            if len(response_body) > self.MAX_RESPONSE_BYTES or response.status < 200 or response.status >= 300:
                raise OKXTransportError("exchange returned an unusable HTTP response")
            try:
                decoded = json.loads(response_body.decode("utf-8"))
            except (UnicodeError, json.JSONDecodeError):
                raise OKXTransportError("exchange returned malformed JSON") from None
            if not isinstance(decoded, dict):
                raise OKXTransportError("exchange returned an unexpected response")
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
        body: dict[str, Any] | None = None,
        private: bool | None = None,
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
        try:
            response = transport(method.upper(), request_path, headers, body_bytes)
        except OKXError:
            raise
        except Exception:
            # A thrown transport error after a write may mean the exchange
            # completed it. Never surface the exception text or retry here.
            raise OKXTransportError("exchange transport failed") from None
        if not isinstance(response, dict):
            raise OKXTransportError("exchange returned an unexpected response")
        if str(response.get("code", "")) != "0":
            raise OKXError("exchange rejected the request")
        data = response.get("data")
        if data is not None and not isinstance(data, list):
            raise OKXTransportError("exchange returned an unexpected response")
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

    def place_order(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self.request("POST", "/api/v5/trade/order", body=payload)

    def close_position(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self.request("POST", "/api/v5/trade/close-position", body=payload)
