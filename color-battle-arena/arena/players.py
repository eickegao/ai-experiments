"""Players. Every LLM player gets the same system prompt and observation text and returns raw text; parsing happens
in prompt.parse. Each decision is a fresh, stateless request (no chat history), so what the model knows is exactly what
is in the observation. Reasoning depth is set to the provider's "high" for everyone.
"""
from __future__ import annotations

import os
import random
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone


@dataclass
class Reply:
    text: str
    seconds: float
    usage: dict = field(default_factory=dict)  # input / output / reasoning tokens where the API reports them
    error: str | None = None
    prompt: str = ""
    at: str = ""  # UTC ISO timestamp of the call (DeepSeek pricing depends on it)


class Player:
    name = "player"
    model = ""
    vendor = ""
    is_llm = True

    def decide(self, system: str, obs: str) -> Reply:
        raise NotImplementedError


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class ClaudePlayer(Player):
    """Anthropic. claude-fable-5-1 is Anthropic's top tier. Thinking is on; depth via output_config.effort."""

    vendor = "Anthropic"

    def __init__(self, model: str = "claude-fable-5-1", effort: str = "high"):
        import anthropic

        self.client = anthropic.Anthropic()
        self.model, self.effort = model, effort
        self.name = f"Claude ({model})"

    def decide(self, system, obs) -> Reply:
        import anthropic

        t0, at = time.time(), _now()
        try:
            r = self.client.messages.create(
                model=self.model, max_tokens=6000, system=system, output_config={"effort": self.effort},
                messages=[{"role": "user", "content": obs}],
            )
        except anthropic.APIError as e:
            return Reply("", time.time() - t0, error=f"{type(e).__name__}: {e}", prompt=obs, at=at)
        if r.stop_reason == "refusal":
            return Reply("", time.time() - t0, error="refusal", prompt=obs, at=at)
        text = "".join(b.text for b in r.content if b.type == "text")
        return Reply(text, time.time() - t0, {"input": r.usage.input_tokens, "output": r.usage.output_tokens}, prompt=obs, at=at)


class OpenAIPlayer(Player):
    """OpenAI. gpt-6-astra is the flagship. Responses API with reasoning effort."""

    vendor = "OpenAI"

    def __init__(self, model: str = "gpt-6-astra", effort: str = "high"):
        import openai

        self.client = openai.OpenAI()
        self.model, self.effort = model, effort
        self.name = f"GPT ({model})"

    def decide(self, system, obs) -> Reply:
        import openai

        t0, at = time.time(), _now()
        try:
            r = self.client.responses.create(
                model=self.model, instructions=system, input=obs, reasoning={"effort": self.effort}, max_output_tokens=6000,
            )
        except openai.APIError as e:
            return Reply("", time.time() - t0, error=f"{type(e).__name__}: {e}", prompt=obs, at=at)
        u = r.usage
        usage = {"input": getattr(u, "input_tokens", 0), "output": getattr(u, "output_tokens", 0)} if u else {}
        det = getattr(u, "output_tokens_details", None)
        if det is not None and getattr(det, "reasoning_tokens", None) is not None:
            usage["reasoning"] = det.reasoning_tokens
        return Reply(r.output_text or "", time.time() - t0, usage, prompt=obs, at=at)


