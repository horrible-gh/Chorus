"""context_meter.py — server-side context usage estimator (T080 Phase 1)

Estimates how much of the model's context window the assembled prompt consumes.
Uses tiktoken for token counting with provider-specific encodings and overhead
margins, plus a static model catalog for context window sizes.
"""
from __future__ import annotations

from pathlib import Path
from typing import Optional

import yaml
import tiktoken

_CATALOG_PATH = Path(__file__).resolve().parent.parent / "data" / "model_catalog.yaml"
_catalog_cache: Optional[dict] = None

_WARN_RATIO = 0.60
_COMPRESS_SOON_RATIO = 0.80
_BLOCK_RATIO = 0.95

_RUNNER_ENCODING: dict[str, str] = {
    "claude": "cl100k_base",
    "codex": "o200k_base",
    "gemini": "o200k_base",
    "copilot": "o200k_base",
}

_RUNNER_MARGIN: dict[str, float] = {
    "claude": 1.15,
    "codex": 1.08,
    "gemini": 1.20,
    "copilot": 1.25,
}

_RUNNER_FIXED_OVERHEAD = 2000

_DEFAULT_CONTEXT_WINDOW = 128000


def load_model_catalog() -> dict:
    """Load and cache model_catalog.yaml."""
    global _catalog_cache
    if _catalog_cache is None:
        with open(_CATALOG_PATH, encoding="utf-8") as fh:
            _catalog_cache = yaml.safe_load(fh) or {}
    return _catalog_cache


def get_context_window(runner: str, model: str) -> int:
    """Return context window token count for runner/model.

    Falls back to copilot default if runner or model is not found.
    """
    catalog = load_model_catalog()
    models_section = catalog.get("models") or {}
    runner_section = models_section.get(runner) or {}
    entry = runner_section.get(model)
    if entry and isinstance(entry, dict) and entry.get("context_window"):
        return int(entry["context_window"])
    # Fallback: copilot default
    default_entry = (models_section.get("copilot") or {}).get("default") or {}
    return int(default_entry.get("context_window") or _DEFAULT_CONTEXT_WINDOW)


def estimate_tokens(prompt: str, runner: str, model: str) -> int:  # noqa: ARG001
    """Estimate token count for prompt with runner-specific encoding and margin.

    The model parameter is accepted for future per-model overrides but is not
    currently used in the margin calculation.

    Encoding choice and margin rationale (from NR028):
      claude  : cl100k_base + 15% + 2000  (Claude Code adds system/hooks overhead)
      codex   : o200k_base  + 8%  + 2000
      gemini  : o200k_base  + 20% + 2000
      copilot : o200k_base  + 25% + 2000  (large overhead; exact limit unclear)
    """
    enc_name = _RUNNER_ENCODING.get(runner, "o200k_base")
    margin = _RUNNER_MARGIN.get(runner, 1.25)
    try:
        enc = tiktoken.get_encoding(enc_name)
    except Exception:
        # If encoding lookup fails, use a safe character-based estimate
        return int(len(prompt) / 3.5 * margin) + _RUNNER_FIXED_OVERHEAD
    raw = len(enc.encode(prompt))
    return int(raw * margin) + _RUNNER_FIXED_OVERHEAD


def _classify_status(ratio: float) -> str:
    if ratio >= _BLOCK_RATIO:
        return "BLOCK_OR_COMPRESS_NOW"
    if ratio >= _COMPRESS_SOON_RATIO:
        return "COMPRESS_SOON"
    if ratio >= _WARN_RATIO:
        return "WARN"
    return "OK"


def compute_context_usage(prompt: str, runner: str, model: str) -> dict:
    """Compute context usage estimate for the assembled prompt.

    Returns:
        {
            "estimated_input_tokens": int,
            "context_window": int,
            "context_ratio": float,
            "context_status": "OK" | "WARN" | "COMPRESS_SOON" | "BLOCK_OR_COMPRESS_NOW"
        }
    """
    estimated = estimate_tokens(prompt, runner, model)
    window = get_context_window(runner, model)
    ratio = round(estimated / window, 4) if window > 0 else 0.0
    return {
        "estimated_input_tokens": estimated,
        "context_window": window,
        "context_ratio": ratio,
        "context_status": _classify_status(ratio),
    }
