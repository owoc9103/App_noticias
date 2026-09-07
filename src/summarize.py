from __future__ import annotations

import os
import re
from typing import Iterable

from src.config import HIGH_KEYWORDS, MEDIUM_KEYWORDS
from src.http_client import get
from src.models import NewsItem
from src.text_utils import fold, looks_english, split_sentences

NAV_NOISE = (
    "suscri",
    "cookie",
    "iniciar sesion",
    "acceso digital",
    "noticias economicas importantes",
    "compartir",
    "siguenos",
    "síguenos",
    "lee mas sobre",
    "lee más sobre",
)

LLM_SYSTEM = (
    "Eres editor de un noticiero económico en español para un laboratorio universitario "
    "en Cali, Colombia. Escribes con tono formal de noticias, claro y sobrio. "
    "No copies párrafos literales. No inventes cifras. "
    "Responde solo en español."
)


def _keyword_score(sentence: str) -> float:
    text = fold(sentence)
    high = sum(1 for w in HIGH_KEYWORDS if w in text)
    mid = sum(1 for w in MEDIUM_KEYWORDS if w in text)
    return 2.4 * high + mid + min(len(sentence) / 180, 1.2)


def _usable_lead(item: NewsItem) -> str:
    snippet = item.snippet or ""
    if any(noise in fold(snippet) for noise in NAV_NOISE):
        return item.title
    return snippet or item.title


def extractive_summary(text: str, max_sentences: int = 4) -> str:
    sentences = [
        sentence
        for sentence in split_sentences(text)
        if not any(noise in fold(sentence) for noise in NAV_NOISE)
    ]
    if not sentences:
        return ""
    ranked = sorted(
        enumerate(sentences),
        key=lambda pair: _keyword_score(pair[1]) + (0.35 if pair[0] < 2 else 0),
        reverse=True,
    )
    picked = sorted(ranked[:max_sentences], key=lambda pair: pair[0])
    return " ".join(s for _, s in picked)


def looks_spanish(text: str) -> bool:
    return not looks_english(text)


def translate_to_es(text: str) -> str:
    text = (text or "").strip()
    if not text or looks_spanish(text):
        return text
    chunks = _chunks(text, 450)
    out: list[str] = []
    for chunk in chunks:
        try:
            resp = get(
                "https://api.mymemory.translated.net/get",
                timeout=12,
                params={"q": chunk, "langpair": "en|es"},
            )
            resp.raise_for_status()
            translated = (resp.json().get("responseData") or {}).get("translatedText") or ""
            out.append(translated.strip())
        except Exception:
            out.append(chunk)
    joined = " ".join(out).strip()
    return joined or text


def _chunks(text: str, size: int) -> list[str]:
    words = text.split()
    bags: list[str] = []
    current: list[str] = []
    length = 0
    for word in words:
        current.append(word)
        length += len(word) + 1
        if length >= size:
            bags.append(" ".join(current))
            current, length = [], 0
    if current:
        bags.append(" ".join(current))
    return bags


def _llm_chat(messages: list[dict[str, str]]) -> str | None:
    groq = os.getenv("GROQ_API_KEY", "").strip()
    openai = os.getenv("OPENAI_API_KEY", "").strip()
    if groq:
        return _openai_compatible(
            "https://api.groq.com/openai/v1/chat/completions",
            groq,
            os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile"),
            messages,
        )
    if openai:
        return _openai_compatible(
            "https://api.openai.com/v1/chat/completions",
            openai,
            os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
            messages,
        )
    return None


def _openai_compatible(url: str, key: str, model: str, messages: list[dict[str, str]]) -> str | None:
    import requests

    try:
        resp = requests.post(
            url,
            headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
            json={"model": model, "temperature": 0.3, "messages": messages},
            timeout=40,
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"].strip()
    except Exception:
        return None


def summarize_item(item: NewsItem, use_llm: bool = True) -> str:
    raw = " ".join(part for part in (item.snippet, item.body) if part)
    base = extractive_summary(raw, max_sentences=4) or _usable_lead(item)
    base_es = translate_to_es(base)
    title_es = translate_to_es(item.title)

    if use_llm:
        polished = _llm_chat(
            [
                {"role": "system", "content": LLM_SYSTEM},
                {
                    "role": "user",
                    "content": (
                        f"Fuente: {item.source_name}\n"
                        f"Titular: {title_es}\n"
                        f"Material: {base_es[:1800]}\n\n"
                        "Redacta un resumen de 4 oraciones para un noticiero. "
                        "Incluye el dato más relevante. No agregues opinión."
                    ),
                },
            ]
        )
        if polished:
            item.summary_es = _clip_sentences(polished, 5)
            item.language = "es"
            return item.summary_es

    lead = f"Según {item.source_name}, {title_es.rstrip('.')}."
    extra = ""
    if base_es and fold(base_es) not in fold(title_es) and fold(title_es) not in fold(base_es):
        extra = base_es
    item.summary_es = _clip_sentences(f"{lead} {extra}".strip(), 5)
    item.language = "es"
    return item.summary_es


def _clip_sentences(text: str, n: int) -> str:
    parts = re.split(r"(?<=[\.!?])\s+", text.strip())
    return " ".join(p.strip() for p in parts[:n] if p.strip())


def summarize_many(items: Iterable[NewsItem], use_llm: bool = True) -> list[NewsItem]:
    for item in items:
        summarize_item(item, use_llm=use_llm)
    return list(items)
