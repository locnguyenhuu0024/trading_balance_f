from __future__ import annotations

from copy import deepcopy
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from email.utils import format_datetime

from backend.data_gateway import DataGateway, GatewayError
from backend.okx import OKXError
from backend.service import APIError, TradeService


SUPPORTED_TYPES = ("MARGIN", "SWAP", "FUTURES")


class ControlledClock:
    def __init__(self) -> None:
        self.monotonic = 100.0
        self.wall = 1_800_000_000.0
        self._lock = threading.Lock()

    def now_monotonic(self) -> float:
        with self._lock:
            return self.monotonic

    def now_wall(self) -> float:
        with self._lock:
            return self.wall

    def advance(self, seconds: float) -> None:
        with self._lock:
            self.monotonic += seconds
            self.wall += seconds


class PressureOKX:
    def __init__(self) -> None:
        self.account = {
            "uid": "account-1",
            "posMode": "net_mode",
            "acctLv": "2",
        }
        self.positions = {
            "MARGIN": [{"instId": "BTC-USDT", "pos": "1", "posSide": "net"}],
            "SWAP": [{"instId": "BTC-USDT-SWAP", "pos": "2", "posSide": "net"}],
            "FUTURES": [{"instId": "BTC-USDT-260925", "pos": "3", "posSide": "net"}],
        }
        self.calls: list[tuple[str, str, dict[str, str] | None]] = []
        self._lock = threading.Lock()
        self.config_error: OKXError | None = None
        self.config_error_on_call: int | None = None
        self.config_entered: threading.Event | None = None
        self.config_release: threading.Event | None = None
        self.config_entered_on_call: dict[int, threading.Event] = {}
        self.config_release_on_call: dict[int, threading.Event] = {}
        self.switch_account_on_config_call: int | None = None
        self.block_positions = False
        self.positions_entered = {kind: threading.Event() for kind in SUPPORTED_TYPES}
        self.positions_release = threading.Event()
        self.fail_position_type: str | None = None
        self.fail_position_release: threading.Event | None = None
        self.switch_account_after_position_type: str | None = None
        self.positions_completed: set[str] = set()
        self.identity_observations: list[frozenset[str]] = []
        self.block_public = False
        self.public_entered = {kind: threading.Event() for kind in SUPPORTED_TYPES}
        self.public_release = threading.Event()

    def account_config(self) -> dict:
        with self._lock:
            self.calls.append(("GET", "/api/v5/account/config", None))
            call_number = sum(call[1] == "/api/v5/account/config" for call in self.calls)
            self.identity_observations.append(frozenset(self.positions_completed))
        entered = self.config_entered_on_call.get(call_number)
        release = self.config_release_on_call.get(call_number)
        if entered is not None:
            entered.set()
        if release is not None and not release.wait(5):
            raise TimeoutError("identity fixture was not released")
        if self.config_entered is not None:
            self.config_entered.set()
        if self.config_release is not None and not self.config_release.wait(5):
            raise TimeoutError("identity fixture was not released")
        if self.config_error is not None and (
            self.config_error_on_call is None or self.config_error_on_call == call_number
        ):
            raise self.config_error
        with self._lock:
            if self.switch_account_on_config_call == call_number:
                self.account["uid"] = "account-2"
                self.switch_account_on_config_call = None
            return deepcopy(self.account)

    def request(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, str] | None = None,
        private: bool | None = None,
        **_: object,
    ) -> dict:
        with self._lock:
            self.calls.append((method, path, deepcopy(params)))
        if path == "/api/v5/account/positions":
            instrument_type = (params or {})["instType"]
            if self.block_positions:
                self.positions_entered[instrument_type].set()
                release = (
                    self.fail_position_release
                    if instrument_type == self.fail_position_type
                    else self.positions_release
                )
                if release is not None and not release.wait(5):
                    raise TimeoutError("position fixture was not released")
            if instrument_type == self.fail_position_type:
                raise OKXError("safe simulated failure", error_code="50000")
            with self._lock:
                self.positions_completed.add(instrument_type)
                if self.switch_account_after_position_type == instrument_type:
                    self.account["uid"] = "account-2"
                    self.switch_account_after_position_type = None
                rows = deepcopy(self.positions[instrument_type])
            return {"code": "0", "msg": "", "data": rows}
        if path == "/api/v5/public/instruments":
            instrument_type = (params or {})["instType"]
            if self.block_public:
                self.public_entered[instrument_type].set()
                if not self.public_release.wait(5):
                    raise TimeoutError("public metadata fixture was not released")
            return {
                "code": "0",
                "msg": "",
                "data": [{
                    "instId": f"BTC-USDT-{instrument_type}",
                    "baseCcy": "BTC",
                    "quoteCcy": "USDT",
                }],
            }
        return {"code": "0", "msg": "", "data": []}

    def count(self, path: str) -> int:
        with self._lock:
            return sum(call[1] == path for call in self.calls)


