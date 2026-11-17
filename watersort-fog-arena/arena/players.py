"""Players. Every LLM gets the same system prompt and the same conversation: the whole session is ONE multi-turn chat,
so everything the model saw and said earlier (boards, its own reasons, failed attempts) is in its context. Only the
visible reply text is carried forward; hidden reasoning is not replayed, for any vendor. Reasoning depth is the same
word ("medium" / "high") for everyone.
"""
from __future__ import annotations

import os
import random
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone

MAX_OUT = 16000


@dataclass
class Reply:
    text: str
    seconds: float
    usage: dict = field(default_factory=dict)   # input / cached / cache_write / output / reasoning, where reported
    error: str | None = None
    at: str = ""                                # UTC ISO timestamp of the call (DeepSeek pricing depends on it)


class Player:
    name = "player"
    model = ""
    vendor = ""

    def chat(self, system: str, messages: list[dict]) -> Reply:
        """messages: [{"role": "user" | "assistant", "content": str}, ...], ending with a user turn."""
        raise NotImplementedError


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class ClaudePlayer(Player):
    """Anthropic. Thinking is always on for this model; depth via output_config.effort. Top-level cache_control caches
    the growing conversation prefix. No refusal fallback on purpose: another model answering would spoil the comparison."""

    vendor = "Anthropic"

    def __init__(self, model: str = "claude-fable-5-2", effort: str = "medium"):
        import anthropic

        self.client = anthropic.Anthropic()
        self.model, self.effort = model, effort
        self.name = f"Claude ({model})"

    def chat(self, system, messages) -> Reply:
        import anthropic

        t0, at = time.time(), _now()
        try:
            r = self.client.messages.create(
                model=self.model, max_tokens=MAX_OUT, system=system, output_config={"effort": self.effort},
                cache_control={"type": "ephemeral"}, messages=messages,
            )
        except anthropic.APIError as e:
            return Reply("", time.time() - t0, error=f"{type(e).__name__}: {e}", at=at)
        if r.stop_reason == "refusal":
            return Reply("", time.time() - t0, error="refusal", at=at)
        u = r.usage
        read, write = u.cache_read_input_tokens or 0, u.cache_creation_input_tokens or 0
        usage = {"input": u.input_tokens + read + write, "cached": read, "cache_write": write, "output": u.output_tokens}
        text = "".join(b.text for b in r.content if b.type == "text")
        return Reply(text, time.time() - t0, usage, at=at)


class OpenAIPlayer(Player):
    """OpenAI, Responses API with reasoning effort. Prompt caching is automatic."""

    vendor = "OpenAI"

    def __init__(self, model: str = "gpt-6.2-astra", effort: str = "medium"):
        import openai

        self.client = openai.OpenAI()
        self.model, self.effort = model, effort
        self.name = f"GPT ({model})"

    def chat(self, system, messages) -> Reply:
        import openai

        t0, at = time.time(), _now()
        try:
            r = self.client.responses.create(
                model=self.model, instructions=system, input=messages, reasoning={"effort": self.effort},
                max_output_tokens=MAX_OUT,
            )
        except openai.APIError as e:
            return Reply("", time.time() - t0, error=f"{type(e).__name__}: {e}", at=at)
        u = r.usage
        usage = {"input": getattr(u, "input_tokens", 0), "output": getattr(u, "output_tokens", 0)} if u else {}
        det = getattr(u, "input_tokens_details", None)
        if det is not None and getattr(det, "cached_tokens", None):
            usage["cached"] = det.cached_tokens
        det = getattr(u, "output_tokens_details", None)
        if det is not None and getattr(det, "reasoning_tokens", None) is not None:
            usage["reasoning"] = det.reasoning_tokens
        return Reply(r.output_text or "", time.time() - t0, usage, at=at)


