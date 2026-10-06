from __future__ import annotations

import io
import json
import os
import sqlite3
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

from backend.app import create_application
from backend.security import token_digest
from backend.service import RuntimeSettings, TradeService
from backend.store import SQLiteStore


NOW = 1_798_848_000.0
SIGNING_KEY = bytes(range(32))
TOKEN = "strategy-settings-test-session"
ORIGIN = "https://strategy.example.test"
DEFAULT_THRESHOLDS = {
    "minStructuralQuality": 4,
    "minEntrySuitabilityProbability": 0.6,
    "maxFailureRiskProbability": 0.4,
}


class SettingsExchange:
    def __init__(self) -> None:
        self.account_uid = "settings-account-a"

    def transport(self, method: str, path: str, _headers: dict[str, str], _body: bytes | None) -> dict[str, Any]:
        if method == "GET" and path == "/api/v5/account/config":
            return {"code": "0", "data": [{"uid": self.account_uid, "posMode": "net_mode"}]}
        raise AssertionError(f"Unexpected fake exchange request: {method} {path}")


class StrategySettingsApiTests(unittest.TestCase):
    def setUp(self) -> None:
        self.db_path = Path(__file__).resolve().parents[2] / (
            f".strategy-settings-test-{os.getpid()}-{id(self)}.sqlite3"
        )
        self.exchange = SettingsExchange()
        self.now = NOW
        settings = RuntimeSettings(
            okx_api_key="test-key",
            okx_api_secret="test-secret",
            okx_api_passphrase="test-passphrase",
            admin_password_hash="unused-in-this-session-fixture",
            totp_secret="unused-in-this-session-fixture",
            session_signing_key=SIGNING_KEY,
            allowed_web_origin=ORIGIN,
            operation_db_path=str(self.db_path),
        )
        self.service = TradeService(settings, transport=self.exchange.transport, clock=lambda: self.now)
        self.app = create_application(service=self.service)
        with self.service.store.transaction() as connection:
            connection.execute(
                "INSERT INTO sessions(token_hash, expires_at, created_at) VALUES (?, ?, ?)",
                (token_digest(TOKEN, SIGNING_KEY), self.now + 3600, self.now),
            )

    def tearDown(self) -> None:
        self.db_path.unlink(missing_ok=True)

    def request(self, method: str, path: str, body: dict[str, Any] | None = None) -> tuple[int, dict[str, Any]]:
        raw = b"" if body is None else json.dumps(body, allow_nan=True).encode("utf-8")
        environ: dict[str, Any] = {
            "REQUEST_METHOD": method,
            "PATH_INFO": path,
            "REMOTE_ADDR": "127.0.0.1",
            "HTTP_ORIGIN": ORIGIN,
            "CONTENT_TYPE": "application/json",
            "CONTENT_LENGTH": str(len(raw)),
            "wsgi.input": io.BytesIO(raw),
            "HTTP_AUTHORIZATION": f"Bearer {TOKEN}",
        }
        response: dict[str, Any] = {}

        def start_response(status: str, _headers: list[tuple[str, str]]) -> None:
            response["status"] = int(status.split(" ", 1)[0])

        payload = b"".join(self.app(environ, start_response))
        return response["status"], {} if not payload else json.loads(payload.decode("utf-8"))

    def get_settings(self) -> dict[str, Any]:
        status, result = self.request("GET", "/v1/strategies/settings")
        self.assertEqual(status, 200, result)
        return result

    def test_default_custom_boundary_roundtrip_and_partial_group_writes(self) -> None:
        self.assertEqual(self.get_settings(), {
            "limitOrderSubmissionMode": "sequential",
            "jevScreeningThresholds": DEFAULT_THRESHOLDS,
        })

        custom = {
            "minStructuralQuality": 0,
            "minEntrySuitabilityProbability": 0.0,
            "maxFailureRiskProbability": 1.0,
        }
        status, saved = self.request("POST", "/v1/strategies/settings", {
            "jevScreeningThresholds": custom,
        })
        self.assertEqual(status, 200, saved)
        self.assertEqual(saved, {
            "limitOrderSubmissionMode": "sequential",
            "jevScreeningThresholds": custom,
        })

        status, saved = self.request("POST", "/v1/strategies/settings", {
            "limitOrderSubmissionMode": "batch",
        })
        self.assertEqual(status, 200, saved)
        self.assertEqual(saved, {
            "limitOrderSubmissionMode": "batch",
            "jevScreeningThresholds": custom,
        })

        combined = {
            "limitOrderSubmissionMode": "sequential",
            "jevScreeningThresholds": {
                "minStructuralQuality": 5,
                "minEntrySuitabilityProbability": 1.0,
                "maxFailureRiskProbability": 0.0,
            },
        }
        status, saved = self.request("POST", "/v1/strategies/settings", combined)
        self.assertEqual(status, 200, saved)
        self.assertEqual(saved, combined)

    def test_settings_are_isolated_by_authenticated_account_fingerprint(self) -> None:
        account_a = {
            "minStructuralQuality": 2,
            "minEntrySuitabilityProbability": 0.35,
            "maxFailureRiskProbability": 0.75,
        }
        status, _ = self.request("POST", "/v1/strategies/settings", {
            "limitOrderSubmissionMode": "batch",
            "jevScreeningThresholds": account_a,
        })
        self.assertEqual(status, 200)

        self.exchange.account_uid = "settings-account-b"
        self.assertEqual(self.get_settings(), {
            "limitOrderSubmissionMode": "sequential",
            "jevScreeningThresholds": DEFAULT_THRESHOLDS,
        })
        account_b = {
            "minStructuralQuality": 1,
            "minEntrySuitabilityProbability": 0.2,
            "maxFailureRiskProbability": 0.9,
        }
        status, _ = self.request("POST", "/v1/strategies/settings", {
            "jevScreeningThresholds": account_b,
        })
        self.assertEqual(status, 200)

        self.exchange.account_uid = "settings-account-a"
        self.assertEqual(self.get_settings(), {
            "limitOrderSubmissionMode": "batch",
            "jevScreeningThresholds": account_a,
        })

    def test_invalid_combined_thresholds_are_atomic_red_001(self) -> None:
        initial = self.get_settings()
        invalid_thresholds = [
            {"minStructuralQuality": 3, "minEntrySuitabilityProbability": 0.5},
            {
                "minStructuralQuality": True,
                "minEntrySuitabilityProbability": 0.5,
                "maxFailureRiskProbability": 0.5,
            },
            {
                "minStructuralQuality": 3,
                "minEntrySuitabilityProbability": "0.5",
                "maxFailureRiskProbability": 0.5,
            },
            {
                "minStructuralQuality": 3,
                "minEntrySuitabilityProbability": 0.5,
                "maxFailureRiskProbability": float("nan"),
            },
            {
                "minStructuralQuality": 6,
                "minEntrySuitabilityProbability": 0.5,
                "maxFailureRiskProbability": 0.5,
            },
            {
                "minStructuralQuality": 3,
                "minEntrySuitabilityProbability": 1.01,
                "maxFailureRiskProbability": 0.5,
            },
            {
                "minStructuralQuality": 3,
                "minEntrySuitabilityProbability": 0.5,
                "maxFailureRiskProbability": -0.01,
            },
            {
                "minStructuralQuality": 3,
                "minEntrySuitabilityProbability": 0.5,
                "maxFailureRiskProbability": 10 ** 400,
            },
            {
                "minStructuralQuality": 3,
                "minEntrySuitabilityProbability": 0.5,
                "maxFailureRiskProbability": 0.5,
                "extra": 1,
            },
            None,
        ]
        for thresholds in invalid_thresholds:
            with self.subTest(thresholds=thresholds):
                status, result = self.request("POST", "/v1/strategies/settings", {
                    "limitOrderSubmissionMode": "batch",
                    "jevScreeningThresholds": thresholds,
                })
                self.assertEqual(status, 400, result)
                self.assertEqual(result["error"], "invalid_jev_screening_thresholds")
                self.assertEqual(self.get_settings(), initial)

    def test_unknown_or_empty_settings_request_is_rejected(self) -> None:
        for body in ({}, {"unknown": 1}, {"limitOrderSubmissionMode": "batch", "unknown": 1}):
            with self.subTest(body=body):
                status, result = self.request("POST", "/v1/strategies/settings", body)
                self.assertEqual(status, 400, result)
                self.assertEqual(result["error"], "invalid_strategy_settings")

        status, result = self.request("POST", "/v1/strategies/settings", {
            "limitOrderSubmissionMode": "sometimes",
        })
        self.assertEqual(status, 400, result)
        self.assertEqual(result["error"], "invalid_submission_mode")

    def test_corrupt_persisted_thresholds_fail_closed(self) -> None:
        self.request("POST", "/v1/strategies/settings", {
            "jevScreeningThresholds": {
                "minStructuralQuality": 3,
                "minEntrySuitabilityProbability": 0.5,
                "maxFailureRiskProbability": 0.5,
            },
        })
        _, fingerprint = self.service.strategy._account()
        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategy_account_preferences SET jev_min_structural_quality=7 "
                "WHERE account_fingerprint=?", (fingerprint,),
            )

        status, result = self.request("GET", "/v1/strategies/settings")
        self.assertEqual(status, 500, result)
        self.assertEqual(result["error"], "strategy_settings_unavailable")


