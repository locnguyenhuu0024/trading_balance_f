from __future__ import annotations

from copy import deepcopy
import threading
import unittest
from concurrent.futures import Future, ThreadPoolExecutor
from unittest.mock import patch

from backend.app import WSGIApplication
from backend.currency import CurrencyClient, CurrencyClientError
from backend.data_gateway import DataGateway, GatewayError, GatewayIdentity
from backend.okx import OKXError
from backend.service import APIError, TradeService


class FakeOKX:
    def __init__(self):
        self.account = {
            "uid": "account-1",
            "posMode": "net_mode",
            "acctLv": "2",
            "mgnIsoMode": "automatic",
            "autoLoan": False,
            "secretMetadata": "must not escape",
        }
        self.positions = {
            "MARGIN": [{"instId": "BTC-USDT", "pos": "1", "posSide": "net"}],
            "SWAP": [{"instId": "BTC-USDT-SWAP", "pos": "2", "posSide": "net"}],
            "FUTURES": [{"instId": "BTC-USDT-260925", "pos": "3", "posSide": "net"}],
        }
        self.tickers = [
            {"instId": "BTC-USDT", "last": "100"},
            {"instId": "ETH-USDT", "last": "200"},
            {"instId": "BTC-USDT-SWAP", "last": "300"},
        ]
        self.balance = [{
            "totalEq": "100.00",
            "details": [
                {"ccy": "BTC", "cashBal": "0.25"},
                {"ccy": "USDT", "cashBal": "75.00"},
            ],
        }]
        self.calls: list[tuple[str, str, dict[str, str] | None]] = []
        self._lock = threading.Lock()
        self.failure_path: str | None = None
        self.failure_code: str | None = None
        self.switch_account_after_path: str | None = None
        self.blocked_types: dict[str, tuple[threading.Event, threading.Event]] = {}
        self.block_path: str | None = None
        self.block_entered: threading.Event | None = None
        self.block_release: threading.Event | None = None

    def account_config(self) -> dict:
        with self._lock:
            self.calls.append(("GET", "/api/v5/account/config", None))
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
        if path == self.failure_path:
            raise OKXError(
                "simulated safe failure",
                error_code=self.failure_code,
                http_status=429 if self.failure_code is None else None,
                retry_after="29",
            )
        if path == self.block_path and self.block_entered is not None:
            self.block_entered.set()
            if self.block_release is not None:
                self.block_release.wait(5)
        if path == "/api/v5/account/positions" and params:
            instrument_type = params["instType"]
            block = self.blocked_types.get(instrument_type)
            if block is not None:
                entered, release = block
                entered.set()
                release.wait(5)
            if self.switch_account_after_path == path:
                self.account["uid"] = "account-2"
                self.switch_account_after_path = None
            return {"code": "0", "msg": "", "data": deepcopy(self.positions[instrument_type])}
        if path == "/api/v5/account/balance":
            if self.switch_account_after_path == path:
                self.account["uid"] = "account-2"
                self.switch_account_after_path = None
            return {"code": "0", "msg": "", "data": deepcopy(self.balance)}
        if path == "/api/v5/market/tickers":
            return {"code": "0", "msg": "", "data": deepcopy(self.tickers)}
        if path == "/api/v5/market/ticker":
            instrument_id = (params or {}).get("instId", "BTC-USDT")
            return {"code": "0", "msg": "", "data": [{"instId": instrument_id, "last": "100"}]}
        if path == "/api/v5/public/instruments":
            instrument_type = (params or {}).get("instType", "SPOT")
            return {
                "code": "0", "msg": "", "data": [{"instId": f"BTC-USDT-{instrument_type}"}]
            }
        if path == "/api/v5/account/config":
            return {"code": "0", "msg": "", "data": [deepcopy(self.account)]}
        if path in {"/api/v5/trade/orders-pending", "/api/v5/trade/orders-history"}:
            return {"code": "0", "msg": "", "data": []}
        return {"code": "0", "msg": "", "data": []}

    def count(self, path: str) -> int:
        with self._lock:
            return sum(call[1] == path for call in self.calls)


