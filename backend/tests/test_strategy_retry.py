from __future__ import annotations

import unittest
from decimal import Decimal
from typing import Any

from backend.strategy import StrategyService
from backend.strategy_retry import (
    RetryDataError,
    classify_row,
    fixed_preview,
    source_revision,
)


SIGNING_KEY = bytes(range(32))
SOURCE_ID = "strategy-source-0001"
CLIENT_ID = "source-order-0001"


def source_fixture(
    *,
    status: Any = "rejected",
    error_code: Any = "51008",
    **result_fields: Any,
) -> dict[str, Any]:
    order = {
        "clientOrderId": CLIENT_ID,
        "side": "long",
        "role": "dca",
        "limitPrice": "59000",
        "contracts": "5",
        "leverage": 5,
    }
    result = {
        **order,
        "status": status,
        "errorCode": error_code,
        "filledContracts": "0",
        **result_fields,
    }
    return {
        "id": SOURCE_ID,
        "accountFingerprint": "account-fingerprint",
        "status": "PARTIAL",
        "attemptStarted": True,
        "batchAttempted": True,
        "orderPlacementAttempted": True,
        "submissionMode": "batch",
        "contract": {"instrumentId": "BTC-USDT-SWAP", "interval": "12Hutc"},
        "orders": [order],
        "results": [result],
        "leverageResults": [],
        "queue": None,
        "updatedAt": 100,
    }


