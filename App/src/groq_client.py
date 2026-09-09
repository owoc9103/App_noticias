from __future__ import annotations

import os
from functools import lru_cache

from src.config import ROOT

GROQ_BASE_URL = "https://api.groq.com/openai/v1"
DEFAULT_CHAT_MODEL = "llama-3.1-8b-instant"
DEFAULT_SUMMARY_MODEL = "llama-3.3-70b-versatile"
CHAT_MODELS = (
    DEFAULT_CHAT_MODEL,
    DEFAULT_SUMMARY_MODEL,
    "llama-3.3-70b-versatile",
    "llama-3.1-8b-instant",
    "llama-3.2-3b-preview",
    "gemma2-9b-it",
    "openai/gpt-oss-20b",
)

_working_model: str | None = None


def _clean_key(value: object) -> str:
    return str(value or "").strip().strip('"').strip("'")


def load_api_env() -> None:
    try:
        from dotenv import load_dotenv
    except ImportError:
        return
    load_dotenv(ROOT / ".env")


def hydrate_streamlit_secrets() -> None:
    try:
        import streamlit as st

        raw = None
        if "GROQ_API_KEY" in st.secrets:
            raw = st.secrets["GROQ_API_KEY"]
        else:
            groq = st.secrets.get("groq")
            if groq:
                raw = groq.get("GROQ_API_KEY") or groq.get("api_key")
        key = _clean_key(raw)
        if key:
            os.environ["GROQ_API_KEY"] = key
        for name in ("GROQ_CHAT_MODEL", "GROQ_MODEL", "GROQ_WHISPER_MODEL"):
            if name in st.secrets:
                os.environ[name] = _clean_key(st.secrets[name])
    except Exception:
        pass


def groq_api_key() -> str:
    load_api_env()
    hydrate_streamlit_secrets()
    return _clean_key(os.getenv("GROQ_API_KEY", ""))


def chat_model() -> str:
    load_api_env()
    hydrate_streamlit_secrets()
    return _clean_key(os.getenv("GROQ_CHAT_MODEL", DEFAULT_CHAT_MODEL)) or DEFAULT_CHAT_MODEL


def summary_model() -> str:
    load_api_env()
    hydrate_streamlit_secrets()
    return _clean_key(os.getenv("GROQ_MODEL", DEFAULT_SUMMARY_MODEL)) or DEFAULT_SUMMARY_MODEL


def _model_candidates(preferred: str | None) -> list[str]:
    ordered: list[str] = []
    for name in (preferred, _working_model, chat_model(), summary_model(), *CHAT_MODELS):
        if name and name not in ordered:
            ordered.append(name)
    return ordered


@lru_cache(maxsize=1)
def _client(api_key: str):
    from openai import OpenAI

    return OpenAI(api_key=api_key, base_url=GROQ_BASE_URL)


def _chat_via_requests(
    key: str,
    model: str,
    messages: list[dict[str, str]],
    max_tokens: int | None,
    temperature: float,
    timeout: int,
) -> str | None:
    import requests

    payload: dict = {"model": model, "temperature": temperature, "messages": messages}
    if max_tokens:
        payload["max_tokens"] = max_tokens
    resp = requests.post(
        f"{GROQ_BASE_URL}/chat/completions",
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        json=payload,
        timeout=timeout,
    )
    resp.raise_for_status()
    return (resp.json()["choices"][0]["message"]["content"] or "").strip() or None


def groq_chat(
    messages: list[dict[str, str]],
    model: str | None = None,
    max_tokens: int | None = None,
    temperature: float = 0.3,
    timeout: int = 40,
) -> str | None:
    global _working_model
    key = groq_api_key()
    if not key:
        return None
    last_error: Exception | None = None
    for candidate in _model_candidates(model):
        try:
            text = _chat_via_requests(key, candidate, messages, max_tokens, temperature, timeout)
            if text:
                _working_model = candidate
                return text
        except Exception as exc:
            last_error = exc
            try:
                client = _client(key)
                kwargs: dict = {
                    "model": candidate,
                    "messages": messages,
                    "temperature": temperature,
                    "timeout": timeout,
                }
                if max_tokens:
                    kwargs["max_tokens"] = max_tokens
                response = client.chat.completions.create(**kwargs)
                text = (response.choices[0].message.content or "").strip()
                if text:
                    _working_model = candidate
                    return text
            except Exception as exc2:
                last_error = exc2
                _client.cache_clear()
                continue
    return None
