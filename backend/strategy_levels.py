"""Exact-decimal port of the Strategy screen's confirmed-candle level calculator."""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation, ROUND_CEILING, ROUND_FLOOR, localcontext
from typing import Any, Iterable


_INTERVALS: dict[str, tuple[int, int]] = {
    "6Hutc": (6 * 60 * 60 * 1000, 0),
    "1Dutc": (24 * 60 * 60 * 1000, 0),
    # Monday 1969-12-29 00:00:00 UTC is the calendar anchor used by Flutter.
    "1Wutc": (7 * 24 * 60 * 60 * 1000, -3 * 24 * 60 * 60 * 1000),
}
_DECIMAL_PATTERN = re.compile(r"^([+-]?)(?:(\d+)(?:\.(\d*))?|\.(\d+))(?:[eE]([+-]?\d+))?$")
_MAX_DECIMAL_TEXT = 1024
_CALCULATION_PRECISION = 4096


class CandleDataError(ValueError):
    """Market candle data cannot be used for strategy generation."""


def parse_decimal(value: Any) -> Decimal | None:
    """Parse the same bounded decimal forms accepted by StrategyDecimal."""
    if isinstance(value, bool) or not isinstance(value, (str, int)):
        return None
    text = str(value).strip()
    if not text or len(text) > _MAX_DECIMAL_TEXT or _DECIMAL_PATTERN.fullmatch(text) is None:
        return None
    match = _DECIMAL_PATTERN.fullmatch(text)
    assert match is not None
    exponent_text = match.group(5) or "0"
    try:
        exponent = int(exponent_text)
        if abs(exponent) > 1024:
            return None
        result = Decimal(text)
    except (InvalidOperation, ValueError, OverflowError):
        return None
    return result if result.is_finite() else None