def make_gateway(exchange: PressureOKX, clock: ControlledClock) -> DataGateway:
    return DataGateway(
        exchange,
        account_fingerprint=lambda uid: None if uid is None else f"fingerprint:{uid}",
        monotonic_clock=clock.now_monotonic,
        wall_clock=clock.now_wall,
    )


def make_service(gateway: DataGateway) -> TradeService:
    service = TradeService.__new__(TradeService)
    service.data_gateway = gateway
    service._require_session = lambda _environ: "session"
    service._display_executor = ThreadPoolExecutor(max_workers=3)
    service._display_admission = threading.BoundedSemaphore(6)
    return service


class IdentityCooldownRedTests(unittest.TestCase):
    def test_identity_429_is_shared_by_concurrent_authorized_callers(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        exchange.config_error = OKXError(
            "safe simulated limit", error_code="50011", http_status=429, retry_after="29"
        )
        exchange.config_entered = threading.Event()
        exchange.config_release = threading.Event()
        gateway = make_gateway(exchange, clock)
        failures: list[GatewayError] = []
        failure_lock = threading.Lock()

        def read_identity() -> None:
            try:
                gateway.identity_for_display(session_guard=lambda: None)
            except GatewayError as error:
                with failure_lock:
                    failures.append(error)

        first = threading.Thread(target=read_identity)
        second = threading.Thread(target=read_identity)
        first.start()
        self.assertTrue(exchange.config_entered.wait(2))
        second.start()
        exchange.config_release.set()
        first.join(3)
        second.join(3)

        self.assertFalse(first.is_alive())
        self.assertFalse(second.is_alive())
        self.assertEqual(len(failures), 2)
        self.assertTrue(all(error.status == 429 for error in failures))
        self.assertTrue(all(error.headers == [("Retry-After", "29")] for error in failures))
        self.assertEqual(exchange.count("/api/v5/account/config"), 1)

    def test_identity_429_cooldown_skips_exchange_and_returns_remaining_delay(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        exchange.config_error = OKXError(
            "safe simulated limit", error_code="50011", http_status=429, retry_after="29"
        )
        gateway = make_gateway(exchange, clock)
        guard = lambda: None

        with self.assertRaises(GatewayError) as first:
            gateway.identity_for_display(session_guard=guard)
        self.assertEqual(first.exception.status, 429)
        clock.advance(4.2)
        with self.assertRaises(GatewayError) as second:
            gateway.identity_for_display(session_guard=guard)

        self.assertEqual(second.exception.status, 429)
        self.assertEqual(second.exception.code, "exchange_rate_limited")
        self.assertEqual(second.exception.headers, [("Retry-After", "25")])
        self.assertEqual(exchange.count("/api/v5/account/config"), 1)

    def test_identity_429_accepts_http_date_and_preserves_long_delay(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        retry_at = datetime.fromtimestamp(clock.wall + 37.0, tz=timezone.utc)
        date_error = OKXError(
            "safe simulated limit",
            error_code="50011",
            http_status=429,
        )
        date_error.retry_after = format_datetime(retry_at, usegmt=True)
        exchange.config_error = date_error
        gateway = make_gateway(exchange, clock)
        with self.assertRaises(GatewayError) as first:
            gateway.identity_for_display(session_guard=lambda: None)
        self.assertEqual(first.exception.headers, [("Retry-After", "37")])

        clock.advance(2.2)
        with self.assertRaises(GatewayError) as remaining:
            gateway.identity_for_display(session_guard=lambda: None)
        self.assertEqual(remaining.exception.headers, [("Retry-After", "35")])
        self.assertEqual(exchange.count("/api/v5/account/config"), 1)

        long_clock = ControlledClock()
        long_exchange = PressureOKX()
        long_exchange.config_error = OKXError(
            "safe simulated limit", error_code="50011", http_status=429, retry_after="100000"
        )
        long_gateway = make_gateway(long_exchange, long_clock)
        with self.assertRaises(GatewayError) as long_delay:
            long_gateway.identity_for_display(session_guard=lambda: None)
        self.assertEqual(long_delay.exception.headers, [("Retry-After", "100000")])
        self.assertEqual(long_exchange.count("/api/v5/account/config"), 1)

    def test_expired_cooldown_coalesces_one_recovery_identity_read(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        exchange.config_error = OKXError(
            "safe simulated limit", error_code="50011", http_status=429, retry_after="2"
        )
        exchange.config_error_on_call = 1
        recovery_entered = threading.Event()
        recovery_release = threading.Event()
        exchange.config_entered_on_call[2] = recovery_entered
        exchange.config_release_on_call[2] = recovery_release
        gateway = make_gateway(exchange, clock)

        with self.assertRaises(GatewayError):
            gateway.identity_for_display(session_guard=lambda: None)
        clock.advance(2.1)

        results: list[object] = []

        def recover() -> None:
            try:
                results.append(gateway.identity_for_display(session_guard=lambda: None))
            except BaseException as error:
                results.append(error)

        first = threading.Thread(target=recover)
        second = threading.Thread(target=recover)
        first.start()
        self.assertTrue(recovery_entered.wait(2))
        second.start()
        recovery_release.set()
        first.join(3)
        second.join(3)

        self.assertFalse(first.is_alive())
        self.assertFalse(second.is_alive())
        self.assertEqual(len(results), 2)
        self.assertTrue(all(not isinstance(result, BaseException) for result in results))
        self.assertEqual(exchange.count("/api/v5/account/config"), 2)

    def test_private_standalone_429_rechecks_caller_authorization(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        exchange.config_error = OKXError(
            "safe simulated limit", error_code="50011", http_status=429, retry_after="29"
        )
        exchange.config_entered = threading.Event()
        exchange.config_release = threading.Event()
        gateway = make_gateway(exchange, clock)
        revoked = threading.Event()
        outcomes: list[GatewayError] = []

        class ExpiredSession(Exception):
            status = 401
            code = "authentication_required"

        def guard() -> None:
            if revoked.is_set():
                raise ExpiredSession()

        def read() -> None:
            try:
                gateway.handle("GET", "account/balance", "", session_guard=guard)
            except GatewayError as error:
                outcomes.append(error)

        worker = threading.Thread(target=read)
        worker.start()
        self.assertTrue(exchange.config_entered.wait(2))
        revoked.set()
        exchange.config_release.set()
        worker.join(3)

        self.assertFalse(worker.is_alive())
        self.assertEqual(len(outcomes), 1)
        self.assertEqual(outcomes[0].status, 401)

    def test_action_invalidation_preserves_observed_identity_cooldown(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        exchange.config_error = OKXError(
            "safe simulated limit", error_code="50011", http_status=429, retry_after="29"
        )
        exchange.config_entered = threading.Event()
        exchange.config_release = threading.Event()
        gateway = make_gateway(exchange, clock)
        outcome: list[GatewayError] = []

        def read() -> None:
            try:
                gateway.handle("GET", "account/balance", "", session_guard=lambda: None)
            except GatewayError as error:
                outcome.append(error)

        worker = threading.Thread(target=read)
        worker.start()
        self.assertTrue(exchange.config_entered.wait(2))
        gateway.invalidate_private()
        exchange.config_release.set()
        worker.join(3)

        self.assertFalse(worker.is_alive())
        self.assertEqual(len(outcome), 1)
        self.assertEqual(outcome[0].status, 409)
        with self.assertRaises(GatewayError) as during_cooldown:
            gateway.identity_for_display(session_guard=lambda: None)
        self.assertEqual(during_cooldown.exception.status, 429)
        self.assertEqual(during_cooldown.exception.headers, [("Retry-After", "29")])
        self.assertEqual(exchange.count("/api/v5/account/config"), 1)

    def test_old_rate_limit_fences_new_identity_until_shared_recovery(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        exchange.config_error = OKXError(
            "safe simulated limit", error_code="50011", http_status=429, retry_after="29"
        )
        exchange.config_error_on_call = 1
        first_entered = threading.Event()
        first_release = threading.Event()
        second_entered = threading.Event()
        second_release = threading.Event()
        exchange.config_entered_on_call[1] = first_entered
        exchange.config_release_on_call[1] = first_release
        exchange.config_entered_on_call[2] = second_entered
        exchange.config_release_on_call[2] = second_release
        gateway = make_gateway(exchange, clock)
        first_result: list[object] = []
        second_result: list[object] = []

        def read(result: list[object]) -> None:
            try:
                result.append(gateway.identity_for_display(session_guard=lambda: None))
            except GatewayError as error:
                result.append(error)

        stale_read = threading.Thread(target=read, args=(first_result,))
        stale_read.start()
        self.assertTrue(first_entered.wait(2))
        gateway.invalidate_private()

        current_read = threading.Thread(target=read, args=(second_result,))
        current_read.start()
        self.assertTrue(second_entered.wait(2))

        second_follower_result: list[object] = []
        second_follower_waiting = threading.Event()
        current_flight = gateway._identity_flight
        self.assertIsNotNone(current_flight)
        original_current_wait = current_flight.event.wait

        def observed_current_wait(timeout: float | None = None) -> bool:
            if threading.current_thread().name == "cooldown-follower":
                second_follower_waiting.set()
            return original_current_wait(timeout)

        current_flight.event.wait = observed_current_wait
        current_follower = threading.Thread(
            target=read, args=(second_follower_result,), name="cooldown-follower"
        )
        current_follower.start()
        self.assertTrue(second_follower_waiting.wait(2))

        first_release.set()
        stale_read.join(3)
        self.assertFalse(stale_read.is_alive())
        self.assertEqual(len(first_result), 1)
        self.assertIsInstance(first_result[0], GatewayError)
        self.assertEqual(first_result[0].status, 409)

        second_release.set()
        current_read.join(3)
        current_follower.join(3)
        self.assertFalse(current_read.is_alive())
        self.assertFalse(current_follower.is_alive())
        self.assertEqual(len(second_result), 1)
        self.assertEqual(len(second_follower_result), 1)
        for result in (second_result[0], second_follower_result[0]):
            self.assertIsInstance(result, GatewayError)
            self.assertEqual(result.status, 429)
            self.assertEqual(result.headers, [("Retry-After", "29")])
        self.assertIsNone(gateway._identity)

        for _ in range(2):
            with self.assertRaises(GatewayError) as during_cooldown:
                gateway.identity_for_display(session_guard=lambda: None)
            self.assertEqual(during_cooldown.exception.status, 429)
        self.assertEqual(exchange.count("/api/v5/account/config"), 2)

        clock.advance(29.1)
        recovery_entered = threading.Event()
        recovery_release = threading.Event()
        exchange.config_entered_on_call[3] = recovery_entered
        exchange.config_release_on_call[3] = recovery_release
        recovery_results: list[object] = []
        recovery_leader = threading.Thread(
            target=read, args=(recovery_results,), name="recovery-leader"
        )
        recovery_leader.start()
        self.assertTrue(recovery_entered.wait(2))
        recovery_flight = gateway._identity_flight
        self.assertIsNotNone(recovery_flight)
        follower_waiting = threading.Event()
        original_wait = recovery_flight.event.wait

        def observed_wait(timeout: float | None = None) -> bool:
            if threading.current_thread().name == "recovery-follower":
                follower_waiting.set()
            return original_wait(timeout)

        recovery_flight.event.wait = observed_wait
        recovery_follower = threading.Thread(
            target=read, args=(recovery_results,), name="recovery-follower"
        )
        recovery_follower.start()
        self.assertTrue(follower_waiting.wait(2))
        recovery_release.set()
        recovery_leader.join(3)
        recovery_follower.join(3)

        self.assertFalse(recovery_leader.is_alive())
        self.assertFalse(recovery_follower.is_alive())
        self.assertEqual(len(recovery_results), 2)
        self.assertTrue(all(not isinstance(result, GatewayError) for result in recovery_results))
        self.assertEqual(recovery_results[0].generation, recovery_results[1].generation)
        self.assertEqual(exchange.count("/api/v5/account/config"), 3)

    def test_postcheck_429_reaches_shared_bundle_callers(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        exchange.block_positions = True
        exchange.config_error = OKXError(
            "safe simulated limit", error_code="50011", http_status=429, retry_after="29"
        )
        exchange.config_error_on_call = 2
        gateway = make_gateway(exchange, clock)
        waiter_entered = threading.Event()
        original_wait = gateway._wait_for_flight

        def observed_wait(flight, identity, private):
            waiter_entered.set()
            return original_wait(flight, identity, private)

        gateway._wait_for_flight = observed_wait
        failures: list[GatewayError] = []
        lock = threading.Lock()

        def read() -> None:
            try:
                gateway.read_display_positions(session_guard=lambda: None)
            except GatewayError as error:
                with lock:
                    failures.append(error)

        leader = threading.Thread(target=read)
        follower = threading.Thread(target=read)
        leader.start()
        self.assertTrue(all(exchange.positions_entered[kind].wait(2) for kind in SUPPORTED_TYPES))
        follower.start()
        self.assertTrue(waiter_entered.wait(2))
        exchange.positions_release.set()
        leader.join(5)
        follower.join(5)

        self.assertFalse(leader.is_alive())
        self.assertFalse(follower.is_alive())
        self.assertEqual(len(failures), 2)
        self.assertTrue(all(error.status == 429 for error in failures))
        self.assertEqual(exchange.count("/api/v5/account/config"), 2)
        self.assertEqual(exchange.count("/api/v5/account/positions"), 3)
        with self.assertRaises(GatewayError) as cooldown:
            gateway.identity_for_display(session_guard=lambda: None)
        self.assertEqual(cooldown.exception.headers, [("Retry-After", "29")])
        self.assertEqual(exchange.count("/api/v5/account/config"), 2)

    def test_independent_invalidation_supersedes_postcheck_429_and_keeps_cooldown(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        exchange.block_positions = True
        exchange.config_error = OKXError(
            "safe simulated limit", error_code="50011", http_status=429, retry_after="29"
        )
        exchange.config_error_on_call = 2
        postcheck_entered = threading.Event()
        postcheck_release = threading.Event()
        exchange.config_entered_on_call[2] = postcheck_entered
        exchange.config_release_on_call[2] = postcheck_release
        gateway = make_gateway(exchange, clock)
        waiter_entered = threading.Event()
        original_wait = gateway._wait_for_flight

        def observed_wait(flight, identity, private):
            waiter_entered.set()
            return original_wait(flight, identity, private)

        gateway._wait_for_flight = observed_wait
        outcomes: list[GatewayError] = []

        def read() -> None:
            try:
                gateway.read_display_positions(session_guard=lambda: None)
            except GatewayError as error:
                outcomes.append(error)

        leader = threading.Thread(target=read)
        follower = threading.Thread(target=read)
        leader.start()
        self.assertTrue(all(exchange.positions_entered[kind].wait(2) for kind in SUPPORTED_TYPES))
        exchange.positions_release.set()
        self.assertTrue(postcheck_entered.wait(2))
        follower.start()
        self.assertTrue(waiter_entered.wait(2))
        gateway.invalidate_private()
        postcheck_release.set()
        leader.join(5)
        follower.join(5)

        self.assertFalse(leader.is_alive())
        self.assertFalse(follower.is_alive())
        self.assertEqual(len(outcomes), 2)
        self.assertTrue(all(error.status == 409 for error in outcomes))
        with self.assertRaises(GatewayError) as cooldown:
            gateway.identity_for_display(session_guard=lambda: None)
        self.assertEqual(cooldown.exception.status, 429)
        self.assertEqual(exchange.count("/api/v5/account/config"), 2)


class BundleSafetyRedTests(unittest.TestCase):
    def test_invalidation_fences_staged_bundle_without_publishing_cache(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        exchange.block_positions = True
        gateway = make_gateway(exchange, clock)
        service = make_service(gateway)
        failures: list[BaseException] = []

        def read_bundle() -> None:
            try:
                service._fetch_display_snapshot({})
            except BaseException as error:
                failures.append(error)

        worker = threading.Thread(target=read_bundle)
        worker.start()
        self.assertTrue(all(exchange.positions_entered[kind].wait(2) for kind in SUPPORTED_TYPES))
        gateway.invalidate_private()
        exchange.positions_release.set()
        worker.join(5)

        self.assertFalse(worker.is_alive())
        self.assertEqual(len(failures), 1)
        self.assertIsInstance(failures[0], APIError)
        self.assertEqual(failures[0].status, 409)
        self.assertFalse(any(entry.private for entry in gateway._cache.values()))
        service._display_executor.shutdown(wait=True)

    def test_revoked_leader_does_not_poison_authorized_follower(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        exchange.block_positions = True
        gateway = make_gateway(exchange, clock)
        service = make_service(gateway)
        leader_environ = {"revoked": False}
        follower_environ = {"revoked": False}

        def require_session(environ: dict[str, bool]) -> str:
            if environ["revoked"]:
                raise APIError(401, "authentication_required", "A valid session is required.")
            return "session"

        service._require_session = require_session
        leader_failure: list[BaseException] = []
        follower_result: list[object] = []

        def leader() -> None:
            try:
                service._fetch_display_snapshot(leader_environ)
            except BaseException as error:
                leader_failure.append(error)

        def follower() -> None:
            try:
                follower_result.append(service._fetch_display_snapshot(follower_environ))
            except BaseException as error:
                follower_result.append(error)

        first = threading.Thread(target=leader)
        second = threading.Thread(target=follower)
        first.start()
        self.assertTrue(all(exchange.positions_entered[kind].wait(2) for kind in SUPPORTED_TYPES))
        second.start()
        leader_environ["revoked"] = True
        exchange.positions_release.set()
        first.join(5)
        second.join(5)

        self.assertFalse(first.is_alive())
        self.assertFalse(second.is_alive())
        self.assertEqual(len(leader_failure), 1)
        self.assertIsInstance(leader_failure[0], APIError)
        self.assertEqual(leader_failure[0].status, 401)
        self.assertEqual(len(follower_result), 1)
        self.assertFalse(isinstance(follower_result[0], BaseException))
        self.assertEqual(exchange.count("/api/v5/account/positions"), 3)
        service._display_executor.shutdown(wait=True)

    def test_partial_failure_drains_all_private_siblings(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        exchange.block_positions = True
        exchange.fail_position_type = "MARGIN"
        exchange.fail_position_release = threading.Event()
        gateway = make_gateway(exchange, clock)
        service = make_service(gateway)
        outcome: list[BaseException] = []
        returned = threading.Event()

        def read_bundle() -> None:
            try:
                service._fetch_display_snapshot({})
            except BaseException as error:
                outcome.append(error)
            finally:
                returned.set()

        worker = threading.Thread(target=read_bundle)
        worker.start()
        try:
            self.assertTrue(
                all(exchange.positions_entered[kind].wait(2) for kind in SUPPORTED_TYPES)
            )
            exchange.fail_position_release.set()
            self.assertFalse(returned.wait(0.05))
            exchange.positions_release.set()
            worker.join(5)

            self.assertFalse(worker.is_alive())
            self.assertEqual(len(outcome), 1)
            self.assertIsInstance(outcome[0], APIError)
            self.assertEqual(exchange.count("/api/v5/account/positions"), 3)
            self.assertFalse(
                any(len(key) > 3 and key[3] == "$display/positions" for key in gateway._cache)
            )
        finally:
            exchange.fail_position_release.set()
            exchange.positions_release.set()
            worker.join(5)
            service._display_executor.shutdown(wait=True)


    def test_account_switch_after_private_reads_rejects_bundle(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        exchange.switch_account_on_config_call = 2
        gateway = make_gateway(exchange, clock)

        with self.assertRaises(GatewayError) as raised:
            gateway.read_display_positions(session_guard=lambda: None)

        self.assertEqual(raised.exception.status, 409)
        self.assertEqual(exchange.count("/api/v5/account/positions"), 3)
        self.assertEqual(exchange.identity_observations[0], frozenset())
        self.assertEqual(exchange.identity_observations[1], frozenset(SUPPORTED_TYPES))
        self.assertFalse(
            any(len(key) > 3 and key[3] == "$display/positions" for key in gateway._cache)
        )

    def test_final_publication_invalidation_rejects_service_response(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        exchange.block_public = True
        gateway = make_gateway(exchange, clock)
        service = make_service(gateway)
        outcome: list[BaseException] = []

        def read() -> None:
            try:
                service._fetch_display_snapshot({})
            except BaseException as error:
                outcome.append(error)

        worker = threading.Thread(target=read)
        worker.start()
        self.assertTrue(all(exchange.public_entered[kind].wait(2) for kind in SUPPORTED_TYPES))
        gateway.invalidate_private()
        exchange.public_release.set()
        worker.join(5)

        self.assertFalse(worker.is_alive())
        self.assertEqual(len(outcome), 1)
        self.assertIsInstance(outcome[0], APIError)
        self.assertEqual(outcome[0].status, 409)
        self.assertFalse(any(entry.private for entry in gateway._cache.values()))
        service._display_executor.shutdown(wait=True)

    def test_revoked_service_caller_gets_401_over_shared_postcheck_429(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        exchange.block_positions = True
        exchange.config_error = OKXError(
            "safe simulated limit", error_code="50011", http_status=429, retry_after="29"
        )
        exchange.config_error_on_call = 2
        postcheck_entered = threading.Event()
        postcheck_release = threading.Event()
        exchange.config_entered_on_call[2] = postcheck_entered
        exchange.config_release_on_call[2] = postcheck_release
        gateway = make_gateway(exchange, clock)
        service = make_service(gateway)
        revoked = threading.Event()
        outcome: list[BaseException] = []

        def require_session(_environ) -> str:
            if revoked.is_set():
                raise APIError(401, "authentication_required", "A valid session is required.")
            return "session"

        service._require_session = require_session

        def read() -> None:
            try:
                service._fetch_display_snapshot({})
            except BaseException as error:
                outcome.append(error)

        worker = threading.Thread(target=read)
        worker.start()
        self.assertTrue(all(exchange.positions_entered[kind].wait(2) for kind in SUPPORTED_TYPES))
        exchange.positions_release.set()
        self.assertTrue(postcheck_entered.wait(2))
        revoked.set()
        postcheck_release.set()
        worker.join(5)

        self.assertFalse(worker.is_alive())
        self.assertEqual(len(outcome), 1)
        self.assertIsInstance(outcome[0], APIError)
        self.assertEqual(outcome[0].status, 401)
        service._display_executor.shutdown(wait=True)

    def test_timed_out_bundle_reader_retains_aggregate_capacity_until_siblings_settle(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        exchange.block_positions = True
        gateway = make_gateway(exchange, clock)
        gateway._aggregate_slots = threading.BoundedSemaphore(1)
        gateway.READ_ACQUIRE_TIMEOUT_SECONDS = 0.01
        gateway.FLIGHT_WAIT_TIMEOUT_SECONDS = 0.01
        failures: list[GatewayError] = []

        def read_bundle() -> None:
            try:
                gateway.read_display_positions(session_guard=lambda: None)
            except GatewayError as error:
                failures.append(error)

        worker = threading.Thread(target=read_bundle)
        worker.start()
        self.assertTrue(all(exchange.positions_entered[kind].wait(2) for kind in SUPPORTED_TYPES))
        gateway.invalidate_private()
        with self.assertRaises(GatewayError) as second:
            gateway.read_display_positions(session_guard=lambda: None)

        self.assertEqual(second.exception.status, 503)
        self.assertEqual(exchange.count("/api/v5/account/positions"), 3)
        self.assertEqual(gateway._aggregate_slots._value, 0)
        self.assertTrue(worker.is_alive())

        exchange.positions_release.set()
        worker.join(5)
        self.assertFalse(worker.is_alive())
        self.assertEqual(len(failures), 1)
        self.assertEqual(failures[0].status, 409)
        self.assertEqual(gateway._aggregate_slots._value, 1)

        exchange.block_positions = False
        gateway.read_display_positions(session_guard=lambda: None)
        self.assertEqual(exchange.count("/api/v5/account/positions"), 6)


class PositionReadPressureGreenTests(unittest.TestCase):
    def test_cold_and_five_second_refresh_call_budgets(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        gateway = make_gateway(exchange, clock)
        service = make_service(gateway)
        try:
            first = service._fetch_display_snapshot({})
            self.assertTrue(first["positions"])
            self.assertEqual(exchange.count("/api/v5/account/config"), 2)
            self.assertEqual(exchange.count("/api/v5/account/positions"), 3)
            self.assertEqual(exchange.count("/api/v5/public/instruments"), 3)

            config_before = exchange.count("/api/v5/account/config")
            positions_before = exchange.count("/api/v5/account/positions")
            instruments_before = exchange.count("/api/v5/public/instruments")
            clock.advance(5.0)
            second = service._fetch_display_snapshot({})

            self.assertEqual(second["positions"], first["positions"])
            self.assertEqual(exchange.count("/api/v5/account/config") - config_before, 2)
            self.assertEqual(exchange.count("/api/v5/account/positions") - positions_before, 3)
            self.assertEqual(exchange.count("/api/v5/public/instruments") - instruments_before, 0)
        finally:
            service._display_executor.shutdown(wait=True)

    def test_concurrent_cold_display_callers_share_private_bundle(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        exchange.block_positions = True
        gateway = make_gateway(exchange, clock)
        service = make_service(gateway)
        start = threading.Barrier(3)
        results: list[dict] = []
        failures: list[BaseException] = []

        def request() -> None:
            try:
                start.wait()
                results.append(service._fetch_display_snapshot({}))
            except BaseException as error:
                failures.append(error)

        workers = [threading.Thread(target=request) for _ in range(2)]
        try:
            for worker in workers:
                worker.start()
            start.wait()
            self.assertTrue(all(exchange.positions_entered[kind].wait(2) for kind in SUPPORTED_TYPES))
            exchange.positions_release.set()
            for worker in workers:
                worker.join(5)

            self.assertTrue(all(not worker.is_alive() for worker in workers))
            self.assertEqual(failures, [])
            self.assertEqual(len(results), 2)
            self.assertEqual(exchange.count("/api/v5/account/positions"), 3)
        finally:
            exchange.positions_release.set()
            service._display_executor.shutdown(wait=True)

    def test_slow_metadata_allows_only_one_service_freshness_retry(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        gateway = make_gateway(exchange, clock)
        service = make_service(gateway)
        original_read = gateway.read_internal_with_deadline
        public_calls = 0

        def slow_public_read(suffix, params, *, session_guard=None):
            nonlocal public_calls
            data, deadline = original_read(suffix, params, session_guard=session_guard)
            if suffix == "public/instruments":
                public_calls += 1
                if public_calls in {1, 4}:
                    clock.advance(1.1)
            return data, deadline

        gateway.read_internal_with_deadline = slow_public_read
        try:
            with self.assertRaises(APIError) as raised:
                service._fetch_display_snapshot({})
            self.assertEqual(raised.exception.status, 503)
            self.assertEqual(raised.exception.code, "data_stale")
            self.assertLessEqual(exchange.count("/api/v5/account/positions"), 6)
            self.assertEqual(exchange.count("/api/v5/account/positions"), 6)
        finally:
            service._display_executor.shutdown(wait=True)

    def test_forced_post_identity_follows_all_private_reads_and_deadline_starts_at_acquisition(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        gateway = make_gateway(exchange, clock)
        original_new_entry = gateway._new_entry
        acquisition_deadlines: list[float] = []

        def observe_acquisition(data, route):
            entry = original_new_entry(data, route)
            if route.upstream_path == "/api/v5/account/positions":
                if data and data[0]["instId"] == "BTC-USDT":
                    acquisition_deadlines.append(entry.deadline)
                    clock.advance(0.4)
            return entry

        gateway._new_entry = observe_acquisition
        identity, groups, deadline = gateway.read_display_positions(session_guard=lambda: None)

        self.assertEqual(identity.fingerprint, "fingerprint:account-1")
        self.assertEqual(set(groups), set(SUPPORTED_TYPES))
        self.assertEqual(exchange.identity_observations[0], frozenset())
        self.assertEqual(exchange.identity_observations[1], frozenset(SUPPORTED_TYPES))
        self.assertEqual(deadline, acquisition_deadlines[0])
        self.assertAlmostEqual(deadline, 101.0)

    def test_bundle_and_standalone_cache_entries_are_separate_deep_copied_and_fenced(self) -> None:
        clock = ControlledClock()
        exchange = PressureOKX()
        gateway = make_gateway(exchange, clock)

        _identity, bundle, _deadline = gateway.read_display_positions(session_guard=lambda: None)
        bundle["SWAP"][0]["pos"] = "900"
        _identity, cached_bundle, _deadline = gateway.read_display_positions(
            session_guard=lambda: None
        )
        self.assertEqual(cached_bundle["SWAP"][0]["pos"], "2")

        standalone, _deadline = gateway.read_internal_with_deadline(
            "account/positions", {"instType": "MARGIN"}, session_guard=lambda: None
        )
        standalone[0]["pos"] = "700"
        cached_standalone, _deadline = gateway.read_internal_with_deadline(
            "account/positions", {"instType": "MARGIN"}, session_guard=lambda: None
        )
        self.assertEqual(cached_standalone[0]["pos"], "1")
        self.assertEqual(exchange.count("/api/v5/account/positions"), 4)
        self.assertTrue(
            any(len(key) > 3 and key[3] == "$display/positions" for key in gateway._cache)
        )
        self.assertTrue(
            any(
                len(key) > 4
                and key[3] == "account/positions"
                and dict(key[4]).get("instType") == "MARGIN"
                for key in gateway._cache
            )
        )
        self.assertLessEqual(len(gateway._cache), gateway.MAX_CACHE_ENTRIES)
        self.assertEqual(gateway._inflight, {})

        gateway.invalidate_private()
        exchange.positions["SWAP"][0]["pos"] = "8"
        _identity, refreshed, _deadline = gateway.read_display_positions(
            session_guard=lambda: None
        )
        refreshed_standalone, _deadline = gateway.read_internal_with_deadline(
            "account/positions", {"instType": "MARGIN"}, session_guard=lambda: None
        )
        self.assertEqual(refreshed["SWAP"][0]["pos"], "8")
        self.assertEqual(refreshed_standalone[0]["pos"], "1")
        self.assertEqual(exchange.count("/api/v5/account/positions"), 8)


if __name__ == "__main__":
    unittest.main()