class StrategyRetryTests(unittest.TestCase):
    def test_red_malformed_batch_codes_and_fill_or_order_id_evidence_fail_closed(self) -> None:
        order = {"clientOrderId": CLIENT_ID, "side": "long", "role": "dca", "limitPrice": "59000",
                 "contracts": "5", "leverage": 5}
        for raw_code in (True, "51008\nprivate", {"code": "51008"}, None):
            with self.subTest(raw_code=type(raw_code).__name__):
                parsed, status, error = StrategyService._parse_batch_ack(
                    {"code": "0", "data": [{"clOrdId": CLIENT_ID, "sCode": raw_code}]}, [order]
                )
                self.assertEqual(status, "UNKNOWN")
                self.assertEqual(error, "batch_ack_malformed")
                self.assertEqual(parsed[0]["status"], "unknown")

        contradictory_rows = (
            {"clOrdId": CLIENT_ID, "sCode": "51008", "ordId": "exchange-123"},
            {"clOrdId": CLIENT_ID, "sCode": "51008", "ordId": 123},
            {"clOrdId": CLIENT_ID, "sCode": "51008", "ordId": {"id": "exchange-123"}},
            {"clOrdId": CLIENT_ID, "sCode": "00"},
        )
        for row in contradictory_rows:
            with self.subTest(row=row):
                parsed, status, error = StrategyService._parse_batch_ack(
                    {"code": "0", "data": [row]}, [order]
                )
                self.assertEqual(status, "UNKNOWN")
                self.assertEqual(error, "batch_ack_malformed")
                self.assertEqual(parsed[0]["status"], "unknown")

        invalid_rows = (
            source_fixture(filledContracts="-1"),
            source_fixture(averageFillPrice="59000"),
            source_fixture(averageFillPrice="invalid"),
            source_fixture(exchangeOrderId={"id": "malformed"}),
            source_fixture(exchangeOrderId="  "),
            source_fixture(status={"accepted": True}),
            source_fixture(error_code="51008 object"),
            source_fixture(error_code="00"),
        )
        for source in invalid_rows:
            with self.subTest(result=source["results"][0]):
                order_row = source["orders"][0]
                outcome, reason = classify_row(source, 0, order_row, source["results"][0])
                self.assertNotIn(outcome, {"not_submitted", "rejected"})
                self.assertIsNotNone(reason)

        sequential_zero = source_fixture(error_code="00", placementState="rejected")
        sequential_zero["submissionMode"] = "sequential"
        sequential_zero["batchAttempted"] = False
        sequential_zero["orderPlacementAttempted"] = True
        sequential_zero["queue"] = {
            "phase": "stopped", "cursor": 0, "totalCount": 1,
            "previewHash": "b" * 64, "inFlight": None, "deadlineAt": 200,
            "enqueuedAt": 100, "submissionMode": "sequential", "stopReason": "leverage_rejected",
        }
        outcome, reason = classify_row(
            sequential_zero, 0, sequential_zero["orders"][0], sequential_zero["results"][0]
        )
        self.assertEqual(outcome, "other")
        self.assertEqual(reason, "rejection_evidence_invalid")

    def test_red_claimed_or_accepted_rows_are_never_retryable(self) -> None:
        accepted = source_fixture(status="accepted", error_code=None, exchangeOrderId="exchange-123")
        self.assertEqual(classify_row(accepted, 0, accepted["orders"][0], accepted["results"][0])[0], "other")
        claimed = source_fixture(status="not_submitted", error_code=None)
        claimed["submissionMode"] = "sequential"
        claimed["batchAttempted"] = False
        claimed["orderPlacementAttempted"] = False
        claimed["queue"] = {
            "phase": "sending", "cursor": 0, "totalCount": 1,
            "previewHash": "a" * 64,
            "inFlight": {"kind": "placement", "index": 0, "side": "long"},
            "deadlineAt": 200,
        }
        claimed["results"][0]["placementState"] = "sending"
        self.assertEqual(classify_row(claimed, 0, claimed["orders"][0], claimed["results"][0])[0], "other")

    def test_green_fixed_preview_preserves_dca_payload_and_uses_exact_costs(self) -> None:
        source = source_fixture()
        row = source["orders"][0]
        result = source["results"][0]
        preview = fixed_preview(
            source_id=SOURCE_ID,
            source_revision_value="a" * 64,
            selection_hash_value="b" * 64,
            selected=[(0, row, result)],
            instrument_id="BTC-USDT-SWAP",
            interval="12Hutc",
            current_price=Decimal("60000"),
            quote_timestamp_ms=Decimal("1798848000000"),
            contract_value=Decimal("0.001"),
            contract_multiplier=Decimal("1"),
            tick_size=Decimal("0.1"),
            lot_size=Decimal("1"),
            minimum_size=Decimal("1"),
            maker_fee=Decimal("-0.0002"),
            taker_fee=Decimal("0.0005"),
            tiers=[{"min": Decimal("0"), "max": Decimal("100000"),
                    "mmr": Decimal("0.01"), "maxLeverage": Decimal("125")}],
            account_fingerprint="account-fingerprint",
            position_mode="net_mode",
            signing_key=SIGNING_KEY,
        )
        self.assertEqual(preview["orders"][0]["role"], "dca")
        self.assertEqual(preview["orders"][0]["limitPrice"], "59000")
        self.assertEqual(preview["orders"][0]["contracts"], "5")
        self.assertEqual(preview["orders"][0]["notional"], "295")
        self.assertEqual(preview["orders"][0]["margin"], "59")
        self.assertEqual(preview["orders"][0]["openingFeeEstimate"], "0.1475")
        self.assertEqual(preview["requiredBalance"], "59.1475")
        self.assertEqual(preview["unallocatedMargin"], "0")
        self.assertEqual(preview["orders"][0]["sourceClientOrderId"], CLIENT_ID)

        refreshed = fixed_preview(
            source_id=SOURCE_ID,
            source_revision_value="a" * 64,
            selection_hash_value="b" * 64,
            selected=[(0, row, result)],
            instrument_id="BTC-USDT-SWAP",
            interval="12Hutc",
            current_price=Decimal("61000"),
            quote_timestamp_ms=Decimal("1798848001000"),
            contract_value=Decimal("0.001"),
            contract_multiplier=Decimal("1"),
            tick_size=Decimal("0.1"),
            lot_size=Decimal("1"),
            minimum_size=Decimal("1"),
            maker_fee=Decimal("-0.0002"),
            taker_fee=Decimal("0.0005"),
            tiers=[{"min": Decimal("0"), "max": Decimal("100000"),
                    "mmr": Decimal("0.01"), "maxLeverage": Decimal("125")}],
            account_fingerprint="account-fingerprint",
            position_mode="net_mode",
            signing_key=SIGNING_KEY,
        )
        self.assertEqual(refreshed["previewHash"], preview["previewHash"])

    def test_green_source_revision_ignores_poll_time_and_live_fill_amount(self) -> None:
        source = source_fixture(status="live", error_code=None, exchangeOrderId="exchange-123")
        baseline = source_revision(source, SIGNING_KEY)
        refreshed = source_fixture(status="live", error_code=None, exchangeOrderId="exchange-123")
        refreshed["updatedAt"] = 999999
        refreshed["results"][0]["filledContracts"] = "1"
        self.assertEqual(source_revision(refreshed, SIGNING_KEY), baseline)
        _, reason = classify_row(refreshed, 0, refreshed["orders"][0], refreshed["results"][0])
        self.assertEqual(reason, "exchange_order_exists")

    def test_red_exact_fixed_size_must_match_current_lot_rules(self) -> None:
        source = source_fixture()
        with self.assertRaises(RetryDataError):
            fixed_preview(
                source_id=SOURCE_ID,
                source_revision_value="a" * 64,
                selection_hash_value="b" * 64,
                selected=[(0, source["orders"][0], source["results"][0])],
                instrument_id="BTC-USDT-SWAP",
                interval="12Hutc",
                current_price=Decimal("60000"),
                quote_timestamp_ms=Decimal("1798848000000"),
                contract_value=Decimal("0.001"),
                contract_multiplier=Decimal("1"),
                tick_size=Decimal("0.1"),
                lot_size=Decimal("2"),
                minimum_size=Decimal("1"),
                maker_fee=Decimal("-0.0002"),
                taker_fee=Decimal("0.0005"),
                tiers=[{"min": Decimal("0"), "max": Decimal("100000"),
                        "mmr": Decimal("0.01"), "maxLeverage": Decimal("125")}],
                account_fingerprint="account-fingerprint",
                position_mode="net_mode",
                signing_key=SIGNING_KEY,
            )


if __name__ == "__main__":
    unittest.main()