class DataGatewayTests(unittest.TestCase):
    def setUp(self) -> None:
        self.exchange = FakeOKX()
        self.monotonic = 10.0
        self.wall = 1_800_000_000.0
        self.gateway = self.make_gateway()
        self.guard_count = 0

    def make_gateway(self, *, currency_transport=None) -> DataGateway:
        return DataGateway(
            self.exchange,
            account_fingerprint=lambda uid: None if uid is None else f"fingerprint:{uid}",
            currency_transport=currency_transport,
            monotonic_clock=lambda: self.monotonic,
            wall_clock=lambda: self.wall,
        )

    def guard(self) -> None:
        self.guard_count += 1

    def private(self, suffix: str, query: str = "") -> dict:
        return self.gateway.handle("GET", suffix, query, session_guard=self.guard)

    def test_invalid_query_and_unsupported_method_make_zero_upstream_calls(self) -> None:
        before = len(self.exchange.calls)
        invalid = (
            ("market/ticker", "instId=BTC-USDT&instId=ETH-USDT"),
            ("market/ticker", "instId=BTC-USDT&unexpected=x"),
            ("market/ticker", "instId=btc-usdt"),
            ("market/candles", "instId=BTC-USDT&limit=301"),
            ("public/open-interest", "instId=BTC-USDT&instType=SWAP"),
            ("market/quotes", "instIds=BTC-USDT-SWAP"),
        )
        for suffix, query in invalid:
            with self.subTest(suffix=suffix, query=query):
                with self.assertRaises(GatewayError) as raised:
                    self.gateway.handle("GET", suffix, query, session_guard=self.guard)
                self.assertEqual(raised.exception.status, 400)
        with self.assertRaises(GatewayError) as raised:
            self.gateway.handle("POST", "market/ticker", "instId=BTC-USDT", session_guard=self.guard)
        self.assertEqual(raised.exception.status, 405)
        with self.assertRaises(GatewayError) as raised:
            self.gateway.handle("GET", "unknown/path", "", session_guard=self.guard)
        self.assertEqual(raised.exception.status, 404)
        self.assertEqual(len(self.exchange.calls), before)

    def test_balance_keeps_all_currencies_cache_hits_and_returns_deep_copies(self) -> None:
        first = self.private("account/balance")
        self.assertEqual(first["data"][0]["details"][0]["ccy"], "BTC")
        self.assertEqual(first["data"][0]["details"][1]["ccy"], "USDT")
        self.assertEqual(first["dataMeta"]["source"], "backend")
        self.assertFalse(first["dataMeta"]["cacheHit"])
        self.assertEqual(self.exchange.calls[-1][2], None)
        self.assertEqual(first["msg"], "")

        first["data"][0]["details"][0]["cashBal"] = "tampered"
        second = self.private("account/balance")
        self.assertEqual(second["data"][0]["details"][0]["cashBal"], "0.25")
        self.assertTrue(second["dataMeta"]["cacheHit"])
        self.assertEqual(self.exchange.count("/api/v5/account/balance"), 1)
        self.assertGreaterEqual(self.guard_count, 4)

    def test_cache_evicts_oldest_entry_at_256(self) -> None:
        for index in range(257):
            self.gateway.handle(
                "GET",
                "public/instruments",
                f"instType=SPOT&instId=PAIR{index}-USDT",
            )

        self.assertEqual(len(self.gateway._cache), 256)
        self.assertEqual(self.exchange.count("/api/v5/public/instruments"), 257)
        self.gateway.handle(
            "GET", "public/instruments", "instType=SPOT&instId=PAIR0-USDT"
        )
        self.assertEqual(self.exchange.count("/api/v5/public/instruments"), 258)

    def test_inflight_admission_caps_distinct_keys_at_32_and_reads_at_four(self) -> None:
        class BlockingOKX(FakeOKX):
            def __init__(inner_self):
                super().__init__()
                inner_self.active_reads = 0
                inner_self.max_active_reads = 0
                inner_self.active_lock = threading.Lock()
                inner_self.four_reads_entered = threading.Event()
                inner_self.release_reads = threading.Event()

            def request(inner_self, method, path, *, params=None, private=None, **kwargs):
                if path == "/api/v5/market/ticker":
                    with inner_self.active_lock:
                        inner_self.active_reads += 1
                        inner_self.max_active_reads = max(
                            inner_self.max_active_reads, inner_self.active_reads
                        )
                        if inner_self.active_reads == 4:
                            inner_self.four_reads_entered.set()
                    if not inner_self.release_reads.wait(5):
                        raise TimeoutError("test read release timed out")
                    with inner_self.active_lock:
                        inner_self.active_reads -= 1
                return super(BlockingOKX, inner_self).request(
                    method, path, params=params, private=private, **kwargs
                )

        exchange = BlockingOKX()
        gateway = DataGateway(
            exchange,
            account_fingerprint=lambda uid: None if uid is None else str(uid),
            monotonic_clock=lambda: self.monotonic,
            wall_clock=lambda: self.wall,
        )
        added_32 = threading.Event()
        raw_lock = threading.RLock()

        class ObservedCacheLock:
            def __enter__(inner_self):
                raw_lock.acquire()
                return inner_self

            def __exit__(inner_self, exc_type, exc, traceback):
                raw_lock.release()
                if len(gateway._inflight) == 32:
                    added_32.set()

        gateway._cache_lock = ObservedCacheLock()
        results: list[dict] = []
        failures: list[BaseException] = []

        def read(index: int) -> None:
            try:
                results.append(
                    gateway.handle("GET", "market/ticker", f"instId=PAIR{index}-USDT")
                )
            except BaseException as error:
                failures.append(error)

        workers = ThreadPoolExecutor(max_workers=32)
        futures = [workers.submit(read, index) for index in range(32)]
        self.assertTrue(added_32.wait(3))
        self.assertTrue(exchange.four_reads_entered.wait(3))
        try:
            with self.assertRaises(GatewayError) as raised:
                gateway.handle("GET", "market/ticker", "instId=PAIR32-USDT")
            self.assertEqual(raised.exception.status, 503)
        finally:
            exchange.release_reads.set()
        for future in futures:
            future.result(timeout=5)
        workers.shutdown(wait=True)

        self.assertEqual(failures, [])
        self.assertEqual(len(results), 32)
        self.assertEqual(exchange.max_active_reads, 4)

    def test_shared_failure_releases_waiter_and_is_not_cached(self) -> None:
        class BlockingFailureOKX(FakeOKX):
            def request(inner_self, method, path, *, params=None, private=None, **kwargs):
                if path == "/api/v5/market/ticker":
                    inner_self.block_entered.set()
                    if not inner_self.block_release.wait(5):
                        raise TimeoutError("test failure release timed out")
                return super(BlockingFailureOKX, inner_self).request(
                    method, path, params=params, private=private, **kwargs
                )

        exchange = BlockingFailureOKX()
        exchange.block_entered = threading.Event()
        exchange.block_release = threading.Event()
        exchange.failure_path = "/api/v5/market/ticker"
        gateway = DataGateway(
            exchange,
            account_fingerprint=lambda uid: None if uid is None else str(uid),
            monotonic_clock=lambda: self.monotonic,
        )
        follower_waiting = threading.Event()
        original_wait = gateway._wait_for_flight

        def observed_wait(flight, identity, private):
            follower_waiting.set()
            return original_wait(flight, identity, private)

        gateway._wait_for_flight = observed_wait
        failures: list[BaseException] = []

        def read() -> None:
            try:
                gateway.handle("GET", "market/ticker", "instId=BTC-USDT")
            except BaseException as error:
                failures.append(error)

        leader = threading.Thread(target=read)
        follower = threading.Thread(target=read)
        leader.start()
        self.assertTrue(exchange.block_entered.wait(2))
        follower.start()
        try:
            self.assertTrue(follower_waiting.wait(2))
        finally:
            exchange.block_release.set()
        leader.join(5)
        follower.join(5)

        self.assertEqual(len(failures), 2)
        self.assertTrue(all(isinstance(error, GatewayError) for error in failures))
        self.assertEqual(exchange.count("/api/v5/market/ticker"), 1)
        with self.assertRaises(GatewayError):
            gateway.handle("GET", "market/ticker", "instId=BTC-USDT")
        self.assertEqual(exchange.count("/api/v5/market/ticker"), 2)

    def test_account_config_projects_only_approved_fields(self) -> None:
        response = self.private("account/config")
        self.assertEqual(
            set(response["data"][0]),
            {"uid", "mgnIsoMode", "acctLv", "posMode", "autoLoan"},
        )
        self.assertNotIn("secretMetadata", response["data"][0])

    def test_quotes_share_spot_ticker_cache_and_match_full_ids(self) -> None:
        first = self.gateway.handle(
            "GET", "market/quotes", "instIds=BTC-USDT,ETH-USDT,BTC-USDT"
        )
        self.assertEqual([row["instId"] for row in first["data"]], ["BTC-USDT", "ETH-USDT"])
        second = self.gateway.handle("GET", "market/quotes", "instIds=BTC-USDT")
        self.assertEqual([row["instId"] for row in second["data"]], ["BTC-USDT"])
        self.assertTrue(second["dataMeta"]["cacheHit"])
        self.assertEqual(self.exchange.count("/api/v5/market/tickers"), 1)

    def test_single_flight_shares_one_upstream_read(self) -> None:
        entered = threading.Event()
        release = threading.Event()
        self.exchange.block_path = "/api/v5/market/ticker"
        self.exchange.block_entered = entered
        self.exchange.block_release = release
        waiting = threading.Event()
        original_wait = self.gateway._wait_for_flight

        def observed_wait(flight, identity, private):
            waiting.set()
            return original_wait(flight, identity, private)

        self.gateway._wait_for_flight = observed_wait
        results: list[dict] = []
        failures: list[BaseException] = []

        def call() -> None:
            try:
                results.append(self.gateway.handle("GET", "market/ticker", "instId=BTC-USDT"))
            except BaseException as error:
                failures.append(error)

        leader = threading.Thread(target=call)
        follower = threading.Thread(target=call)
        leader.start()
        self.assertTrue(entered.wait(2))
        follower.start()
        try:
            self.assertTrue(waiting.wait(2))
        finally:
            release.set()
        leader.join(5)
        follower.join(5)

        self.assertFalse(leader.is_alive())
        self.assertFalse(follower.is_alive())
        self.assertEqual(failures, [])
        self.assertEqual(len(results), 2)
        self.assertEqual(self.exchange.count("/api/v5/market/ticker"), 1)

    def test_private_invalidation_refreshes_cached_data_after_execute(self) -> None:
        stale_balance = deepcopy(self.exchange.balance)
        entered = threading.Event()
        release = threading.Event()

        class DelayedBalanceOKX(FakeOKX):
            def request(inner_self, method, path, *, params=None, private=None, **kwargs):
                if path == "/api/v5/account/balance" and inner_self.delayed_balance_pending:
                    inner_self.delayed_balance_pending = False
                    with inner_self._lock:
                        inner_self.calls.append((method, path, deepcopy(params)))
                    entered.set()
                    if not release.wait(5):
                        raise TimeoutError("test release timed out")
                    return {"code": "0", "msg": "", "data": deepcopy(stale_balance)}
                return super(DelayedBalanceOKX, inner_self).request(
                    method, path, params=params, private=private, **kwargs
                )

        exchange = DelayedBalanceOKX()
        exchange.delayed_balance_pending = True
        gateway = DataGateway(
            exchange,
            account_fingerprint=lambda uid: None if uid is None else f"fingerprint:{uid}",
            monotonic_clock=lambda: self.monotonic,
            wall_clock=lambda: self.wall,
        )
        results: list[dict] = []
        failures: list[BaseException] = []

        def read_before_action() -> None:
            try:
                results.append(gateway.handle("GET", "account/balance", "", session_guard=self.guard))
            except BaseException as error:
                failures.append(error)

        reader = threading.Thread(target=read_before_action)
        reader.start()
        self.assertTrue(entered.wait(2))

        service = TradeService.__new__(TradeService)
        service.data_gateway = gateway
        service._source_address = lambda environ: "127.0.0.1"
        service._source_key = lambda source: "test-source"
        service._require_session = lambda environ: None
        service._check_action_rate = lambda action, source: None

        def execute(_body):
            exchange.balance[0]["totalEq"] = "200.00"
            return {"status": "SUCCEEDED"}

        service._execute = execute
        status, body, _headers = service.dispatch("POST", "/v1/actions/execute", {}, {})
        self.assertEqual((status, body["status"]), (200, "SUCCEEDED"))
        release.set()
        reader.join(5)

        self.assertFalse(reader.is_alive())
        self.assertEqual(results, [])
        self.assertEqual(len(failures), 1)
        self.assertIsInstance(failures[0], GatewayError)
        fresh = gateway.handle("GET", "account/balance", "", session_guard=self.guard)
        self.assertEqual(fresh["data"][0]["totalEq"], "200.00")
        self.assertFalse(fresh["dataMeta"]["cacheHit"])
        self.assertEqual(exchange.count("/api/v5/account/balance"), 2)

    def test_strategy_post_invalidates_private_display_cache(self) -> None:
        first = self.private("account/balance")
        self.assertEqual(first["data"][0]["totalEq"], "100.00")
        service = TradeService.__new__(TradeService)
        service.data_gateway = self.gateway
        service._source_address = lambda environ: "127.0.0.1"
        service._source_key = lambda source: "test-source"
        service._require_session = lambda environ: None
        service._check_action_rate = lambda action, source: None

        class StrategyMutation:
            def dispatch(_self, method, path, body, *, request_guard):
                request_guard()
                self.exchange.balance[0]["totalEq"] = "300.00"
                return {"status": "APPLIED"}

        service.strategy = StrategyMutation()
        status, body, _headers = service.dispatch(
            "POST", "/v1/strategies/strategy-123/execute-apply", {}, {}
        )

        self.assertEqual((status, body["status"]), (200, "APPLIED"))
        fresh = self.private("account/balance")
        self.assertEqual(fresh["data"][0]["totalEq"], "300.00")
        self.assertFalse(fresh["dataMeta"]["cacheHit"])

    def test_private_account_switch_during_fetch_discards_data_and_does_not_cache(self) -> None:
        self.exchange.switch_account_after_path = "/api/v5/account/balance"
        with self.assertRaises(GatewayError) as raised:
            self.private("account/balance")
        self.assertEqual(raised.exception.status, 409)
        self.assertEqual(raised.exception.code, "account_changed")
        self.assertEqual(len(self.gateway._cache), 0)

        response = self.private("account/balance")
        self.assertEqual(response["data"][0]["totalEq"], "100.00")
        self.assertFalse(response["dataMeta"]["cacheHit"])
        self.assertEqual(self.exchange.count("/api/v5/account/balance"), 2)

    def test_identity_observation_expires_and_invalidates_cached_private_data(self) -> None:
        self.private("account/balance")
        self.exchange.account["uid"] = "account-2"
        self.monotonic += 1.01

        response = self.private("account/balance")

        self.assertFalse(response["dataMeta"]["cacheHit"])
        self.assertEqual(self.exchange.count("/api/v5/account/balance"), 2)

    def test_private_read_expiring_before_publication_returns_data_stale(self) -> None:
        original_new_entry = self.gateway._new_entry
        advanced = False

        def expire_first_entry(data, route):
            nonlocal advanced
            entry = original_new_entry(data, route)
            if route.private and not advanced:
                advanced = True
                self.monotonic += 1.1
            return entry

        self.gateway._new_entry = expire_first_entry

        with self.assertRaises(GatewayError) as raised:
            self.private("account/balance")

        self.assertEqual(raised.exception.status, 503)
        self.assertEqual(raised.exception.code, "data_stale")
        self.assertEqual(self.exchange.count("/api/v5/account/balance"), 1)
        self.assertEqual(len(self.gateway._cache), 0)

    def test_private_ttl_starts_at_acquisition_before_identity_verification(self) -> None:
        class SlowIdentityOKX(FakeOKX):
            def __init__(inner_self, slow_config_calls):
                super().__init__()
                inner_self.config_reads = 0
                inner_self.slow_config_calls = dict(slow_config_calls)

            def account_config(inner_self):
                result = super(SlowIdentityOKX, inner_self).account_config()
                inner_self.config_reads += 1
                delay = inner_self.slow_config_calls.get(inner_self.config_reads, 0.0)
                self.monotonic += delay
                self.wall += delay
                return result

        exchange = SlowIdentityOKX({2: 0.4})
        gateway = DataGateway(
            exchange,
            account_fingerprint=lambda uid: None if uid is None else f"fingerprint:{uid}",
            monotonic_clock=lambda: self.monotonic,
            wall_clock=lambda: self.wall,
        )

        fetched_at = gateway._iso_time(self.wall)
        response = gateway.handle("GET", "account/balance", "", session_guard=self.guard)

        self.assertEqual(exchange.count("/api/v5/account/balance"), 1)
        self.assertEqual(response["dataMeta"]["fetchedAt"], fetched_at)
        self.assertEqual(self.wall, 1_800_000_000.4)
        self.assertEqual(response["data"][0]["totalEq"], "100.00")

    def test_combined_identity_delays_bound_private_refresh_to_one(self) -> None:
        class SlowSecondIdentityOKX(FakeOKX):
            def __init__(inner_self):
                super().__init__()
                inner_self.config_reads = 0

            def account_config(inner_self):
                result = super(SlowSecondIdentityOKX, inner_self).account_config()
                inner_self.config_reads += 1
                if inner_self.config_reads == 3:
                    self.monotonic += 1.1
                    self.wall += 1.1
                return result

        exchange = SlowSecondIdentityOKX()
        gateway = DataGateway(
            exchange,
            account_fingerprint=lambda uid: None if uid is None else f"fingerprint:{uid}",
            monotonic_clock=lambda: self.monotonic,
            wall_clock=lambda: self.wall,
        )
        original_current_identity = gateway._current_identity_for
        first_final_check = True

        def delay_after_first_final_check(expected):
            nonlocal first_final_check
            current = original_current_identity(expected)
            if first_final_check:
                first_final_check = False
                self.monotonic += 1.1
                self.wall += 1.1
            return current

        gateway._current_identity_for = delay_after_first_final_check

        with self.assertRaises(GatewayError) as raised:
            gateway.handle("GET", "account/balance", "", session_guard=self.guard)

        self.assertEqual(raised.exception.status, 503)
        self.assertEqual(raised.exception.code, "data_stale")
        self.assertEqual(exchange.count("/api/v5/account/balance"), 2)
        self.assertEqual(exchange.config_reads, 3)
        self.assertEqual(len(gateway._cache), 0)

    def test_repeated_slow_identity_fencing_returns_data_stale_without_cache(self) -> None:
        class SlowIdentityOKX(FakeOKX):
            def __init__(inner_self):
                super().__init__()
                inner_self.config_reads = 0

            def account_config(inner_self):
                result = super(SlowIdentityOKX, inner_self).account_config()
                inner_self.config_reads += 1
                if inner_self.config_reads in {2, 3}:
                    self.monotonic += 1.1
                    self.wall += 1.1
                return result

        exchange = SlowIdentityOKX()
        gateway = DataGateway(
            exchange,
            account_fingerprint=lambda uid: None if uid is None else f"fingerprint:{uid}",
            monotonic_clock=lambda: self.monotonic,
            wall_clock=lambda: self.wall,
        )

        with self.assertRaises(GatewayError) as raised:
            gateway.handle("GET", "account/balance", "", session_guard=self.guard)

        self.assertEqual(raised.exception.status, 503)
        self.assertEqual(raised.exception.code, "data_stale")
        self.assertEqual(exchange.count("/api/v5/account/balance"), 1)
        self.assertEqual(len(gateway._cache), 0)

    def test_all_positions_parallelize_and_keep_registry_order(self) -> None:
        gates = {
            instrument_type: (threading.Event(), threading.Event())
            for instrument_type in ("MARGIN", "SWAP", "FUTURES")
        }
        self.exchange.blocked_types = gates
        result: list[dict] = []
        failure: list[BaseException] = []

        def call() -> None:
            try:
                result.append(self.private("account/positions", "instType=ALL"))
            except BaseException as error:
                failure.append(error)

        worker = threading.Thread(target=call, name="all-positions-test")
        worker.start()
        try:
            self.assertTrue(all(entered.wait(2) for entered, _ in gates.values()))
        finally:
            for instrument_type in ("FUTURES", "SWAP", "MARGIN"):
                gates[instrument_type][1].set()
        worker.join(5)

        self.assertFalse(worker.is_alive())
        self.assertEqual(failure, [])
        self.assertEqual(
            [row["instId"] for row in result[0]["data"]],
            ["BTC-USDT", "BTC-USDT-SWAP", "BTC-USDT-260925"],
        )

    def test_all_positions_refreshes_parts_expired_while_sibling_is_slow(self) -> None:
        margin_cached = threading.Event()
        cached_siblings = threading.Event()
        cached_types: set[str] = set()
        cached_lock = threading.Lock()
        swap_entered = threading.Event()
        release_swap = threading.Event()

        class DelayedSiblingOKX(FakeOKX):
            def __init__(inner_self):
                super().__init__()
                inner_self.delay_first_swap = True

            def request(inner_self, method, path, *, params=None, private=None, **kwargs):
                if (
                    path == "/api/v5/account/positions"
                    and params is not None
                    and params.get("instType") == "SWAP"
                    and inner_self.delay_first_swap
                ):
                    inner_self.delay_first_swap = False
                    if not margin_cached.wait(3):
                        raise TimeoutError("MARGIN fixture was not cached")
                    swap_entered.set()
                    if not release_swap.wait(5):
                        raise TimeoutError("SWAP fixture was not released")
                return super(DelayedSiblingOKX, inner_self).request(
                    method, path, params=params, private=private, **kwargs
                )

        exchange = DelayedSiblingOKX()
        gateway = DataGateway(
            exchange,
            account_fingerprint=lambda uid: None if uid is None else f"fingerprint:{uid}",
            monotonic_clock=lambda: self.monotonic,
            wall_clock=lambda: self.wall,
        )
        store_entry = gateway._store_entry

        def observe_margin_cache(key, entry, identity):
            store_entry(key, entry, identity)
            if key[3] == "account/positions":
                instrument_type = dict(key[4])["instType"]
                if instrument_type == "MARGIN":
                    margin_cached.set()
                with cached_lock:
                    cached_types.add(instrument_type)
                    if {"MARGIN", "FUTURES"}.issubset(cached_types):
                        cached_siblings.set()

        gateway._store_entry = observe_margin_cache
        results: list[dict] = []
        failures: list[BaseException] = []

        def call() -> None:
            try:
                results.append(gateway.handle("GET", "account/positions", "instType=ALL", session_guard=self.guard))
            except BaseException as error:
                failures.append(error)

        worker = threading.Thread(target=call, name="stale-aggregate-test")
        worker.start()
        self.assertTrue(swap_entered.wait(2))
        self.assertTrue(cached_siblings.wait(2))
        self.monotonic += 1.1
        release_swap.set()
        worker.join(5)

        self.assertFalse(worker.is_alive())
        self.assertEqual(failures, [])
        self.assertEqual(len(results), 1)
        self.assertEqual(exchange.count("/api/v5/account/positions"), 5)
        self.assertEqual(
            [row["instId"] for row in results[0]["data"]],
            ["BTC-USDT", "BTC-USDT-SWAP", "BTC-USDT-260925"],
        )

    def test_failed_all_aggregate_never_returns_partial_data(self) -> None:
        self.exchange.failure_path = "/api/v5/account/positions"
        self.exchange.failure_code = "50011"
        with self.assertRaises(GatewayError) as raised:
            self.private("account/positions", "instType=ALL")
        self.assertEqual(raised.exception.status, 429)
        self.assertEqual(raised.exception.headers, [("Retry-After", "29")])

    def test_all_positions_fanout_preserves_revoked_session_as_401(self) -> None:
        gates = {
            instrument_type: (threading.Event(), threading.Event())
            for instrument_type in ("MARGIN", "SWAP", "FUTURES")
        }
        self.exchange.blocked_types = gates
        revoked = threading.Event()
        result: list[dict] = []
        failures: list[BaseException] = []

        class ExpiredSession(Exception):
            status = 401
            code = "authentication_required"

        def guard() -> None:
            if revoked.is_set():
                raise ExpiredSession()

        def call() -> None:
            try:
                result.append(
                    self.gateway.handle(
                        "GET", "account/positions", "instType=ALL", session_guard=guard
                    )
                )
            except BaseException as error:
                failures.append(error)

        worker = threading.Thread(target=call, name="revoked-all-test")
        worker.start()
        try:
            self.assertTrue(all(entered.wait(2) for entered, _ in gates.values()))
            revoked.set()
        finally:
            for _, release in gates.values():
                release.set()
        worker.join(5)

        self.assertFalse(worker.is_alive())
        self.assertEqual(result, [])
        self.assertEqual(len(failures), 1)
        self.assertIsInstance(failures[0], GatewayError)
        self.assertEqual(failures[0].status, 401)

    def test_identity_rate_limit_preserves_status_and_retry_after(self) -> None:
        class LimitedIdentityOKX(FakeOKX):
            def account_config(inner_self):
                raise OKXError(
                    "safe limit",
                    error_code="50011",
                    http_status=429,
                    retry_after="29",
                )

        gateway = DataGateway(
            LimitedIdentityOKX(),
            account_fingerprint=lambda uid: None if uid is None else str(uid),
            monotonic_clock=lambda: self.monotonic,
        )
        with self.assertRaises(GatewayError) as raised:
            gateway.handle("GET", "account/balance", "", session_guard=self.guard)

        self.assertEqual(raised.exception.status, 429)
        self.assertEqual(raised.exception.headers, [("Retry-After", "29")])

    def test_ttl_expiry_refreshes_public_read_and_empty_data_stays_empty(self) -> None:
        first = self.gateway.handle("GET", "trade/orders-history", "instType=SWAP", session_guard=self.guard)
        self.assertEqual(first["data"], [])
        second = self.gateway.handle("GET", "trade/orders-history", "instType=SWAP", session_guard=self.guard)
        self.assertTrue(second["dataMeta"]["cacheHit"])
        self.monotonic += 1.01
        third = self.gateway.handle("GET", "trade/orders-history", "instType=SWAP", session_guard=self.guard)
        self.assertFalse(third["dataMeta"]["cacheHit"])
        self.assertEqual(self.exchange.count("/api/v5/trade/orders-history"), 2)

    def test_currency_route_is_public_cached_and_uses_injected_fixed_request(self) -> None:
        calls: list[tuple[str, str, dict[str, str]]] = []

        def transport(method: str, path: str, headers: dict[str, str]) -> dict:
            calls.append((method, path, dict(headers)))
            return {"tether": {"vnd": 25_000.0}}

        gateway = self.make_gateway(currency_transport=transport)
        first = gateway.handle("GET", "currency/usdt-vnd", "")
        second = gateway.handle("GET", "currency/usdt-vnd", "")

        self.assertEqual(first["data"], [{"instId": "USDT-VND", "rate": "25000", "source": "CoinGecko"}])
        self.assertTrue(second["dataMeta"]["cacheHit"])
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0], "GET")
        self.assertEqual(calls[0][1], CurrencyClient.REQUEST_PATH)
        self.assertNotIn("Authorization", calls[0][2])
        self.assertFalse(any(key.startswith("OK-") for key in calls[0][2]))
        self.assertEqual(self.exchange.calls, [])

    def test_currency_route_rejects_invalid_upstream_numbers(self) -> None:
        for value in (True, 0, -1, float("inf"), float("nan"), "25000"):
            with self.subTest(value=value):
                gateway = self.make_gateway(
                    currency_transport=lambda method, path, headers, rate=value: {"tether": {"vnd": rate}}
                )
                with self.assertRaises(GatewayError) as raised:
                    gateway.handle("GET", "currency/usdt-vnd", "")
                self.assertEqual(raised.exception.status, 502)
                self.assertEqual(raised.exception.code, "currency_unavailable")

    def test_currency_client_uses_only_fixed_host_and_does_not_follow_redirects(self) -> None:
        requests: list[tuple[str, str, dict[str, str]]] = []

        class Response:
            status = 302
            will_close = True

            def read(self, size: int) -> bytes:
                return b"{}"

        class Connection:
            def __init__(self, host: str, *, timeout: int):
                self.host = host

            def request(self, method: str, path: str, *, headers: dict[str, str]) -> None:
                requests.append((self.host, method, path, dict(headers)))

            def getresponse(self) -> Response:
                return Response()

            def close(self) -> None:
                return None

        with patch("backend.currency.http.client.HTTPSConnection", Connection):
            with self.assertRaises(CurrencyClientError):
                CurrencyClient().usdt_vnd_rate()

        self.assertEqual(len(requests), 1)
        self.assertEqual(requests[0][0], "api.coingecko.com")
        self.assertEqual(requests[0][1:3], ("GET", CurrencyClient.REQUEST_PATH))
        self.assertNotIn("Authorization", requests[0][3])
        self.assertFalse(any(key.startswith("OK-") for key in requests[0][3]))