class StrategySettingsMigrationTests(unittest.TestCase):
    def test_additive_migration_preserves_legacy_row_and_is_repeatable_and_concurrent(self) -> None:
        db_path = Path(__file__).resolve().parents[2] / (
            f".strategy-settings-migration-{os.getpid()}-{id(self)}.sqlite3"
        )
        try:
            connection = sqlite3.connect(db_path)
            try:
                connection.execute(
                    "CREATE TABLE strategy_account_preferences ("
                    "account_fingerprint TEXT PRIMARY KEY, "
                    "limit_order_submission_mode TEXT NOT NULL, updated_at REAL NOT NULL)"
                )
                connection.execute(
                    "INSERT INTO strategy_account_preferences VALUES (?, ?, ?)",
                    ("legacy-account-fingerprint", "batch", 1234.5),
                )
                connection.commit()
            finally:
                connection.close()

            barrier = threading.Barrier(2)

            def initialize() -> None:
                barrier.wait()
                SQLiteStore(str(db_path)).initialize()

            with ThreadPoolExecutor(max_workers=2) as pool:
                futures = [pool.submit(initialize) for _ in range(2)]
                for future in futures:
                    future.result(timeout=10)

            store = SQLiteStore(str(db_path))
            store.initialize()
            store.initialize()
            with store.connection() as migrated:
                row = migrated.execute(
                    "SELECT * FROM strategy_account_preferences WHERE account_fingerprint=?",
                    ("legacy-account-fingerprint",),
                ).fetchone()
                columns = {item[1] for item in migrated.execute(
                    "PRAGMA table_info(strategy_account_preferences)"
                ).fetchall()}
            self.assertEqual(row["limit_order_submission_mode"], "batch")
            self.assertEqual(row["updated_at"], 1234.5)
            self.assertEqual(row["jev_min_structural_quality"], 4)
            self.assertAlmostEqual(row["jev_min_entry_suitability_probability"], 0.6)
            self.assertAlmostEqual(row["jev_max_failure_risk_probability"], 0.4)
            self.assertTrue({
                "jev_min_structural_quality",
                "jev_min_entry_suitability_probability",
                "jev_max_failure_risk_probability",
            }.issubset(columns))
        finally:
            db_path.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
