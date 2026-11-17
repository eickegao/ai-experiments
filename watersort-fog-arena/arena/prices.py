"""Per-model prices, USD per million tokens: (input, cached input, output incl. reasoning). Cached input is what a
long single conversation mostly pays, because every turn re-sends the whole history. Read from the price pages on 2026-11-17.

DeepSeek bills in CNY with a peak / off-peak schedule (Beijing time Mon-Fri 9-12 and 14-18 is peak, everything else half
price); we convert at a fixed rate and pick the window from the UTC timestamp of each call.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

CNY_PER_USD = 7.1  # approximate, Nov 2026; only affects the DeepSeek line

PRICES: dict[str, tuple[float, float | None, float]] = {
    # Anthropic: cache read 0.20; cache writes cost 1.25x input (CACHE_WRITE_FACTOR)
    "claude-fable-5-2": (8.00, 0.20, 40.00),
    # OpenAI (developers.openai.com/api/docs/pricing, standard tier, prompts up to 272K tokens)
    "gpt-6.2-astra": (8.00, 0.40, 40.00),
    "gpt-6-astra": (10.00, 1.00, 50.00),
    # Google (aistudio.google.com/docs/pricing, standard tier; all three numbers double on 2026-12-01)
    "gemini-4-carbon": (2.00, 0.10, 10.00),
    "gemini-4-argon": (2.00, 0.10, 10.00),
}
CACHE_WRITE_FACTOR = {"claude-fable-5-2": 1.25}
# DeepSeek (api-docs.deepseek.com/zh-cn/quick_start/pricing), CNY per 1M, peak; off-peak is half: (input, cache hit, output)
DEEPSEEK_CNY = {"deepseek-v4-pro": (9.0, 0.30, 27.0)}
BEIJING = timezone(timedelta(hours=8))


def deepseek_is_peak(when_utc: datetime) -> bool:
    bj = when_utc.astimezone(BEIJING)
    if bj.weekday() >= 5:
        return False
    h = bj.hour + bj.minute / 60
    return 9 <= h < 12 or 14 <= h < 18


def unit_prices(model: str, when_utc: datetime | None = None) -> tuple[float, float | None, float] | None:
    if model in PRICES:
        return PRICES[model]
    if model in DEEPSEEK_CNY:
        k = (1.0 if deepseek_is_peak(when_utc or datetime.now(timezone.utc)) else 0.5) / CNY_PER_USD
        i, c, o = DEEPSEEK_CNY[model]
        return (i * k, c * k, o * k)
    return None


def call_cost(model: str, usage: dict, when_utc: datetime | None = None) -> float | None:
    """usage: input (all prompt tokens), cached (the part read from cache), cache_write (the part written), output."""
    pr = unit_prices(model, when_utc)
    if not pr or not usage:
        return None
    fresh_price, cached_price, out_price = pr
    cached = usage.get("cached", 0) if cached_price is not None else 0
    write = usage.get("cache_write", 0)
    fresh = usage.get("input", 0) - cached - write
    wf = CACHE_WRITE_FACTOR.get(model, 1.0)
    return (fresh * fresh_price + write * fresh_price * wf + cached * (cached_price or 0) + usage.get("output", 0) * out_price) / 1_000_000