class ApplicationInitializationTests(unittest.TestCase):
    def test_concurrent_first_calls_construct_one_service(self) -> None:
        app = WSGIApplication(settings=object())
        service = object()
        calls = 0
        entered = threading.Event()
        release = threading.Event()
        calls_lock = threading.Lock()

        def factory(settings, **kwargs):
            nonlocal calls
            with calls_lock:
                calls += 1
            entered.set()
            release.wait(3)
            return service

        barrier = threading.Barrier(9)
        results: list[object] = []
        failures: list[BaseException] = []

        def get_service() -> None:
            try:
                barrier.wait()
                results.append(app._get_service())
            except BaseException as error:
                failures.append(error)

        with patch("backend.app.TradeService", side_effect=factory):
            workers = [threading.Thread(target=get_service) for _ in range(8)]
            for worker in workers:
                worker.start()
            barrier.wait()
            self.assertTrue(entered.wait(2))
            release.set()
            for worker in workers:
                worker.join(3)

        self.assertEqual(failures, [])
        self.assertEqual(calls, 1)
        self.assertEqual(len(results), 8)
        self.assertTrue(all(result is service for result in results))

    def make_display_service(self, *, always_stale: bool = False):
        class DisplayGateway:
            def __init__(self):
                self.now = 0.0
                self.reads = 0
                self.forced_identity_reads = 0

            def identity_for_display(self, *, session_guard, force=False):
                session_guard()
                if force:
                    self.forced_identity_reads += 1
                    if always_stale or self.forced_identity_reads == 1:
                        self.now += 2.0
                return GatewayIdentity(
                    account={"uid": "display-account", "posMode": "net_mode"},
                    fingerprint="display-fingerprint",
                    generation=0,
                )

            def read_internal_with_deadline(self, suffix, params, *, session_guard=None):
                if session_guard is not None:
                    session_guard()
                self.reads += 1
                if suffix == "account/positions":
                    data = []
                else:
                    data = [{"instId": f"BTC-USDT-{params['instType']}"}]
                return data, self.now + 1.0

            def is_deadline_fresh(self, deadline):
                return deadline > self.now

        service = TradeService.__new__(TradeService)
        service.data_gateway = DisplayGateway()
        service._require_session = lambda environ: "session"
        service._display_executor = ThreadPoolExecutor(max_workers=3)
        service._display_admission = threading.BoundedSemaphore(6)
        return service

    def test_display_snapshot_retries_expired_child_once(self) -> None:
        service = self.make_display_service()
        try:
            snapshot = service._fetch_display_snapshot({})
        finally:
            service._display_executor.shutdown(wait=True)

        self.assertEqual(snapshot["accountFingerprint"], "display-fingerprint")
        self.assertEqual(service.data_gateway.reads, 12)

    def test_display_snapshot_fails_stale_after_one_refresh(self) -> None:
        service = self.make_display_service(always_stale=True)
        try:
            with self.assertRaises(APIError) as raised:
                service._fetch_display_snapshot({})
        finally:
            service._display_executor.shutdown(wait=True)

        self.assertEqual(raised.exception.status, 503)
        self.assertEqual(raised.exception.code, "data_stale")
        self.assertEqual(service.data_gateway.reads, 12)

    def test_display_snapshot_admission_is_bounded(self) -> None:
        service = self.make_display_service()
        for _ in range(6):
            self.assertTrue(service._display_admission.acquire(blocking=False))
        try:
            with self.assertRaises(APIError) as raised:
                service._fetch_display_snapshot({})
        finally:
            for _ in range(6):
                service._display_admission.release()
            service._display_executor.shutdown(wait=True)

        self.assertEqual(raised.exception.status, 503)
        self.assertEqual(service.data_gateway.reads, 0)

    def test_display_admission_releases_after_group_error(self) -> None:
        service = self.make_display_service()
        original_read = service.data_gateway.read_internal_with_deadline
        siblings_ready = threading.Event()
        release_siblings = threading.Event()
        siblings_completed = threading.Event()
        sibling_types: set[str] = set()
        sibling_lock = threading.Lock()
        should_fail = True

        def controlled_read(suffix, params, *, session_guard=None):
            nonlocal should_fail
            instrument_type = params["instType"]
            if suffix == "account/positions" and instrument_type == "MARGIN" and should_fail:
                self.assertTrue(siblings_ready.wait(3))
                should_fail = False
                raise GatewayError(502, "exchange_unavailable", "safe failure")
            if suffix == "account/positions" and instrument_type in {"SWAP", "FUTURES"}:
                with sibling_lock:
                    sibling_types.add(instrument_type)
                    if sibling_types == {"SWAP", "FUTURES"}:
                        siblings_ready.set()
                self.assertTrue(release_siblings.wait(3))
                data, deadline = original_read(suffix, params, session_guard=session_guard)
                with sibling_lock:
                    sibling_types.discard(instrument_type)
                    if not sibling_types:
                        siblings_completed.set()
                return data, deadline
            return original_read(suffix, params, session_guard=session_guard)

        service.data_gateway.read_internal_with_deadline = controlled_read
        outcome: list[BaseException] = []

        def request() -> None:
            try:
                service._fetch_display_snapshot({})
            except BaseException as error:
                outcome.append(error)

        worker = threading.Thread(target=request)
        worker.start()
        worker.join(3)
        self.assertFalse(worker.is_alive())
        self.assertEqual(len(outcome), 1)
        self.assertIsInstance(outcome[0], APIError)
        self.assertLess(service._display_admission._value, 6)

        release_siblings.set()
        self.assertTrue(siblings_completed.wait(3))
        self.assertEqual(service._display_admission._value, 6)
        snapshot = service._fetch_display_snapshot({})
        self.assertEqual(snapshot["accountFingerprint"], "display-fingerprint")
        service._display_executor.shutdown(wait=True)

    def test_display_admission_releases_unsubmitted_slots_after_submit_error(self) -> None:
        service = self.make_display_service()
        executor = service._display_executor
        service._display_executor = object()

        class FailingExecutor:
            submissions = 0

            def submit(inner_self, function, *args):
                inner_self.submissions += 1
                if inner_self.submissions == 2:
                    raise RuntimeError("simulated submit failure")
                future = Future()
                future.set_result(None)
                return future

        service._display_executor = FailingExecutor()
        try:
            with self.assertRaises(APIError) as raised:
                service._fetch_display_snapshot({})
            self.assertEqual(raised.exception.status, 502)
            self.assertEqual(service._display_admission._value, 6)
        finally:
            service._display_executor = executor

        snapshot = service._fetch_display_snapshot({})
        self.assertEqual(snapshot["accountFingerprint"], "display-fingerprint")
        executor.shutdown(wait=True)

    def test_display_admission_releases_after_future_timeout_completes(self) -> None:
        service = self.make_display_service()
        executor = service._display_executor

        class TimeoutFuture(Future):
            def result(self, timeout=None):
                raise TimeoutError("simulated display future timeout")

        class TimeoutExecutor:
            def __init__(inner_self):
                inner_self.futures: list[TimeoutFuture] = []

            def submit(inner_self, function, *args):
                future = TimeoutFuture()
                future.set_running_or_notify_cancel()
                inner_self.futures.append(future)
                return future

        timeout_executor = TimeoutExecutor()
        service._display_executor = timeout_executor
        try:
            with self.assertRaises(APIError) as raised:
                service._fetch_display_snapshot({})
            self.assertEqual(raised.exception.status, 503)
            self.assertEqual(service._display_admission._value, 3)
            for future in timeout_executor.futures:
                future.set_result(([], {}, 1.0))
            self.assertEqual(service._display_admission._value, 6)
        finally:
            service._display_executor = executor

        snapshot = service._fetch_display_snapshot({})
        self.assertEqual(snapshot["accountFingerprint"], "display-fingerprint")
        executor.shutdown(wait=True)


if __name__ == "__main__":
    unittest.main()
