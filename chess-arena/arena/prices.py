"""每百万 token 的美元价格，用来算每局成本。来源见 README；没列的模型成本记 None。"""
PRICES = {
    # Anthropic（platform.claude.com 价格表，2026-10）
    "claude-fable-5-1": (10.00, 50.00),
    "claude-opus-5-5": (4.00, 20.00),
    "claude-sonnet-5-5": (2.00, 10.00),
    # OpenAI：对局前在 README 里确认 gpt-6-astra 的官方价格后填入
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