def decimal_text(value: Decimal) -> str:
    if value == 0:
        return "0"
    text = format(value, "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return text


def interval_milliseconds(interval: str) -> int:
    try:
        return _INTERVALS[interval][0]
    except KeyError:
        raise CandleDataError("unsupported_interval") from None


def iso_timestamp(timestamp_ms: int) -> str:
    seconds, milliseconds = divmod(timestamp_ms, 1000)
    value = datetime.fromtimestamp(seconds, tz=timezone.utc).replace(microsecond=milliseconds * 1000)
    return value.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def timestamp_milliseconds(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str) and re.fullmatch(r"-?\d{1,16}", value):
        try:
            return int(value)
        except ValueError:
            return None
    return None


def _is_aligned(timestamp_ms: int, interval: str) -> bool:
    width, anchor = _INTERVALS[interval]
    return (timestamp_ms - anchor) % width == 0


def normalize_candles(
    rows: Iterable[Any],
    *,
    interval: str,
    snapshot_time_ms: int,
) -> list[dict[str, Any]]:
    """Keep only unique, valid, UTC-aligned, confirmed candles closed by snapshot time."""
    if interval not in _INTERVALS:
        raise CandleDataError("unsupported_interval")
    width = _INTERVALS[interval][0]
    by_timestamp: dict[int, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, (list, tuple)) or len(row) < 9:
            continue
        timestamp = timestamp_milliseconds(row[0])
        if timestamp is None or not _is_aligned(timestamp, interval):
            continue
        if str(row[8]) != "1" or timestamp + width > snapshot_time_ms:
            continue
        open_price, high, low, close = (parse_decimal(row[index]) for index in (1, 2, 3, 4))
        if any(value is None or value <= 0 for value in (open_price, high, low, close)):
            continue
        assert open_price is not None and high is not None and low is not None and close is not None
        if (
            high < low or high < open_price or high < close
            or low > open_price or low > close
        ):
            continue
        volume = parse_decimal(row[5])
        normalized = {
            "timestampMs": timestamp,
            "timestamp": iso_timestamp(timestamp),
            "open": decimal_text(open_price),
            "high": decimal_text(high),
            "low": decimal_text(low),
            "close": decimal_text(close),
            "volume": None if volume is None or volume < 0 else decimal_text(volume),
        }
        # Duplicate pages can overlap. A timestamp remains one candle and the
        # first valid copy wins, matching the market repository's de-duplication.
        by_timestamp.setdefault(timestamp, normalized)
    return [by_timestamp[key] for key in sorted(by_timestamp)]


@dataclass(frozen=True)
class _Swing:
    price: Decimal
    timestamp_ms: int
    level_id: str


def calculate_levels(
    candles: list[dict[str, Any]],
    *,
    reference_price: str,
    tick_size: str,
    interval: str,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Return `(supports, resistances)` with StrategyLevelCalculator parity."""
    if interval not in _INTERVALS:
        raise CandleDataError("unsupported_interval")
    reference = parse_decimal(reference_price)
    tick = parse_decimal(tick_size)
    if reference is None or reference <= 0 or tick is None or tick <= 0:
        raise CandleDataError("invalid_market_decimal")

    with localcontext() as context:
        context.prec = _CALCULATION_PRECISION
        ordered: list[dict[str, Any]] = []
        previous_timestamp: int | None = None
        for candle in candles:
            timestamp = candle.get("timestampMs")
            if (
                isinstance(timestamp, bool) or not isinstance(timestamp, int)
                or not _is_aligned(timestamp, interval)
                or (previous_timestamp is not None and timestamp <= previous_timestamp)
            ):
                raise CandleDataError("invalid_candle_order")
            previous_timestamp = timestamp
            values = [parse_decimal(candle.get(key)) for key in ("open", "high", "low", "close")]
            if any(value is None or value <= 0 for value in values):
                continue
            open_price, high, low, close = values
            assert open_price is not None and high is not None and low is not None and close is not None
            if (
                high < low or high < open_price or high < close
                or low > open_price or low > close
            ):
                continue
            ordered.append(candle)

        window = ordered[-500:]
        swings: list[_Swing] = []
        for index in range(2, len(window) - 2):
            current = window[index]
            current_high = parse_decimal(current["high"])
            current_low = parse_decimal(current["low"])
            assert current_high is not None and current_low is not None
            is_high = True
            is_low = True
            for offset in (1, 2):
                left = window[index - offset]
                right = window[index + offset]
                left_high, right_high = parse_decimal(left["high"]), parse_decimal(right["high"])
                left_low, right_low = parse_decimal(left["low"]), parse_decimal(right["low"])
                assert left_high is not None and right_high is not None
                assert left_low is not None and right_low is not None
                if current_high <= left_high or current_high <= right_high:
                    is_high = False
                if current_low >= left_low or current_low >= right_low:
                    is_low = False
            timestamp = current["timestampMs"]
            if is_high:
                swings.append(_Swing(current_high, timestamp, f"high_{timestamp}"))
            if is_low:
                swings.append(_Swing(current_low, timestamp, f"low_{timestamp}"))

        swings.sort(key=lambda item: (item.price, item.timestamp_ms, item.level_id))
        clusters: list[list[_Swing]] = []
        for candidate in swings:
            if not clusters:
                clusters.append([candidate])
                continue
            cluster = clusters[-1]
            minimum = cluster[0].price
            if (candidate.price - minimum) * 200 <= minimum:
                cluster.append(candidate)
            else:
                clusters.append([candidate])

        supports: list[dict[str, Any]] = []
        resistances: list[dict[str, Any]] = []
        for cluster in clusters:
            prices = sorted(candidate.price for candidate in cluster)
            middle = len(prices) // 2
            median = prices[middle] if len(prices) % 2 else (prices[middle - 1] + prices[middle]) / Decimal(2)
            comparison = (median > reference) - (median < reference)
            if comparison == 0:
                continue
            side = "long" if comparison < 0 else "short"
            tick_count = median / tick
            if side == "long":
                quantized = tick_count.to_integral_value(rounding=ROUND_FLOOR) * tick
                if quantized >= reference:
                    continue
            else:
                quantized = tick_count.to_integral_value(rounding=ROUND_CEILING) * tick
                if quantized <= reference:
                    continue
            by_source = sorted(cluster, key=lambda item: (item.timestamp_ms, item.level_id))
            timestamps = sorted(candidate.timestamp_ms for candidate in cluster)
            generation_order = len(supports) + 1 if side == "long" else len(resistances) + 1
            level = {
                "levelId": by_source[0].level_id,
                "side": side,
                "price": decimal_text(quantized),
                "touchCount": len(cluster),
                "firstTouchAt": iso_timestamp(timestamps[0]),
                "lastTouchAt": iso_timestamp(timestamps[-1]),
                "generationOrder": generation_order,
            }
            (supports if side == "long" else resistances).append(level)

        supports.sort(key=lambda row: (-Decimal(row["price"]), row["levelId"]))
        resistances.sort(key=lambda row: (Decimal(row["price"]), row["levelId"]))
        for order, level in enumerate(supports, start=1):
            level["generationOrder"] = order
        for order, level in enumerate(resistances, start=1):
            level["generationOrder"] = order
        return supports, resistances
