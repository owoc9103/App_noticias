from __future__ import annotations

import os
from functools import lru_cache

from src.config import ROOT

GROQ_BASE_URL = "https://api.groq.com/openai/v1"
DEFAULT_CHAT_MODEL = "llama-3.1-8b-instant"
DEFAULT_SUMMARY_MODEL = "llama-3.3-70b-versatile"


def load_api_env() -> None:
    try:
        from dotenv import load_dotenv
    except ImportError:
        return
    load_dotenv(ROOT / ".env")


def groq_api_key() -> str:
    load_api_env()
    key = os.getenv("GROQ_API_KEY", "").strip()
    if key:
        return key
    try:
        import streamlit as st

        if "GROQ_API_KEY" in st.secrets:
            return str(st.secrets["GROQ_API_KEY"]).strip()
        groq = st.secrets.get("groq")
        if groq and "api_key" in groq:
            return str(groq["api_key"]).strip()
        if groq and "GROQ_API_KEY" in groq:
            return str(groq["GROQ_API_KEY"]).strip()
    except Exception:
        pass
    return ""


def chat_model() -> str:
    load_api_env()
    return os.getenv("GROQ_CHAT_MODEL", DEFAULT_CHAT_MODEL).strip() or DEFAULT_CHAT_MODEL


def summary_model() -> str:
    load_api_env()
    return os.getenv("GROQ_MODEL", DEFAULT_SUMMARY_MODEL).strip() or DEFAULT_SUMMARY_MODEL


@lru_cache(maxsize=1)
def _client(api_key: str):
    from openai import OpenAI

    return OpenAI(api_key=api_key, base_url=GROQ_BASE_URL)


def groq_chat(
    messages: list[dict[str, str]],
    model: str | None = None,
    max_tokens: int | None = None,
    temperature: float = 0.3,
    timeout: int = 40,
) -> str | None:
    """Llama a Groq con el cliente OpenAI-compatible (chat.completions).

    El snippet de Groq con client.responses.create y openai/gpt-oss-20b es
    para otro modelo. El asistente usa llama-3.1-8b-instant por chat.completions.
    """
    key = groq_api_key()
    if not key:
        return None
    try:
        client = _client(key)
        kwargs: dict = {
            "model": model or chat_model(),
            "messages": messages,
            "temperature": temperature,
            "timeout": timeout,
        }
        if max_tokens:
            kwargs["max_tokens"] = max_tokens
        response = client.chat.completions.create(**kwargs)
        return (response.choices[0].message.content or "").strip() or None
    except Exception:
        _client.cache_clear()
        return None
