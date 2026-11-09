"""USD per million tokens (input, output), used for per-game cost. Models not listed get cost None."""
PRICES = {
    # Anthropic (platform.claude.com price list, Oct 2026)
    "claude-fable-5-1": (10.00, 50.00),
    "claude-opus-5-5": (4.00, 20.00),
    "claude-sonnet-5-5": (2.00, 10.00),
    # OpenAI: fill in from the official price page before the match
    "gpt-6-astra": None,
    "gpt-6.1-terra": None,
}


def cost_usd(model: str, plies: list, side: str):
    pr = PRICES.get(model)
    if not pr:
        return None
    i = sum(a["usage"].get("input", 0) for p in plies if p["side"] == side for a in p["attempts"])
    o = sum(a["usage"].get("output", 0) for p in plies if p["side"] == side for a in p["attempts"])
    return round((i * pr[0] + o * pr[1]) / 1_000_000, 4)
