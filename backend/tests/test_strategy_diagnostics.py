from __future__ import annotations

import io
import json
import threading
import unittest
from contextlib import nullcontext
from concurrent.futures import ThreadPoolExecutor
from typing import Any
from unittest.mock import patch

from backend import diagnostics
from backend.okx import OKXClient, OKXTransportError
from backend.service import APIError
from backend.strategy import StrategyService
from backend.strategy_worker import StrategyOrderWorker, WorkerSettings
from backend.tests import test_strategy_api as api_fixtures


class _Capture:
    def __init__(self, *, maxsize: int = diagnostics.MAX_QUEUE_LENGTH):
        self.stream = io.StringIO()
        self.sink = diagnostics._Sink(maxsize=maxsize, stream=self.stream)
        self.original = diagnostics._DEFAULT_SINK

    def __enter__(self) -> "_Capture":
        diagnostics._DEFAULT_SINK = self.sink
        return self

    def __exit__(self, *_: Any) -> None:
        self.sink.shutdown()
        diagnostics._DEFAULT_SINK = self.original

    def records(self) -> list[dict[str, Any]]:
        self.sink.drain()
        return [json.loads(line) for line in self.stream.getvalue().splitlines() if line]


class StrategyDiagnosticsTests(unittest.TestCase):
    def _queue_fixture(self) -> tuple[Any, StrategyOrderWorker, list[float]]:
        fixture = api_fixtures.StrategyApiTests(
            "test_red_strategy_routes_require_bearer_before_exchange_reads"
        )
        fixture.setUp()
        self.addCleanup(fixture.tearDown)
        monotonic = [0.0]

        def sleep(seconds: float) -> None:
            monotonic[0] += seconds
            fixture.now += seconds

        settings = WorkerSettings(
            okx_api_key="test-key", okx_api_secret="test-secret", okx_api_passphrase="test-passphrase",
            session_signing_key=api_fixtures.SIGNING_KEY,
            operation_db_path=fixture.settings.operation_db_path,
        )
        worker = StrategyOrderWorker(
            settings, store=fixture.service.store, transport=fixture.exchange.transport,
            clock=lambda: fixture.now, owner_id="diagnostics-worker", lease_seconds=30,
            order_interval_seconds=5, call_spacing_seconds=0, sleep=sleep,
            monotonic=lambda: monotonic[0],
        )
        return fixture, worker, monotonic

    @staticmethod
    def _deterministic_ids(preview: dict[str, Any], _old_orders: Any = None) -> list[dict[str, Any]]:
        return [
            {**row, "clientOrderId": f"diag-order-{index:04d}"}
            for index, row in enumerate(preview["orders"])
        ]

    def _start_queue(self, fixture: Any, count: int = 3) -> tuple[str, dict[str, Any]]:
        status, saved_setting = fixture.request(
            "POST", "/v1/strategies/settings", {"limitOrderSubmissionMode": "sequential"}
        )
        self.assertEqual(status, 200, saved_setting)
        selected = [
            {"side": "long", "price": str(59000 - index * 100),
             "levelId": "queue-entry" if index == 0 else f"queue-level-{index + 1}"}
            for index in range(count)
        ]
        contract = api_fixtures.StrategyApiTests.id_mode_contract(
            selected, entry_ids={"long": "queue-entry"}
        )
        if count > 1:
            contract["totalMargin"] = "600"
        strategy_id, _ = fixture.save_draft(contract)
        status, prepared = fixture.request(
            "POST", f"/v1/strategies/{strategy_id}/prepare-apply", {}
        )
        self.assertEqual(status, 200, prepared)
        status, queued = fixture.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, queued)
        self.assertEqual(queued["queueStatus"], "pending")
        return strategy_id, prepared

    @staticmethod
    def _read_strategy(fixture: Any, strategy_id: str) -> dict[str, Any]:
        with fixture.service.store.connection() as connection:
            row = connection.execute(
                "SELECT * FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone()
        return fixture.service.strategy._decode_row(row)

    @staticmethod
    def _fixed_ack(response: dict[str, Any]) -> dict[str, Any]:
        return {"timestamp": "2026-10-02T00:00:00.000Z", **response}

    def test_red_hostile_route_failure_is_classified_without_raw_identifiers(self) -> None:
        fixture = api_fixtures.StrategyApiTests(
            "test_red_strategy_routes_require_bearer_before_exchange_reads"
        )
        fixture.setUp()
        self.addCleanup(fixture.tearDown)
        raw_strategy_id = "strat-hostile-12345678"
        auth_canary = "AUTH-CANARY-do-not-log"

        with _Capture() as capture:
            raw = b"{}"
            environ: dict[str, Any] = {
                "REQUEST_METHOD": "POST", "PATH_INFO": f"/v1/strategies/{raw_strategy_id}/prepare-apply",
                "REMOTE_ADDR": "127.0.0.1", "HTTP_ORIGIN": api_fixtures.ORIGIN,
                "CONTENT_TYPE": "application/json", "CONTENT_LENGTH": str(len(raw)),
                "wsgi.input": io.BytesIO(raw), "HTTP_AUTHORIZATION": f"Bearer {auth_canary}",
            }
            response: dict[str, Any] = {}

            def start_response(status_text: str, _: list[tuple[str, str]]) -> None:
                response["status"] = int(status_text.split(" ", 1)[0])

            payload_bytes = b"".join(fixture.app(environ, start_response))
            status = response["status"]
            payload = json.loads(payload_bytes.decode("utf-8"))
            records = capture.records()

        self.assertEqual(status, 401, payload)
        failures = [row for row in records if row["event"] == "request_failure"]
        self.assertEqual(len(failures), 1)
        self.assertEqual(failures[0]["stage"], "request")
        self.assertEqual(failures[0]["api_code"], "authentication_required")
        self.assertEqual(failures[0]["strategy_ref"], diagnostics.strategy_ref(raw_strategy_id))
        serialized = "\n".join(json.dumps(row) for row in records)
        self.assertNotIn(raw_strategy_id, serialized)
        self.assertNotIn(auth_canary, serialized)
        self.assertEqual(fixture.exchange.calls, [])

    def test_red_api_preflight_failure_has_fixed_stage_without_exception_text(self) -> None:
        fixture = api_fixtures.StrategyApiTests(
            "test_red_strategy_routes_require_bearer_before_exchange_reads"
        )
        fixture.setUp()
        self.addCleanup(fixture.tearDown)
        contract = api_fixtures.StrategyApiTests.id_mode_contract(
            [{"side": "long", "price": "59000", "levelId": "preflight-entry"}],
            entry_ids={"long": "preflight-entry"},
        )
        strategy_id, _ = fixture.save_draft(contract)
        exception_canary = "private-preflight-exception-canary"

        with _Capture() as capture:
            with patch.object(
                fixture.service.strategy, "_preflight",
                side_effect=APIError(409, "account_changed", exception_canary),
            ):
                status, _ = fixture.request(
                    "POST", f"/v1/strategies/{strategy_id}/prepare-apply", {}
                )
            records = capture.records()

        self.assertEqual(status, 409)
        preflight = next(row for row in records if row["event"] == "preflight")
        self.assertEqual(preflight["component"], "api")
        self.assertEqual(preflight["stage"], "preflight_initial")
        self.assertEqual(preflight["outcome"], "failure")
        self.assertEqual(preflight["reason"], "account_changed")
        self.assertNotIn(exception_canary, json.dumps(records))

    def test_red_hostile_values_and_invalid_schema_are_dropped_or_sanitized(self) -> None:
        raw_strategy_id = "strat-secret-12345678"
        raw_client_id = "order-secret-12345678"
        with _Capture() as capture:
            diagnostics.emit_event(
                "request_failure", component="api", stage="request", outcome="failure",
                reason="internal_error", strategy_id=raw_strategy_id,
                client_order_id=raw_client_id, api_code="credential-canary\n\x1b[31m",
                top_code="response-canary",
            )
            diagnostics.emit_event(
                "request_failure", component="api", stage="request", outcome="failure",
                reason="raw\nmessage", strategy_id=raw_strategy_id,
            )
            diagnostics.emit_event(
                "request_failure", component="api", stage="request", outcome="failure",
                reason="internal_error", order_count=True,
            )
            diagnostics.emit_event(
                "request_failure", component="api", stage="request", outcome="failure",
                reason="internal_error", http_status=600,
            )
            diagnostics.emit_event(
                "request_failure", component="api", stage="request", outcome="failure",
                reason="internal_error", payload={"nested": "credential-canary"},
            )
            records = capture.records()

        request_records = [row for row in records if row["event"] == "request_failure"]
        self.assertEqual(len(request_records), 1)
        row = request_records[0]
        self.assertEqual(row["api_code"], "other")
        self.assertEqual(row["strategy_ref"], diagnostics.strategy_ref(raw_strategy_id))
        self.assertEqual(row["order_ref"], diagnostics.order_ref(raw_client_id))
        serialized = json.dumps(row)
        for canary in (raw_strategy_id, raw_client_id, "credential-canary", "response-canary", "raw\\nmessage"):
            self.assertNotIn(canary, serialized)
        self.assertLessEqual(len(serialized.encode("utf-8")), diagnostics.MAX_RECORD_BYTES)

    def test_red_stalled_full_and_raising_sink_never_blocks_producers(self) -> None:
        entered = threading.Event()
        release = threading.Event()

        class BlockingStream:
            def write(self, _: str) -> None:
                entered.set()
                release.wait(2)

            def flush(self) -> None:
                return

        sink = diagnostics._Sink(maxsize=1, stream=BlockingStream())
        record = diagnostics._new_record(
            "heartbeat", {"component": "worker", "stage": "heartbeat", "outcome": "success"}
        )
        self.assertIsNotNone(record)
        sink.emit_record(record)
        self.assertTrue(entered.wait(1))

        finished = threading.Event()

        def produce() -> None:
            for _ in range(20):
                sink.emit_record(record)
            finished.set()

        producer = threading.Thread(target=produce)
        producer.start()
        self.assertTrue(finished.wait(0.5))
        self.assertGreater(sink._dropped, 0)
        release.set()
        producer.join(1)
        self.assertFalse(producer.is_alive())
        self.assertTrue(sink.shutdown())

        class RaisingStream:
            def write(self, _: str) -> None:
                raise OSError("secret-bearing sink failure")

            def flush(self) -> None:
                return

        failing = diagnostics._Sink(stream=RaisingStream())
        self.assertTrue(failing.emit_record(record))
        self.assertTrue(failing.drain())
        self.assertGreater(failing._dropped, 0)
        self.assertTrue(failing.shutdown())

    def test_green_okx_failure_categories_are_content_free_and_distinct(self) -> None:
        class Response:
            def __init__(self, status: int, body: bytes):
                self.status = status
                self._body = body

            def read(self, _: int) -> bytes:
                return self._body

        class Connection:
            def __init__(self, response: Response):
                self.response = response

            def request(self, *_: Any, **__: Any) -> None:
                return

            def getresponse(self) -> Response:
                return self.response

            def close(self) -> None:
                return

        cases = [
            (Response(503, b'{"code":"50011"}'), "http_rejected", "http_rejected", 503),
            (Response(200, b"not-json"), "malformed_json", "malformed_json", 200),
            (Response(200, b"[]"), "nonobject_response", "nonobject_response", 200),
        ]
        with _Capture() as capture, patch("backend.okx.http.client.HTTPSConnection") as factory:
            for response, _, _, _ in cases:
                factory.return_value = Connection(response)
                client = OKXClient("k", "s", "p")
                with diagnostics.strategy_context("strategy-safe-12345678", component="api"):
                    with self.assertRaises(OKXTransportError):
                        client.request("POST", "/api/v5/trade/order", body={})
            records = capture.records()

        categories = {
            (row.get("outcome"), row.get("reason"), row.get("http_status"))
            for row in records if row["event"] == "okx_request"
        }
        self.assertEqual(categories, {(outcome, reason, status) for _, outcome, reason, status in cases})
        self.assertTrue(all(row["endpoint"] == "place_order" for row in records))

    def test_green_concurrent_contexts_remain_isolated(self) -> None:
        barrier = threading.Barrier(2)
        identifiers = ("strategy-concurrent-0001", "strategy-concurrent-0002")

        def emit(strategy_id: str) -> None:
            with diagnostics.strategy_context(strategy_id, component="api", submission_mode="batch"):
                barrier.wait(timeout=2)
                diagnostics.emit_event(
                    "request_start", stage="request", outcome="started", strategy_id=strategy_id
                )

        with _Capture() as capture:
            with ThreadPoolExecutor(max_workers=2) as pool:
                list(pool.map(emit, identifiers))
            records = capture.records()

        self.assertEqual(
            {row["strategy_ref"] for row in records},
            {diagnostics.strategy_ref(value) for value in identifiers},
        )
        self.assertTrue(all(row["submission_mode"] == "batch" for row in records))
        self.assertTrue(all(row["component"] == "api" for row in records))

    def test_green_heartbeat_is_throttled(self) -> None:
        with patch.object(diagnostics._heartbeat_state, "last", None):
            self.assertTrue(diagnostics.should_emit_heartbeat(100.0))
            self.assertFalse(diagnostics.should_emit_heartbeat(159.999))
            self.assertTrue(diagnostics.should_emit_heartbeat(160.0))

    def test_green_sequential_api_worker_fifo_ack_and_commit_trail(self) -> None:
        fixture, worker, _ = self._queue_fixture()
        with patch.object(StrategyService, "_with_client_ids", staticmethod(self._deterministic_ids)):
            with _Capture() as capture:
                strategy_id, prepared = self._start_queue(fixture, count=3)
                self.assertTrue(worker.run_once())
                records = capture.records()

        strategy = self._read_strategy(fixture, strategy_id)
        self.assertEqual(strategy["status"], "APPLIED")
        self.assertEqual(strategy["queue"]["phase"], "submitted")
        self.assertEqual(fixture.exchange.single_order_attempts, 3)
        actual_order_payloads = [
            payload for method, path, payload in fixture.exchange.calls
            if method == "POST" and path.split("?", 1)[0] == "/api/v5/trade/order"
        ]
        self.assertEqual(
            [row["clOrdId"] for row in actual_order_payloads],
            [row["clientOrderId"] for row in prepared["orders"]],
        )
        order_attempts = [
            row for row in records if row["event"] == "write_attempt" and row.get("stage") == "order"
        ]
        self.assertEqual(
            [row["order_ref"] for row in order_attempts],
            [diagnostics.order_ref(row["clientOrderId"]) for row in prepared["orders"]],
        )
        self.assertTrue(all(row["strategy_ref"] == diagnostics.strategy_ref(strategy_id) for row in order_attempts))
        observed = [
            row for row in records if row["event"] == "ack_observed" and row.get("stage") == "order"
        ]
        self.assertEqual([row["persisted"] for row in observed], [False, False, False])
        commits = [
            row for row in records
            if row["event"] == "commit" and row.get("stage") == "commit"
            and row.get("order_index") is not None
            and row.get("order_ref") in {diagnostics.order_ref(item["clientOrderId"]) for item in prepared["orders"]}
        ]
        self.assertEqual([row["order_index"] for row in commits], [0, 1, 2])
        self.assertEqual([row["persisted"] for row in commits], [True, True, True])
        self.assertEqual([row["status"] for row in commits], ["APPLYING", "APPLYING", "APPLIED"])
        self.assertEqual(
            [row["stage"] for row in records if row["event"] == "preflight" and row["component"] == "worker"],
            ["preflight_initial", "preflight_post_leverage"],
        )
        enqueue = next(row for row in records if row["event"] == "enqueue_result")
        self.assertTrue(enqueue["persisted"])
        self.assertEqual(enqueue["strategy_ref"], diagnostics.strategy_ref(strategy_id))
        serialized = "\n".join(json.dumps(row) for row in records)
        self.assertNotIn(strategy_id, serialized)
        for order in prepared["orders"]:
            self.assertNotIn(order["clientOrderId"], serialized)

    def test_green_eligible_count_read_failure_does_not_stop_worker(self) -> None:
        fixture, worker, _ = self._queue_fixture()
        with patch.object(StrategyService, "_with_client_ids", staticmethod(self._deterministic_ids)):
            with _Capture() as capture:
                strategy_id, _ = self._start_queue(fixture, count=1)
                original_connection = worker.store.connection
                read_count = 0

                def fail_only_count_read(*args: Any, **kwargs: Any) -> Any:
                    nonlocal read_count
                    read_count += 1
                    if read_count == 3:
                        raise OSError("diagnostic count read failed")
                    return original_connection(*args, **kwargs)

                with patch.object(worker.store, "connection", side_effect=fail_only_count_read):
                    self.assertTrue(worker.run_once())
                records = capture.records()

        state = self._read_strategy(fixture, strategy_id)
        self.assertEqual(state["status"], "APPLIED")
        no_due = next(
            row for row in records
            if row["event"] == "selection" and row.get("outcome") == "no_due"
        )
        self.assertNotIn("eligible_count", no_due)
        self.assertNotIn("matching_eligible_count", no_due)

    def test_green_worker_preflight_resume_stage_is_distinct(self) -> None:
        fixture, worker, _ = self._queue_fixture()
        with patch.object(StrategyService, "_with_client_ids", staticmethod(self._deterministic_ids)):
            with _Capture() as capture:
                strategy_id, _ = self._start_queue(fixture, count=3)
                with patch("backend.strategy_worker.MAX_PLACEMENTS_PER_PASS", 1):
                    self.assertTrue(worker.run_once())
                mid = self._read_strategy(fixture, strategy_id)
                self.assertEqual(mid["status"], "APPLYING")
                self.assertEqual(mid["queue"]["cursor"], 1)
                fixture.now += 6
                self.assertTrue(worker.run_once())
                records = capture.records()

        state = self._read_strategy(fixture, strategy_id)
        self.assertEqual(state["status"], "APPLIED")
        self.assertEqual(fixture.exchange.single_order_attempts, 3)
        phases = [
            row["stage"] for row in records
            if row["event"] == "preflight" and row["component"] == "worker"
        ]
        self.assertEqual(
            phases,
            ["preflight_initial", "preflight_post_leverage", "preflight_resume"],
        )

    def test_red_hostile_unknown_ack_stops_tail_and_fence_loss_stays_uncommitted(self) -> None:
        fixture, worker, _ = self._queue_fixture()
        with patch.object(StrategyService, "_with_client_ids", staticmethod(self._deterministic_ids)):
            with _Capture() as capture:
                strategy_id, prepared = self._start_queue(fixture, count=3)
                fixture.exchange.single_order_acks[0] = {
                    "code": "0", "data": [{
                        "clOrdId": "hostile-order-id", "sCode": "0", "ordId": "raw-exchange-id",
                        "message": "credential-canary\\n\\x1b", "nested": {"token": "secret-value"},
                        "padding": "x" * 120_000,
                    }],
                }
                self.assertTrue(worker.run_once())
                records = capture.records()

        strategy = self._read_strategy(fixture, strategy_id)
        self.assertEqual(strategy["status"], "UNKNOWN")
        self.assertEqual([row["status"] for row in strategy["results"]], ["unknown", "not_submitted", "not_submitted"])
        self.assertEqual(fixture.exchange.single_order_attempts, 1)
        observed = next(row for row in records if row["event"] == "ack_observed" and row.get("stage") == "order")
        self.assertFalse(observed["persisted"])
        self.assertEqual(observed["ack_shape"], "client_identity_mismatch")
        raw = "\\n".join(json.dumps(row) for row in records)
        for canary in ("hostile-order-id", "raw-exchange-id", "credential-canary", "secret-value", "x" * 1024):
            self.assertNotIn(canary, raw)

        fixture2, worker2, _ = self._queue_fixture()
        with patch.object(StrategyService, "_with_client_ids", staticmethod(self._deterministic_ids)):
            with _Capture() as capture2:
                strategy2, prepared2 = self._start_queue(fixture2, count=3)

                def lose_fence(_payload: dict[str, Any], _order_id: str) -> None:
                    with fixture2.service.store.transaction() as connection:
                        connection.execute(
                            "UPDATE strategy_monitor_lease SET lease_until=? WHERE singleton=1",
                            (fixture2.now - 1,),
                        )

                fixture2.exchange.after_single_order_write = lose_fence
                self.assertTrue(worker2.run_once())
                records2 = capture2.records()

        pending = self._read_strategy(fixture2, strategy2)
        self.assertEqual(fixture2.exchange.single_order_attempts, 1)
        self.assertEqual(pending["queue"]["inFlight"], {"kind": "placement", "index": 0})
        ack = next(row for row in records2 if row["event"] == "ack_observed" and row.get("stage") == "order")
        refusal = next(row for row in records2 if row["event"] == "commit" and row.get("persisted") is False)
        self.assertFalse(ack["persisted"])
        self.assertFalse(refusal["persisted"])
        self.assertEqual(refusal["reason"], "fence_or_cas_loss")
        self.assertEqual(refusal["order_ref"], diagnostics.order_ref(prepared2["orders"][0]["clientOrderId"]))

    def test_green_batch_mixed_outcomes_are_summarized_with_safe_codes(self) -> None:
        fixture = api_fixtures.StrategyApiTests(
            "test_red_strategy_routes_require_bearer_before_exchange_reads"
        )
        fixture.setUp()
        self.addCleanup(fixture.tearDown)
        selected = [
            {"side": "long", "price": "59000", "levelId": "batch-entry"},
            {"side": "long", "price": "58900", "levelId": "batch-level-2"},
        ]
        contract = api_fixtures.StrategyApiTests.id_mode_contract(
            selected, entry_ids={"long": "batch-entry"}
        )
        with patch.object(StrategyService, "_with_client_ids", staticmethod(self._deterministic_ids)):
            with _Capture() as capture:
                strategy_id, _ = fixture.save_draft(contract)
                status, prepared = fixture.request(
                    "POST", f"/v1/strategies/{strategy_id}/prepare-apply", {}
                )
                self.assertEqual(status, 200, prepared)
                first, second = prepared["orders"]
                fixture.exchange.batch_top_code = "1"
                fixture.exchange.batch_ack = [
                    {"sCode": "0", "ordId": "raw-exchange-id-1", "clOrdId": first["clientOrderId"]},
                    {"sCode": "51008", "clOrdId": second["clientOrderId"]},
                ]
                status, result = fixture.request(
                    "POST", f"/v1/strategies/{strategy_id}/execute-apply",
                    {"confirmationToken": prepared["confirmationToken"]},
                )
                self.assertEqual(status, 200, result)
                records = capture.records()

        state = self._read_strategy(fixture, strategy_id)
        self.assertEqual(state["status"], "PARTIAL")
        self.assertEqual(state["results"][0]["status"], "accepted")
        self.assertEqual(state["results"][1]["status"], "rejected")
        summary = next(row for row in records if row["event"] == "batch_summary")
        self.assertEqual(summary["accepted_count"], 1)
        self.assertEqual(summary["status"], "PARTIAL")
        self.assertEqual(summary["top_code"], "1")
        self.assertTrue(any(
            row["event"] == "preflight" and row["component"] == "api"
            and row["stage"] == "preflight_initial" and row.get("submission_mode") == "batch"
            and row["outcome"] == "success"
            for row in records
        ))
        item = next(row for row in records if row["event"] == "ack_observed" and row.get("item_code") == "51008")
        self.assertFalse(item["persisted"])
        self.assertEqual(item["order_ref"], diagnostics.order_ref(second["clientOrderId"]))
        self.assertTrue(any(row["event"] == "commit" and row.get("persisted") is True and row.get("status") == "PARTIAL" for row in records))
        self.assertEqual(len(fixture.exchange.batch_writes), 1)
        serialized = "\\n".join(json.dumps(row) for row in records)
        self.assertNotIn("raw-exchange-id-1", serialized)
        self.assertNotIn(first["clientOrderId"], serialized)
        self.assertNotIn(second["clientOrderId"], serialized)

    def test_green_ack_shape_classifiers_match_parser_stages(self) -> None:
        order = {"clientOrderId": "shape-order-1"}
        valid_row = {"sCode": "0", "ordId": "exchange-order-1", "clOrdId": order["clientOrderId"]}
        self.assertEqual(StrategyOrderWorker._order_ack_shape({}, order["clientOrderId"], "unknown", None), "missing_code")
        self.assertEqual(StrategyOrderWorker._order_ack_shape({"code": "bad"}, order["clientOrderId"], "unknown", None), "invalid_code")
        self.assertEqual(StrategyOrderWorker._order_ack_shape({"code": "0", "data": []}, order["clientOrderId"], "unknown", None), "data_cardinality")
        self.assertEqual(StrategyOrderWorker._order_ack_shape({"code": "0", "data": [None]}, order["clientOrderId"], "unknown", None), "invalid_row")
        self.assertEqual(
            StrategyOrderWorker._order_ack_shape(
                {"code": "0", "data": [{**valid_row, "clOrdId": "different-client"}]},
                order["clientOrderId"], "unknown", None,
            ),
            "client_identity_mismatch",
        )
        missing_item_code = {key: value for key, value in valid_row.items() if key != "sCode"}
        self.assertEqual(
            StrategyOrderWorker._order_ack_shape(
                {"code": "0", "data": [missing_item_code]}, order["clientOrderId"], "unknown", None
            ),
            "missing_code",
        )
        self.assertEqual(
            StrategyOrderWorker._order_ack_shape(
                {"code": "0", "data": [{**valid_row, "sCode": "raw-code"}]},
                order["clientOrderId"], "unknown", None,
            ),
            "invalid_code",
        )
        self.assertEqual(
            StrategyOrderWorker._order_ack_shape(
                {"code": "0", "data": [{**valid_row, "ordId": ""}]},
                order["clientOrderId"], "unknown", None,
            ),
            "missing_order_id",
        )

        orders = [order, {"clientOrderId": "shape-order-2"}]
        self.assertEqual(
            StrategyService._batch_ack_shape(
                {"code": "0", "data": [valid_row]}, [{"clientOrderId": []}]
            ),
            "invalid_row",
        )
        mixed = {"code": "1", "data": [
            valid_row,
            {"sCode": "51008", "clOrdId": orders[1]["clientOrderId"]},
        ]}
        outcomes, state, _ = StrategyService._parse_batch_ack(mixed, orders)
        self.assertEqual(state, "PARTIAL")
        self.assertEqual([row["status"] for row in outcomes], ["accepted", "rejected"])
        self.assertEqual(StrategyService._batch_ack_shape(mixed, orders), "valid")

        all_accepted = {"code": "1", "data": [
            valid_row,
            {"sCode": "0", "ordId": "exchange-order-2", "clOrdId": orders[1]["clientOrderId"]},
        ]}
        _, conflict_state, _ = StrategyService._parse_batch_ack(all_accepted, orders)
        self.assertEqual(conflict_state, "UNKNOWN")
        self.assertEqual(StrategyService._batch_ack_shape(all_accepted, orders), "top_level_conflict")

        leverage = {
            "code": "0", "data": [{"sCode": "0", "instId": "BTC-USDT-SWAP",
                                    "mgnMode": "isolated", "posSide": "net", "lever": "5.0"}],
        }
        self.assertEqual(
            StrategyOrderWorker._leverage_ack_shape(
                leverage, expected_pos_side="net", expected_instrument_id="BTC-USDT-SWAP",
                expected_leverage=5,
            ),
            "valid",
        )

    def _run_queue_with_sink(self, mode: str) -> tuple[list[Any], tuple[Any, ...]]:
        fixture, worker, _ = self._queue_fixture()
        entered = threading.Event()
        release = threading.Event()

        class BlockingStream:
            def __init__(self) -> None:
                self.first = True

            def write(self, _: str) -> None:
                if self.first:
                    self.first = False
                    entered.set()
                    release.wait(2)

            def flush(self) -> None:
                return

        class RaisingStream:
            def write(self, _: str) -> None:
                raise OSError("credential-canary sink exception")

            def flush(self) -> None:
                return

        stream: Any
        maxsize = diagnostics.MAX_QUEUE_LENGTH
        if mode == "working":
            stream = io.StringIO()
        elif mode in {"full", "stalled"}:
            stream = BlockingStream()
            maxsize = 1 if mode == "full" else diagnostics.MAX_QUEUE_LENGTH
        elif mode == "raising":
            stream = RaisingStream()
        elif mode == "disabled":
            stream = io.StringIO()
        else:
            raise AssertionError("unknown test sink mode")

        original = diagnostics._DEFAULT_SINK
        sink = diagnostics._Sink(maxsize=maxsize, stream=stream)
        diagnostics._DEFAULT_SINK = sink
        try:
            if mode in {"full", "stalled"}:
                seed = diagnostics._new_record(
                    "heartbeat", {"component": "worker", "stage": "heartbeat", "outcome": "success"}
                )
                sink.emit_record(seed)
                self.assertTrue(entered.wait(1))
            emitter = (
                patch.object(diagnostics, "emit_event", return_value=False)
                if mode == "disabled" else nullcontext()
            )
            with emitter:
                with patch.object(StrategyService, "_with_client_ids", staticmethod(self._deterministic_ids)):
                    strategy_id, prepared = self._start_queue(fixture, count=3)
                    worker.run_once()
            state = self._read_strategy(fixture, strategy_id)
            orders = tuple(
                (row["status"], row.get("exchangeOrderId"), row.get("filledContracts"))
                for row in state["results"]
            )
            snapshot = (
                state["status"], state["queue"]["phase"], state["queue"]["cursor"],
                state["orderPlacementAttempted"], orders,
            )
            self.assertEqual(len(prepared["orders"]), 3)
            return list(fixture.exchange.calls), snapshot
        finally:
            release.set()
            sink.shutdown()
            diagnostics._DEFAULT_SINK = original

    def test_green_exchange_payload_and_state_parity_across_sink_failures(self) -> None:
        baseline_calls, baseline_state = self._run_queue_with_sink("working")
        self.assertEqual(baseline_state[0:4], ("APPLIED", "submitted", 3, True))
        calls, state = self._run_queue_with_sink("disabled")
        self.assertEqual(calls, baseline_calls, "disabled")
        self.assertEqual(state, baseline_state, "disabled")
        for mode in ("full", "raising", "stalled"):
            calls, state = self._run_queue_with_sink(mode)
            self.assertEqual(calls, baseline_calls, mode)
            self.assertEqual(state, baseline_state, mode)


if __name__ == "__main__":
    unittest.main()
