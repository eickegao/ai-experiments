"""Per-model prices, USD per million tokens (input on cache miss, output incl. reasoning). Read 2026-11-09.

DeepSeek bills in CNY with a peak / off-peak schedule (Beijing time Mon-Fri 9-12 and 14-18 is peak; everything else,
weekends and Chinese public holidays included, is off-peak at half price). We convert at a fixed rate noted below and pick
the window from the UTC timestamp of each call.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

CNY_PER_USD = 7.1  # approximate, Nov 2026; only affects the DeepSeek line

PRICES = {
    # Anthropic (platform.claude.com price list)
    "claude-fable-5-1": (10.00, 50.00),
    "claude-opus-5-5": (4.00, 20.00),
    # OpenAI (developers.openai.com/api/docs/pricing, standard tier)
    "gpt-6-astra": (10.00, 50.00),
    # Google (aistudio.google.com/docs/pricing, standard tier; doubles to 4 / 20 from 2026-12-01)
    "gemini-4-argon": (2.00, 10.00),
}
# DeepSeek (api-docs.deepseek.com/zh-cn/quick_start/pricing), CNY per 1M: (peak_in, peak_out, offpeak_in, offpeak_out)
DEEPSEEK_CNY = {
    "deepseek-v4-pro": (9.0, 27.0, 4.5, 13.5),
    "deepseek-flash": (2.0, 8.0, 1.0, 4.0),
}
BEIJING = timezone(timedelta(hours=8))


def deepseek_is_peak(when_utc: datetime) -> bool:
    bj = when_utc.astimezone(BEIJING)
    if bj.weekday() >= 5:
        return False
    h = bj.hour + bj.minute / 60
    return 9 <= h < 12 or 14 <= h < 18


def unit_prices(model: str, when_utc: datetime | None = None) -> tuple[float, float] | None:
    if model in PRICES:
        return PRICES[model]
    if model in DEEPSEEK_CNY:
        p = DEEPSEEK_CNY[model]
        peak = deepseek_is_peak(when_utc or datetime.now(timezone.utc))
        i, o = (p[0], p[1]) if peak else (p[2], p[3])
        return (i / CNY_PER_USD, o / CNY_PER_USD)
    return None


def call_cost(model: str, usage: dict, when_utc: datetime | None = None) -> float | None:
    if usage and usage.get("cost") is not None:   # OpenRouter reports the exact charge per call
        return float(usage["cost"])
    pr = unit_prices(model, when_utc)
    if not pr or not usage:
        return None
    return (usage.get("input", 0) * pr[0] + usage.get("output", 0) * pr[1]) / 1_000_000