class GeminiPlayer(Player):
    """Google. gemini-4-argon is the flagship model callable through the public Gemini API (Gemini 4 Carbon has no public
    API model ID as of 2026-11-09). Thinking level high. Key: GEMINI_API_KEY."""

    vendor = "Google"

    def __init__(self, model: str = "gemini-4-argon", effort: str = "high"):
        from google import genai

        self.client = genai.Client(api_key=os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY"))
        self.model, self.effort = model, effort
        self.name = f"Gemini ({model})"

    def decide(self, system, obs) -> Reply:
        from google.genai import types

        t0, at = time.time(), _now()
        try:
            r = self.client.models.generate_content(
                model=self.model, contents=obs,
                config=types.GenerateContentConfig(
                    system_instruction=system, max_output_tokens=6000,
                    thinking_config=types.ThinkingConfig(thinking_level=self.effort),
                ),
            )
        except Exception as e:  # google-genai raises its own error classes
            return Reply("", time.time() - t0, error=f"{type(e).__name__}: {e}", prompt=obs, at=at)
        um = r.usage_metadata
        usage = {}
        if um is not None:
            usage = {"input": um.prompt_token_count or 0, "output": (um.candidates_token_count or 0) + (um.thoughts_token_count or 0)}
            if um.thoughts_token_count:
                usage["reasoning"] = um.thoughts_token_count
        return Reply(r.text or "", time.time() - t0, usage, prompt=obs, at=at)


class DeepSeekPlayer(Player):
    """DeepSeek. deepseek-v4-pro (serves DeepSeek-V4-Pro-0813) through the OpenAI-compatible endpoint with thinking on.
    Key: DEEPSEEK_API_KEY."""

    vendor = "DeepSeek"

    def __init__(self, model: str = "deepseek-v4-pro", effort: str = "high"):
        import openai

        self.client = openai.OpenAI(api_key=os.environ["DEEPSEEK_API_KEY"], base_url="https://api.deepseek.com")
        self.model, self.effort = model, effort
        self.name = f"DeepSeek ({model})"

    def decide(self, system, obs) -> Reply:
        import openai

        # DeepSeek counts its thinking against max_tokens; at effort high a draft question used the whole 6000 budget and
        # came back with no answer text (2026-11-09). Budget 24000, and if the answer is still empty retry once at medium.
        t0, at = time.time(), _now()
        usage: dict = {}
        for attempt, (effort, budget) in enumerate(((self.effort, 24000), ("medium", 24000))):
            try:
                r = self.client.chat.completions.create(
                    model=self.model, max_tokens=budget,
                    messages=[{"role": "system", "content": system}, {"role": "user", "content": obs}],
                    extra_body={"thinking": {"type": "enabled"}, "reasoning_effort": effort},
                )
            except openai.APIError as e:
                return Reply("", time.time() - t0, usage, error=f"{type(e).__name__}: {e}", prompt=obs, at=at)
            msg = r.choices[0].message if r.choices else None
            text = (msg.content or "") if msg else ""
            u = r.usage
            got = {"input": getattr(u, "prompt_tokens", 0), "output": getattr(u, "completion_tokens", 0)} if u else {}
            det = getattr(u, "completion_tokens_details", None) if u else None
            if det is not None and getattr(det, "reasoning_tokens", None):
                got["reasoning"] = det.reasoning_tokens
            usage = {k: usage.get(k, 0) + v for k, v in got.items()} if usage else got   # both attempts are paid for
            if text.strip():
                if attempt:
                    usage["retried_at_medium"] = True
                return Reply(text, time.time() - t0, usage, prompt=obs, at=at)
            finish = getattr(r.choices[0], "finish_reason", "") if r.choices else ""
            if finish != "length":
                break
        return Reply("", time.time() - t0, usage, error=f"empty answer (finish_reason={finish}, reasoning tokens {usage.get('reasoning', '?')})", prompt=obs, at=at)


class OpenRouterPlayer(Player):
    """Any model through OpenRouter (one key, one balance for every vendor). OpenAI-compatible chat API at
    https://openrouter.ai/api/v1 with the unified `reasoning.effort` parameter; OpenRouter reports the exact USD cost of
    each call in `usage.cost`, which we record instead of our own price table. Key: OPENROUTER_API_KEY.
    Model ids: anthropic/claude-fable-5.1, openai/gpt-6-astra, google/gemini-4-argon, deepseek/deepseek-v4-pro …"""

    vendor = "OpenRouter"

    def __init__(self, model: str, effort: str = "high"):
        import openai

        self.client = openai.OpenAI(base_url="https://openrouter.ai/api/v1", api_key=os.environ["OPENROUTER_API_KEY"],
                                    default_headers={"HTTP-Referer": "https://github.com/eickegao/ai-experiments", "X-Title": "Color Battle Arena"})
        self.model, self.effort = model, effort
        short = model.split("/")[-1]
        label = {"anthropic": "Claude", "openai": "GPT", "google": "Gemini", "deepseek": "DeepSeek"}.get(model.split("/")[0], model.split("/")[0])
        self.name = f"{label} ({short})"
        self.vendor = f"{label} via OpenRouter"

    def decide(self, system, obs) -> Reply:
        import openai

        t0, at = time.time(), _now()
        try:
            r = self.client.chat.completions.create(
                model=self.model, max_tokens=6000,
                messages=[{"role": "system", "content": system}, {"role": "user", "content": obs}],
                extra_body={"reasoning": {"effort": self.effort}, "usage": {"include": True}},
            )
        except openai.APIError as e:
            return Reply("", time.time() - t0, error=f"{type(e).__name__}: {e}", prompt=obs, at=at)
        text = (r.choices[0].message.content or "") if r.choices else ""
        u = r.usage
        usage = {"input": getattr(u, "prompt_tokens", 0) or 0, "output": getattr(u, "completion_tokens", 0) or 0} if u else {}
        det = getattr(u, "completion_tokens_details", None) if u else None
        if det is not None and getattr(det, "reasoning_tokens", None) is not None:
            usage["reasoning"] = det.reasoning_tokens
        cost = getattr(u, "cost", None) if u else None
        if cost is None and u is not None and hasattr(u, "model_extra"):
            cost = (u.model_extra or {}).get("cost")
        if cost is not None:
            usage["cost"] = float(cost)
        if not text and r.choices and getattr(r.choices[0], "finish_reason", "") == "length":
            return Reply("", time.time() - t0, usage, error="max_tokens reached before any answer text", prompt=obs, at=at)
        return Reply(text, time.time() - t0, usage, prompt=obs, at=at)


class RandomPlayer(Player):
    """Dry runs: turns toward a random point, sometimes casts, sometimes answers garbage (to exercise the rejection path)."""

    vendor = "random"
    model = "random"

    def __init__(self, seed: int = 0, slots: int = 0):
        self.rng = random.Random(seed)
        self.slots = slots
        self.name = f"Random#{seed}"

    def decide(self, system, obs) -> Reply:
        t0 = time.time()
        r = self.rng.random()
        if r < 0.1:
            text = "I'll go there. CMD: TURN far away"
        elif self.slots and r < 0.4:
            text = f"CMD: CAST {self.rng.randint(1, self.slots)} {self.rng.uniform(0, 32):.1f} {self.rng.uniform(0, 32):.1f}\nCMD: TURN {self.rng.uniform(0, 32):.1f} {self.rng.uniform(0, 32):.1f}"
        else:
            text = f"Heading for open ground.\nCMD: TURN {self.rng.uniform(0, 32):.1f} {self.rng.uniform(0, 32):.1f}"
        return Reply(text, time.time() - t0, {"input": 0, "output": 0}, prompt=obs, at=_now())


class BotPlayer(Player):
    """The game's own computer opponent (cd_ai.lua). It is not an LLM: it acts every tick inside the simulation, exactly as in
    the shipped game, so it serves as the reference for 'what a decent scripted player scores'."""

    vendor = "PlayDoz bot"
    model = "cd_ai"
    is_llm = False

    def __init__(self, eager: float = 0.6):
        self.eager = eager
        self.name = f"Bot (eager {eager:g})"


def make_player(spec: str, effort: str = "high", seed: int = 0, slots: int = 0) -> Player:
    """spec: claude[:<model>] | openai[:<model>] | gemini[:<model>] | deepseek[:<model>] | or:<vendor/model> (OpenRouter) | bot[:<eager>] | random"""
    kind, _, arg = spec.partition(":")
    if kind in ("or", "openrouter"):
        return OpenRouterPlayer(arg or "anthropic/claude-fable-5.1", effort)
    if kind == "claude":
        return ClaudePlayer(arg or "claude-fable-5-1", effort)
    if kind == "openai":
        return OpenAIPlayer(arg or "gpt-6-astra", effort)
    if kind == "gemini":
        return GeminiPlayer(arg or "gemini-4-argon", effort)
    if kind == "deepseek":
        return DeepSeekPlayer(arg or "deepseek-v4-pro", effort)
    if kind == "bot":
        return BotPlayer(float(arg or 0.6))
    if kind == "random":
        return RandomPlayer(seed, slots)
    raise SystemExit(f"unknown player {spec!r}")