class GeminiPlayer(Player):
    """Google, Gemini API with a thinking level. Key: GEMINI_API_KEY."""

    vendor = "Google"

    def __init__(self, model: str = "gemini-4-carbon", effort: str = "medium"):
        from google import genai

        self.client = genai.Client(api_key=os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY"))
        self.model, self.effort = model, effort
        self.name = f"Gemini ({model})"

    def chat(self, system, messages) -> Reply:
        from google.genai import types

        contents = [types.Content(role="model" if m["role"] == "assistant" else "user", parts=[types.Part(text=m["content"])])
                    for m in messages]
        t0, at = time.time(), _now()
        try:
            r = self.client.models.generate_content(
                model=self.model, contents=contents,
                config=types.GenerateContentConfig(
                    system_instruction=system, max_output_tokens=MAX_OUT,
                    thinking_config=types.ThinkingConfig(thinking_level=self.effort),
                ),
            )
        except Exception as e:  # google-genai raises its own error classes
            return Reply("", time.time() - t0, error=f"{type(e).__name__}: {e}", at=at)
        um = r.usage_metadata
        usage = {}
        if um is not None:
            usage = {"input": um.prompt_token_count or 0, "output": (um.candidates_token_count or 0) + (um.thoughts_token_count or 0)}
            if um.cached_content_token_count:
                usage["cached"] = um.cached_content_token_count
            if um.thoughts_token_count:
                usage["reasoning"] = um.thoughts_token_count
        return Reply(r.text or "", time.time() - t0, usage, at=at)


class DeepSeekPlayer(Player):
    """DeepSeek through its OpenAI-compatible endpoint, thinking on. Its thinking counts against max_tokens, so the
    budget is larger than for the others. Key: DEEPSEEK_API_KEY."""

    vendor = "DeepSeek"

    def __init__(self, model: str = "deepseek-v4-pro", effort: str = "medium"):
        import openai

        self.client = openai.OpenAI(api_key=os.environ["DEEPSEEK_API_KEY"], base_url="https://api.deepseek.com")
        self.model, self.effort = model, effort
        self.name = f"DeepSeek ({model})"

    def chat(self, system, messages) -> Reply:
        import openai

        t0, at = time.time(), _now()
        try:
            r = self.client.chat.completions.create(
                model=self.model, max_tokens=24000,
                messages=[{"role": "system", "content": system}, *messages],
                extra_body={"thinking": {"type": "enabled"}, "reasoning_effort": self.effort},
            )
        except openai.APIError as e:
            return Reply("", time.time() - t0, error=f"{type(e).__name__}: {e}", at=at)
        msg = r.choices[0].message if r.choices else None
        text = (msg.content or "") if msg else ""
        u = r.usage
        usage = {"input": getattr(u, "prompt_tokens", 0), "output": getattr(u, "completion_tokens", 0)} if u else {}
        hit = getattr(u, "prompt_cache_hit_tokens", None) if u else None
        if hit:
            usage["cached"] = hit
        det = getattr(u, "completion_tokens_details", None) if u else None
        if det is not None and getattr(det, "reasoning_tokens", None):
            usage["reasoning"] = det.reasoning_tokens
        if not text.strip():
            finish = getattr(r.choices[0], "finish_reason", "") if r.choices else ""
            return Reply("", time.time() - t0, usage, error=f"empty answer (finish_reason={finish})", at=at)
        return Reply(text, time.time() - t0, usage, at=at)


class RandomPlayer(Player):
    """Free dry runs, no API key: random legal pours, some undos and restarts, some garbage (to exercise fouls).
    The runner hands it the game object; it is not a model and reads nothing from the conversation."""

    vendor = "random"
    model = "random"

    def __init__(self, seed: int = 0):
        self.rng = random.Random(seed)
        self.name = f"Random#{seed}"
        self.game = None

    def chat(self, system, messages) -> Reply:
        g, r = self.game, self.rng.random()
        n = len(g.tubes)
        legal = [(a, b) for a in range(1, n + 1) for b in range(1, n + 1) if g.why_illegal(a, b) is None]
        if r < 0.05:
            text = "Let me think about tube 3.\nMOVE three to four"
        elif r < 0.10:
            text = f"Trying something.\nMOVE {self.rng.randint(1, n)} {self.rng.randint(1, n)}"
        elif r < 0.20 and g.can_undo():
            text = "That was a mistake.\nUNDO"
        elif r < 0.22 or not legal:
            text = "Starting over.\n**RESTART**"
        else:
            a, b = self.rng.choice(legal)
            text = f"Looks fine.\nMOVE {a} {b}"
        return Reply(text, 0.0, {"input": 0, "output": 0}, at=_now())


KINDS = {"claude": ClaudePlayer, "openai": OpenAIPlayer, "gemini": GeminiPlayer, "deepseek": DeepSeekPlayer}


def make_player(spec: str, effort: str = "medium") -> Player:
    """spec: claude[:<model>] | openai[:<model>] | gemini[:<model>] | deepseek[:<model>] | random[:<seed>]"""
    kind, _, arg = spec.partition(":")
    if kind == "random":
        return RandomPlayer(int(arg or 0))
    if kind not in KINDS:
        raise SystemExit(f"unknown player spec: {spec}")
    return KINDS[kind](arg, effort) if arg else KINDS[kind](effort=effort)
