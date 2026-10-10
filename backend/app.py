"""WSGI entry point for ``backend.app:application``."""

from __future__ import annotations

import json
import os
import threading
from typing import Any, Callable

from .currency import CurrencyTransport
from .service import APIError, BODY_LIMIT_BYTES, RuntimeSettings, TradeService
from .okx import Transport
from . import diagnostics


class WSGIApplication:
    def __init__(
        self,
        *,
        settings: RuntimeSettings | None = None,
        transport: Transport | None = None,
        currency_transport: CurrencyTransport | None = None,
        clock: Callable[[], float] | None = None,
        service: TradeService | None = None,
    ):
        self._settings = settings
        self._transport = transport
        self._currency_transport = currency_transport
        self._clock = clock
        self._service = service
        self._service_lock = threading.Lock()

    def _get_service(self) -> TradeService:
        if self._service is not None:
            return self._service
        with self._service_lock:
            if self._service is not None:
                return self._service
            try:
                settings = self._settings or RuntimeSettings.from_environ()
                kwargs: dict[str, Any] = {
                    "transport": self._transport,
                    "currency_transport": self._currency_transport,
                }
                if self._clock is not None:
                    kwargs["clock"] = self._clock
                self._service = TradeService(settings, **kwargs)
                return self._service
            except Exception:
                raise APIError(503, "service_not_configured", "The private API is not ready.") from None

    @staticmethod
    def _response(
        start_response: Callable[..., Any],
        status: int,
        payload: dict[str, Any] | None,
        headers: list[tuple[str, str]] | None = None,
    ) -> list[bytes]:
        body = b"" if payload is None else json.dumps(
            payload, separators=(",", ":"), ensure_ascii=False
        ).encode("utf-8")
        status_text = {
            200: "OK", 204: "No Content", 400: "Bad Request", 401: "Unauthorized",
            403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 409: "Conflict", 410: "Gone",
            413: "Payload Too Large", 415: "Unsupported Media Type", 422: "Unprocessable Entity",
            429: "Too Many Requests", 500: "Internal Server Error", 502: "Bad Gateway",
            503: "Service Unavailable",
        }.get(status, "Error")
        response_headers = [
            ("Content-Type", "application/json; charset=utf-8"),
            ("Content-Length", str(len(body))),
            ("Cache-Control", "no-store"),
            ("X-Content-Type-Options", "nosniff"),
            ("Referrer-Policy", "no-referrer"),
        ]
        if headers:
            response_headers.extend(headers)
        start_response(f"{status} {status_text}", response_headers)
        return [body]

    def __call__(self, environ: dict[str, Any], start_response: Callable[..., Any]) -> list[bytes]:
        method = environ.get("REQUEST_METHOD", "GET")
        request_method = str(method).upper()
        diagnostic_method = request_method if request_method in ("GET", "POST") else "other"
        path = environ.get("PATH_INFO", "/")
        classified = diagnostics.classified_strategy_route(request_method, path)
        if classified is None:
            return self._handle_request(environ, start_response)
        strategy_id, stage = classified
        with diagnostics.strategy_context(strategy_id, component="api"):
            diagnostics.emit_event(
                "request_start", stage=stage, outcome="started", method=diagnostic_method
            )
            observed_status: list[int] = []

            def record_start(status: str, headers: list[tuple[str, str]], exc_info: Any = None) -> Any:
                try:
                    observed_status.append(int(status.split(" ", 1)[0]))
                except (ValueError, AttributeError):
                    pass
                if exc_info is None:
                    return start_response(status, headers)
                return start_response(status, headers, exc_info)

            try:
                response = self._handle_request(environ, record_start)
            except Exception:
                diagnostics.emit_event(
                    "request_failure", stage="request", outcome="failure",
                    reason="internal_error", api_code="internal_error", method=diagnostic_method,
                )
                raise
            if observed_status and observed_status[-1] < 400:
                diagnostics.emit_event(
                    "request_end", stage=stage, outcome="success", method=diagnostic_method
                )
            return response

    def _handle_request(
        self, environ: dict[str, Any], start_response: Callable[..., Any]
    ) -> list[bytes]:
        method = str(environ.get("REQUEST_METHOD", "GET")).upper()
        diagnostic_method = method if method in ("GET", "POST") else "other"
        path = str(environ.get("PATH_INFO", "/"))
        origin = str(environ.get("HTTP_ORIGIN", ""))
        cors_headers: list[tuple[str, str]] = []

        # Health remains a static response and does not require credentials,
        # database access, or a live OKX request.
        if path == "/v1/health" and method == "GET":
            allowed = os.environ.get("ALLOWED_WEB_ORIGIN", "")
            if self._settings is not None:
                allowed = self._settings.allowed_web_origin
            if self._service is not None:
                allowed = self._service.settings.allowed_web_origin
            if origin and origin != allowed:
                return self._response(start_response, 403, {"error": "origin_denied", "message": "This origin is not allowed."})
            if origin and allowed:
                cors_headers = self._cors_headers(origin)
            return self._response(start_response, 200, {"status": "ok"}, cors_headers)

        try:
            service = self._get_service()
            if origin and origin != service.settings.allowed_web_origin:
                raise APIError(403, "origin_denied", "This origin is not allowed.")
            if origin:
                cors_headers = self._cors_headers(origin)
            if method == "OPTIONS":
                return self._response(start_response, 204, None, cors_headers)

            body = self._read_json_body(environ)
            status, payload, extra_headers = service.dispatch(method, path, body, environ)
            return self._response(start_response, status, payload, [*cors_headers, *extra_headers])
        except APIError as error:
            if diagnostics.current_context() is not None:
                reason = {
                    "origin_denied": "origin_denied",
                    "unauthorized": "authentication_failed",
                    "authentication_required": "authentication_failed",
                    "invalid_request": "invalid_request",
                    "invalid_json": "body_invalid",
                    "json_required": "body_invalid",
                    "service_not_configured": "service_unavailable",
                    "internal_error": "internal_error",
                    "strategy_stale": "strategy_stale",
                    "account_changed": "account_changed",
                    "account_mode_unsupported": "account_mode_unsupported",
                    "exchange_rate_limited": "exchange_rate_limited",
                    "account_preflight_unavailable": "preflight_unavailable",
                    "instrument_position_exists": "position_exists",
                    "pending_order_exists": "pending_order_exists",
                    "insufficient_balance": "insufficient_balance",
                    "invalid_confirmation": "confirmation_invalid",
                    "strategy_immutable": "strategy_immutable",
                    "strategy_state_changed": "strategy_state_changed",
                    "prepared_strategy_invalid": "prepared_invalid",
                    "retry_source_unavailable": "retry_source_unavailable",
                    "retry_selection_invalid": "retry_selection_invalid",
                    "retry_source_stale": "retry_source_stale",
                    "retry_selection_in_use": "retry_selection_in_use",
                    "retry_request_conflict": "retry_request_conflict",
                    "retry_preview_stale": "retry_preview_stale",
                }.get(error.code, "other")
                diagnostics.emit_event(
                    "request_failure", stage="request", outcome="failure", reason=reason,
                    api_code=error.code, method=diagnostic_method,
                )
            return self._response(start_response, error.status, error.response(), [*cors_headers, *error.headers])
        except Exception:
            # Never serialize exception text: it can contain request or
            # transport details that do not belong in the API response.
            if diagnostics.current_context() is not None:
                diagnostics.emit_event(
                    "request_failure", stage="request", outcome="failure",
                    reason="internal_error", api_code="internal_error", method=diagnostic_method,
                )
            return self._response(
                start_response,
                500,
                {"error": "internal_error", "message": "The request could not be completed."},
                cors_headers,
            )

    @staticmethod
    def _read_json_body(environ: dict[str, Any]) -> dict[str, Any]:
        method = str(environ.get("REQUEST_METHOD", "GET")).upper()
        if method in ("GET", "HEAD", "OPTIONS"):
            return {}
        content_type = str(environ.get("CONTENT_TYPE", "")).split(";", 1)[0].strip().lower()
        if content_type != "application/json":
            raise APIError(415, "json_required", "Send a JSON request body.")
        length_text = str(environ.get("CONTENT_LENGTH", "0") or "0")
        try:
            length = int(length_text)
        except ValueError:
            raise APIError(400, "invalid_content_length", "The request body is malformed.") from None
        if length < 0 or length > BODY_LIMIT_BYTES:
            raise APIError(413, "body_too_large", "The request body exceeds the size limit.")
        stream = environ.get("wsgi.input")
        raw = b"" if stream is None or length == 0 else stream.read(length)
        if len(raw) != length:
            raise APIError(400, "invalid_json", "The request body is incomplete.")
        try:
            parsed = json.loads(raw.decode("utf-8")) if raw else {}
        except (UnicodeError, json.JSONDecodeError):
            raise APIError(400, "invalid_json", "The request body is not valid JSON.") from None
        if not isinstance(parsed, dict):
            raise APIError(400, "invalid_json", "The request body must be a JSON object.")
        return parsed

    @staticmethod
    def _cors_headers(origin: str) -> list[tuple[str, str]]:
        return [
            ("Access-Control-Allow-Origin", origin),
            ("Access-Control-Allow-Credentials", "true"),
            ("Access-Control-Allow-Methods", "GET, POST, OPTIONS"),
            ("Access-Control-Allow-Headers", "Authorization, Content-Type, X-CSRF-Token, X-Session-Transport"),
            ("Access-Control-Max-Age", "600"),
            ("Vary", "Origin"),
        ]


def create_application(
    *,
    settings: RuntimeSettings | None = None,
    transport: Transport | None = None,
    currency_transport: CurrencyTransport | None = None,
    clock: Callable[[], float] | None = None,
    service: TradeService | None = None,
) -> WSGIApplication:
    """Create an app with optional fake transport and temporary test settings."""
    return WSGIApplication(
        settings=settings,
        transport=transport,
        currency_transport=currency_transport,
        clock=clock,
        service=service,
    )


application = create_application()
