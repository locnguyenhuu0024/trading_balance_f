from __future__ import annotations

import copy
import json
import sqlite3
from contextlib import closing
from concurrent.futures import ThreadPoolExecutor
from tempfile import TemporaryDirectory
from threading import Barrier
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit
import unittest

from backend.security import token_digest
from backend.service import APIError, RuntimeSettings, TradeService
from backend.tests.test_trade_api import FakeOKX


ORIGIN = "https://tradingbalancef.vercel.app"
PASSWORD = "disposable-test-password-2026"
TOTP_SECRET = "JBSWY3DPEHPK3PXP"
SIGNING_KEY = b"T" * 32
BASE_TIME = 1_800_000_000.0
SESSION_TOKEN = "fixture-cancellation-session"


class CancellationExchange(FakeOKX):
    """A local-only fake for authoritative order reads and cancel writes."""

    def __init__(self, order: dict | None = None):
        super().__init__()
        self.order = order or {
            "instType": "SPOT",
            "instId": "BTC-USDT",
            "ordId": "spot-order-1",
            "ordType": "limit",
            "side": "buy",
            "px": "60000.00",
            "sz": "2.0",
            "accFillSz": "0",
            "state": "live",
        }
        self.cancel_state = "canceled"
        self.cancel_fill: str | None = None
        self.cancel_timeout_after_effect = False
        self.cancel_ack_override: dict | None = None
        self.cancel_bodies: list[dict] = []
        self.order_reads = 0
        self.account_config_unavailable = False
        self.malformed_order_read_after_write = False
        self.order_missing_after_write = False
        self.operation_db_path: str | None = None
        self.journal_state_at_cancel: list[tuple[str, str]] = []

    def transport(self, method: str, path: str, headers: dict[str, str], body: bytes | None) -> dict:
        parsed = urlsplit(path)
        params = {key: values[-1] for key, values in parse_qs(parsed.query).items()}
        payload = None if body is None else json.loads(body.decode("utf-8"))

        if method == "GET" and parsed.path == "/api/v5/account/config" and self.account_config_unavailable:
            self.calls.append((method, path, payload))
            self.account_config_read_count += 1
            raise TimeoutError("simulated account identity read failure")

        if method == "GET" and parsed.path == "/api/v5/trade/order" and "ordId" in params:
            self.calls.append((method, path, payload))
            self.order_reads += 1
            if self.malformed_order_read_after_write and self.write_count > 0:
                return {"code": "0", "data": None}
            if self.order_missing_after_write and self.write_count > 0:
                return {"code": "0", "data": []}
            if params.get("instId") == self.order.get("instId") and params.get("ordId") == self.order.get("ordId"):
                return {"code": "0", "data": [copy.deepcopy(self.order)]}
            return {"code": "0", "data": []}

        if method == "POST" and parsed.path == "/api/v5/trade/cancel-order":
            self.calls.append((method, path, payload))
            self.cancel_bodies.append(copy.deepcopy(payload))
            if self.operation_db_path is not None:
                with closing(sqlite3.connect(self.operation_db_path)) as connection, connection:
                    row = connection.execute(
                        "SELECT status, results_json FROM operations WHERE action='cancel_order' "
                        "ORDER BY created_at DESC LIMIT 1"
                    ).fetchone()
                if row is not None:
                    targets = json.loads(row[1])
                    self.journal_state_at_cancel.append((row[0], targets[0]["status"]))
            self.write_count += 1
            if self.cancel_ack_override is not None:
                return copy.deepcopy(self.cancel_ack_override)
            self.order["state"] = self.cancel_state
            if self.cancel_fill is not None:
                self.order["accFillSz"] = self.cancel_fill
            if self.cancel_timeout_after_effect:
                raise TimeoutError("simulated cancellation timeout after exchange effect")
            return {"code": "0", "data": [{"sCode": "0", "ordId": payload["ordId"]}]}

        return super().transport(method, path, headers, body)


class OrderCancellationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TemporaryDirectory()
        self.now = BASE_TIME
        self.exchange = CancellationExchange()
        self.settings = RuntimeSettings(
            okx_api_key="test-key",
            okx_api_secret="test-secret",
            okx_api_passphrase="test-passphrase",
            admin_password_hash="unused-fixture-password-hash",
            totp_secret=TOTP_SECRET,
            session_signing_key=SIGNING_KEY,
            allowed_web_origin=ORIGIN,
            operation_db_path=f"{self.temp.name}/operations.sqlite3",
        )
        self.exchange.operation_db_path = self.settings.operation_db_path
        self._new_service()
        with self.service.store.transaction() as connection:
            connection.execute(
                "INSERT INTO sessions(token_hash, expires_at, created_at) VALUES (?, ?, ?)",
                (token_digest(SESSION_TOKEN, SIGNING_KEY), self.now + 3600, self.now),
            )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _new_service(self) -> None:
        self.service = TradeService(
            self.settings, transport=self.exchange.transport, clock=lambda: self.now
        )

    def restart_server(self) -> None:
        self._new_service()

    def request(
        self,
        method: str,
        path: str,
        body: dict | None = None,
        *,
        token: str | None = None,
    ) -> tuple[int, dict]:
        environ = {"REMOTE_ADDR": "127.0.0.1"}
        if token:
            environ["HTTP_AUTHORIZATION"] = f"Bearer {token}"
        try:
            status, result, _ = self.service.dispatch(method, path, body or {}, environ)
            return status, result
        except APIError as error:
            return error.status, error.response()

    @staticmethod
    def login() -> str:
        """Return the valid temporary session seeded directly for these API tests."""
        return SESSION_TOKEN

    def identity(self, **overrides: str) -> dict[str, str]:
        result = {
            key: str(self.exchange.order[key])
            for key in ("instType", "instId", "ordId", "ordType", "side", "px", "sz")
        }
        result.update(overrides)
        return result

    def prepare(self, token: str, identity: dict | None = None) -> dict:
        status, result = self.request(
            "POST", "/v1/actions/prepare",
            {"action": "cancel_order", "targetIdentity": self.identity() if identity is None else identity},
            token=token,
        )
        self.assertEqual(status, 200, result)
        return result

    def execute(self, token: str, prepared: dict) -> dict:
        status, result = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )
        self.assertEqual(status, 200, result)
        return result

    def _assert_top_level_ack_case(
        self,
        response: dict,
        *,
        expected_status: str,
        expected_code: str | None = None,
        hidden_texts: tuple[str, ...] = (),
    ) -> None:
        token = self.login()
        prepared = self.prepare(token)
        self.exchange.cancel_ack_override = response

        result = self.execute(token, prepared)
        self.assertEqual(result["status"], expected_status)
        for hidden_text in hidden_texts:
            self.assertNotIn(hidden_text, json.dumps(result))

        if expected_status == "UNKNOWN":
            self.assertEqual(
                result["targets"][0]["outcome"]["reason"],
                "exchange_acknowledgement_unconfirmed",
            )
            self.assertEqual(self.exchange.write_count, 1)
            reads_before_reconciliation = self.exchange.order_reads
            status, reconciled = self.request(
                "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
            )
            self.assertEqual(status, 200)
            self.assertEqual(reconciled["status"], "UNKNOWN")
            self.assertEqual(self.exchange.order["state"], "live")
            self.assertEqual(self.exchange.order_reads, reads_before_reconciliation + 1)
            self.assertEqual(self.exchange.write_count, 1)
        else:
            self.assertEqual(result["targets"][0]["outcome"]["exchangeCode"], expected_code)
            self.assertEqual(self.exchange.write_count, 1)

    def test_red_missing_authentication_never_looks_up_or_writes(self) -> None:
        status, result = self.request(
            "POST", "/v1/actions/prepare",
            {"action": "cancel_order", "targetIdentity": self.identity()},
        )
        self.assertEqual(status, 401)
        self.assertEqual(result["error"], "authentication_required")
        self.assertEqual(self.exchange.order_reads, 0)
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_missing_identity_is_rejected_without_exchange_access(self) -> None:
        token = self.login()
        status, result = self.request(
            "POST", "/v1/actions/prepare", {"action": "cancel_order"}, token=token
        )
        self.assertEqual(status, 400)
        self.assertEqual(result["error"], "invalid_order_identity")
        self.assertEqual(self.exchange.order_reads, 0)
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_wrong_confirmation_never_writes(self) -> None:
        token = self.login()
        prepared = self.prepare(token)
        status, result = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": "wrong-confirmation"},
            token=token,
        )
        self.assertEqual(status, 403)
        self.assertEqual(result["error"], "invalid_confirmation")
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_expired_confirmation_never_writes(self) -> None:
        token = self.login()
        prepared = self.prepare(token)
        self.now += 121
        result = self.execute(token, prepared)
        self.assertEqual(result["status"], "EXPIRED")
        self.assertEqual(result["targets"][0]["status"], "EXPIRED")
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_nonlimit_identity_is_rejected_without_exchange_write(self) -> None:
        token = self.login()
        status, result = self.request(
            "POST", "/v1/actions/prepare",
            {"action": "cancel_order", "targetIdentity": self.identity(ordType="market")},
            token=token,
        )
        self.assertEqual(status, 400)
        self.assertEqual(result["error"], "invalid_order_identity")
        self.assertEqual(self.exchange.order_reads, 0)
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_terminal_order_cannot_be_prepared(self) -> None:
        self.exchange.order["state"] = "canceled"
        token = self.login()
        status, result = self.request(
            "POST", "/v1/actions/prepare",
            {"action": "cancel_order", "targetIdentity": self.identity()}, token=token,
        )
        self.assertEqual(status, 409)
        self.assertEqual(result["error"], "stale_target")
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_selected_order_mismatch_cannot_be_prepared(self) -> None:
        token = self.login()
        status, result = self.request(
            "POST", "/v1/actions/prepare",
            {"action": "cancel_order", "targetIdentity": self.identity(px="60001")}, token=token,
        )
        self.assertEqual(status, 409)
        self.assertEqual(result["error"], "stale_target")
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_account_change_during_lookup_rejects_prepare(self) -> None:
        token = self.login()
        self.exchange.switch_account_on_config_read = self.exchange.account_config_read_count + 3
        status, result = self.request(
            "POST", "/v1/actions/prepare",
            {"action": "cancel_order", "targetIdentity": self.identity()}, token=token,
        )
        self.assertEqual(status, 409)
        self.assertEqual(result["error"], "stale_target")
        self.assertEqual(self.exchange.order_reads, 1)
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_account_identity_read_failure_is_a_safe_prepare_error(self) -> None:
        token = self.login()
        self.exchange.account_config_unavailable = True
        status, result = self.request(
            "POST", "/v1/actions/prepare",
            {"action": "cancel_order", "targetIdentity": self.identity()}, token=token,
        )
        self.assertEqual(status, 502)
        self.assertEqual(result["error"], "account_identity_unavailable")
        self.assertEqual(self.exchange.order_reads, 0)
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_account_change_before_attempt_conflicts_without_write(self) -> None:
        token = self.login()
        prepared = self.prepare(token)
        self.exchange.switch_account_on_config_read = self.exchange.account_config_read_count + 1
        result = self.execute(token, prepared)
        self.assertEqual(result["status"], "CONFLICT")
        self.assertEqual(result["targets"][0]["status"], "CONFLICT")
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_fill_change_before_attempt_conflicts_without_write(self) -> None:
        self.exchange.order["state"] = "partially_filled"
        self.exchange.order["accFillSz"] = "0.25"
        token = self.login()
        prepared = self.prepare(token)
        self.exchange.order["accFillSz"] = "0.5"
        result = self.execute(token, prepared)
        self.assertEqual(result["status"], "CONFLICT")
        self.assertEqual(result["targets"][0]["outcome"]["reason"], "order_changed_before_cancellation")
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_terminal_state_change_before_attempt_conflicts_without_write(self) -> None:
        token = self.login()
        prepared = self.prepare(token)
        self.exchange.order["state"] = "filled"
        self.exchange.order["accFillSz"] = self.exchange.order["sz"]
        result = self.execute(token, prepared)
        self.assertEqual(result["status"], "CONFLICT")
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_duplicate_preparation_is_blocked_while_confirmation_is_pending(self) -> None:
        token = self.login()
        first = self.prepare(token)
        status, result = self.request(
            "POST", "/v1/actions/prepare",
            {"action": "cancel_order", "targetIdentity": self.identity()}, token=token,
        )
        self.assertEqual(status, 409)
        self.assertEqual(result["error"], "operation_pending")
        self.assertTrue(first["confirmationToken"])
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_concurrent_same_order_preparation_serializes_conflict_and_insert(self) -> None:
        token = self.login()
        start = Barrier(3, timeout=10)
        request_body = {"action": "cancel_order", "targetIdentity": self.identity()}

        def prepare_concurrently() -> tuple[int, dict]:
            start.wait()
            return self.request("POST", "/v1/actions/prepare", request_body, token=token)

        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [executor.submit(prepare_concurrently) for _ in range(2)]
            start.wait()
            results = [future.result(timeout=15) for future in futures]

        self.assertCountEqual([status for status, _ in results], [200, 409])
        prepared = next(result for status, result in results if status == 200)
        pending = next(result for status, result in results if status == 409)
        self.assertTrue(prepared["confirmationToken"])
        self.assertEqual(pending["error"], "operation_pending")
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_conflict_key_ignores_mutable_price_and_size_for_same_order(self) -> None:
        token = self.login()
        self.prepare(token)
        self.exchange.order["px"] = "60001"
        self.exchange.order["sz"] = "2.1"
        status, result = self.request(
            "POST", "/v1/actions/prepare",
            {
                "action": "cancel_order",
                "targetIdentity": self.identity(px="60001", sz="2.1"),
            },
            token=token,
        )
        self.assertEqual(status, 409)
        self.assertEqual(result["error"], "operation_pending")
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_overlapping_preparation_cannot_retry_unknown_cancellation(self) -> None:
        token = self.login()
        first = self.prepare(token)
        self.exchange.cancel_ack_override = {"code": "0", "data": []}

        first_result = self.execute(token, first)
        self.assertEqual(first_result["status"], "UNKNOWN")
        self.assertEqual(self.exchange.write_count, 1)

        # Model an overlapping prepare that passed its initial pending check before the first result became UNKNOWN.
        with patch.object(self.service, "_pending_target_conflict", return_value=False):
            second = self.prepare(token)
        second_result = self.execute(token, second)
        self.assertEqual(second_result["status"], "CONFLICT")
        self.assertEqual(second_result["targets"][0]["outcome"]["reason"], "order_action_pending")
        self.assertEqual(self.exchange.write_count, 1)

    def test_red_known_exchange_rejection_is_failed_with_code_only(self) -> None:
        token = self.login()
        prepared = self.prepare(token)
        self.exchange.cancel_ack_override = {
            "code": "0", "data": [{"sCode": "51000", "sMsg": "fixture rejection details"}]
        }
        result = self.execute(token, prepared)
        self.assertEqual(result["status"], "FAILED")
        self.assertEqual(result["targets"][0]["outcome"]["exchangeCode"], "51000")
        self.assertNotIn("fixture rejection details", json.dumps(result))
        self.assertEqual(self.exchange.write_count, 1)

    def test_red_malformed_rejection_code_is_unknown_without_echoing_exchange_text(self) -> None:
        token = self.login()
        prepared = self.prepare(token)
        self.exchange.cancel_ack_override = {
            "code": "0", "data": [{"sCode": "unsafe-code", "sMsg": "unsafe exchange text"}]
        }
        result = self.execute(token, prepared)
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertNotIn("unsafe-code", json.dumps(result))
        self.assertNotIn("unsafe exchange text", json.dumps(result))
        self.assertEqual(self.exchange.write_count, 1)

    def test_red_top_level_missing_response_code_stays_unknown_on_read_only_reconciliation(self) -> None:
        self._assert_top_level_ack_case(
            {"data": [], "msg": "unsafe exchange detail"},
            expected_status="UNKNOWN",
            hidden_texts=("unsafe exchange detail",),
        )

    def test_red_top_level_text_response_code_stays_unknown_on_read_only_reconciliation(self) -> None:
        self._assert_top_level_ack_case(
            {"code": "unsafe-top-level-code", "data": [], "msg": "unsafe exchange detail"},
            expected_status="UNKNOWN",
            hidden_texts=("unsafe-top-level-code", "unsafe exchange detail"),
        )

    def test_red_top_level_bool_response_code_stays_unknown_on_read_only_reconciliation(self) -> None:
        self._assert_top_level_ack_case(
            {"code": True, "data": [], "msg": "unsafe exchange detail"},
            expected_status="UNKNOWN",
            hidden_texts=("unsafe exchange detail",),
        )

    def test_red_top_level_numeric_response_code_is_failed_with_bounded_code(self) -> None:
        self._assert_top_level_ack_case(
            {"code": "51002", "data": [], "msg": "unsafe exchange detail"},
            expected_status="FAILED",
            expected_code="51002",
            hidden_texts=("unsafe exchange detail",),
        )

    def test_red_ack_without_authoritative_cancellation_is_unknown(self) -> None:
        token = self.login()
        prepared = self.prepare(token)
        self.exchange.cancel_state = "live"
        result = self.execute(token, prepared)
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertEqual(result["targets"][0]["outcome"]["orderState"], "live")
        self.assertEqual(self.exchange.write_count, 1)

    def test_red_order_filled_during_cancel_is_failed_with_fill_retained(self) -> None:
        token = self.login()
        prepared = self.prepare(token)
        self.exchange.cancel_state = "filled"
        self.exchange.cancel_fill = "2.0"
        result = self.execute(token, prepared)
        self.assertEqual(result["status"], "FAILED")
        self.assertEqual(result["targets"][0]["outcome"]["filledSize"], "2")
        self.assertEqual(self.exchange.write_count, 1)

    def test_red_malformed_authoritative_order_after_ack_is_unknown(self) -> None:
        token = self.login()
        prepared = self.prepare(token)
        self.exchange.malformed_order_read_after_write = True
        result = self.execute(token, prepared)
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertEqual(result["targets"][0]["outcome"]["reason"], "order_status_unavailable")
        self.assertEqual(self.exchange.write_count, 1)

    def test_red_missing_authoritative_order_after_ack_is_unknown(self) -> None:
        token = self.login()
        prepared = self.prepare(token)
        self.exchange.order_missing_after_write = True
        result = self.execute(token, prepared)
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertEqual(result["targets"][0]["outcome"]["reason"], "order_status_unavailable")
        self.assertEqual(self.exchange.write_count, 1)

    def test_red_bad_ack_remains_unknown_and_result_read_never_repeats_write(self) -> None:
        token = self.login()
        prepared = self.prepare(token)
        self.exchange.cancel_ack_override = {
            "code": "0", "data": [{"sCode": "0", "ordId": "different-order"}]
        }
        result = self.execute(token, prepared)
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertEqual(result["targets"][0]["outcome"]["reason"], "cancellation_acknowledgement_mismatch")

        status, reconciled = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )
        self.assertEqual(status, 200)
        self.assertEqual(reconciled["status"], "UNKNOWN")
        self.assertEqual(self.exchange.write_count, 1)
        self.assertEqual(self.exchange.order["state"], "live")

    def test_red_timeout_restart_reconciles_read_only_and_duplicate_execute_does_not_retry(self) -> None:
        token = self.login()
        prepared = self.prepare(token)
        self.exchange.cancel_timeout_after_effect = True
        result = self.execute(token, prepared)
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertEqual(self.exchange.write_count, 1)

        duplicate = self.execute(token, prepared)
        self.assertEqual(duplicate["status"], "UNKNOWN")
        self.assertEqual(self.exchange.write_count, 1)

        self.restart_server()
        status, reconciled = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )
        self.assertEqual(status, 200)
        self.assertEqual(reconciled["status"], "SUCCEEDED")
        self.assertEqual(reconciled["targets"][0]["outcome"]["filledSize"], "0")
        self.assertEqual(self.exchange.write_count, 1)

    def test_red_account_change_after_cancel_ack_keeps_result_unknown_without_retry(self) -> None:
        token = self.login()
        prepared = self.prepare(token)
        self.exchange.switch_account_on_config_read = self.exchange.account_config_read_count + 3
        result = self.execute(token, prepared)
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertEqual(self.exchange.write_count, 1)

    def test_red_recovery_of_durable_attempt_started_is_read_only(self) -> None:
        token = self.login()
        prepared = self.prepare(token)
        with closing(sqlite3.connect(self.settings.operation_db_path)) as connection, connection:
            row = connection.execute(
                "SELECT results_json FROM operations WHERE operation_id=?",
                (prepared["operationId"],),
            ).fetchone()
            targets = json.loads(row[0])
            targets[0]["status"] = "ATTEMPT_STARTED"
            connection.execute(
                "UPDATE operations SET status='IN_PROGRESS', results_json=? WHERE operation_id=?",
                (json.dumps(targets, separators=(",", ":")), prepared["operationId"]),
            )

        status, result = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertEqual(self.exchange.write_count, 0)

    def test_green_confirmed_spot_cancel_uses_exact_body_and_is_idempotent(self) -> None:
        token = self.login()
        prepared = self.prepare(token, self.identity(px="60000", sz="2"))
        self.assertEqual(prepared["summary"]["targets"][0]["remainingSize"], "2")
        result = self.execute(token, prepared)
        self.assertEqual(result["status"], "SUCCEEDED")
        self.assertEqual(result["targets"][0]["outcome"]["orderState"], "canceled")
        self.assertEqual(
            self.exchange.cancel_bodies,
            [{"instId": "BTC-USDT", "ordId": "spot-order-1"}],
        )
        writes = [call for call in self.exchange.calls if call[0] == "POST"]
        self.assertEqual([call[1] for call in writes], ["/api/v5/trade/cancel-order"])
        self.assertEqual(self.exchange.write_count, 1)
        self.assertEqual(self.exchange.journal_state_at_cancel, [("IN_PROGRESS", "ATTEMPT_STARTED")])

        duplicate = self.execute(token, prepared)
        self.assertEqual(duplicate["status"], "SUCCEEDED")
        self.assertEqual(self.exchange.write_count, 1)

    def test_green_confirmed_partially_filled_derivative_cancel_retains_fills(self) -> None:
        self.exchange.order = {
            "instType": "SWAP",
            "instId": "BTC-USDT-SWAP",
            "ordId": "swap-order-9",
            "ordType": "limit",
            "side": "sell",
            "px": "70000.000",
            "sz": "3.000",
            "accFillSz": "0.75",
            "state": "partially_filled",
        }
        self.exchange.cancel_state = "mmp_canceled"
        token = self.login()
        prepared = self.prepare(token, self.identity(px="70000", sz="3"))
        self.assertEqual(prepared["summary"]["targets"][0]["filledSize"], "0.75")
        self.assertEqual(prepared["summary"]["targets"][0]["remainingSize"], "2.25")

        result = self.execute(token, prepared)
        self.assertEqual(result["status"], "SUCCEEDED")
        self.assertEqual(result["targets"][0]["outcome"]["orderState"], "mmp_canceled")
        self.assertEqual(result["targets"][0]["outcome"]["filledSize"], "0.75")
        self.assertEqual(result["targets"][0]["outcome"]["remainingSize"], "2.25")
        self.assertEqual(
            self.exchange.cancel_bodies,
            [{"instId": "BTC-USDT-SWAP", "ordId": "swap-order-9"}],
        )
        writes = [call for call in self.exchange.calls if call[0] == "POST"]
        self.assertEqual([call[1] for call in writes], ["/api/v5/trade/cancel-order"])
        self.assertEqual(self.exchange.write_count, 1)


if __name__ == "__main__":
    unittest.main()
