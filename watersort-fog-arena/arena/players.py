"""Players. Every LLM gets the same system prompt and the same conversation: the whole session is ONE multi-turn chat,
so everything the model saw and said earlier (boards, its own reasons, failed attempts) is in its context. Only the
visible reply text is carried forward; hidden reasoning is not replayed, for any vendor. Reasoning depth is the same
word ("medium" / "high") for everyone.

Effort "off" means "thinking switched off, or as close as the API allows" (probed 2026-11-17):
  DeepSeek   thinking disabled
  Gemini     thinking_budget 0
  OpenAI     cannot be switched off for gpt-6.2-astra ('none' and 'minimal' are rejected) → lowest level, "low"
  Anthropic  cannot be switched off for claude-fable-5-2 (thinking "disabled" is rejected) → lowest level, "low"
Each player's `sent` attribute says what was actually sent; it goes into the log header.
"""
from __future__ import annotations

import os
import random
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone

MAX_OUT = 16000
CLAUDE_MAX_OUT = 64000


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
    sent = ""   # the thinking setting actually sent to the API

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
        self.model, self.effort = model, ("low" if effort == "off" else effort)
        self.sent = f"output_config.effort={self.effort}"
        self.name = f"Claude ({model})"

    def chat(self, system, messages) -> Reply:
        import anthropic

        t0, at = time.time(), _now()
        try:
            # Thinking cannot be switched off for this model and counts against max_tokens. With the 16000 cap the
            # official run had 10 replies cut off before any command was written (turns 128-158), so from turn 159 on
            # the cap is 64000, streamed to stay clear of HTTP timeouts.
            with self.client.messages.stream(
                model=self.model, max_tokens=CLAUDE_MAX_OUT, system=system, output_config={"effort": self.effort},
                cache_control={"type": "ephemeral"}, messages=messages,
            ) as stream:
                r = stream.get_final_message()
        except anthropic.APIError as e:
            return Reply("", time.time() - t0, error=f"{type(e).__name__}: {e}", at=at)
        if r.stop_reason == "refusal":
            return Reply("", time.time() - t0, error="refusal", at=at)
        u = r.usage
        read, write = u.cache_read_input_tokens or 0, u.cache_creation_input_tokens or 0
        usage = {"input": u.input_tokens + read + write, "cached": read, "cache_write": write, "output": u.output_tokens}
        if r.stop_reason == "max_tokens":
            usage["cut_off"] = True
        text = "".join(b.text for b in r.content if b.type == "text")
        return Reply(text, time.time() - t0, usage, at=at)


class OpenAIPlayer(Player):
    """OpenAI, Responses API with reasoning effort. Prompt caching is automatic."""

    vendor = "OpenAI"

    def __init__(self, model: str = "gpt-6.2-astra", effort: str = "medium"):
        import openai

        self.client = openai.OpenAI()
        self.model, self.effort = model, ("low" if effort == "off" else effort)
        self.sent = f"reasoning.effort={self.effort}"
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

        from google.genai import types

        # a request that has not answered in 5 minutes is treated as stuck and retried by the session (seen 2026-11-17:
        # the first high-effort call sat for 9 minutes without returning)
        # Two ways in, same model. With GEMINI_VERTEX_PROJECT set: Vertex AI on that Google Cloud project, signed in
        # through Application Default Credentials (`gcloud auth application-default login`), location "global"; this
        # route takes thinking levels only (no thinking_budget). Otherwise: the AI Studio key GEMINI_API_KEY.
        opts = types.HttpOptions(timeout=300_000)
        self.vertex = os.environ.get("GEMINI_VERTEX_PROJECT")
        if self.vertex:
            if effort == "off":
                raise SystemExit("Vertex AI rejects thinking_budget for this model; use --effort low (the lowest level)")
            self.client = genai.Client(vertexai=True, project=self.vertex, location="global", http_options=opts)
        else:
            self.client = genai.Client(api_key=os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY"), http_options=opts)
        self.model, self.effort = model, effort
        self.thinking = types.ThinkingConfig(thinking_budget=0) if effort == "off" else types.ThinkingConfig(thinking_level=effort)
        self.sent = ("thinking_budget=0" if effort == "off" else f"thinking_level={effort}") + (" (Vertex AI)" if self.vertex else " (AI Studio)")
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
                    thinking_config=self.thinking,
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
        self.extra = {"thinking": {"type": "disabled"}} if effort == "off" else {"thinking": {"type": "enabled"}, "reasoning_effort": effort}
        self.sent = "thinking disabled" if effort == "off" else f"thinking enabled, reasoning_effort={effort}"
        self.name = f"DeepSeek ({model})"

    def chat(self, system, messages) -> Reply:
        import openai

        t0, at = time.time(), _now()
        try:
            r = self.client.chat.completions.create(
                model=self.model, max_tokens=24000,
                messages=[{"role": "system", "content": system}, *messages],
                extra_body=self.extra,
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
