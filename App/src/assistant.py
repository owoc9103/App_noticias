from __future__ import annotations

import asyncio
import os
import re
from pathlib import Path

from src.config import ASSETS_DIR, AUDIO_DIR
from src.models import Briefing
from src.summarize import _llm_chat, _openai_compatible, looks_spanish
from src.text_utils import fold

CHAT_SYSTEM = (
    "Eres el asistente de voz de DATA-LAB Market Briefing (Javeriana Cali). "
    "Solo usas el briefing del día que te pasan. Responde en 2 a 4 frases, "
    "tono de noticiero financiero. Responde en el idioma de la pregunta. "
    "Si el dato no está en el briefing, dilo y no inventes cifras ni recomendaciones "
    "de compra o venta. Es lectura académica de coyuntura, no asesoría de inversión."
)

STOP = {
    "que", "qué", "como", "cómo", "cual", "cuál", "donde", "dónde", "cuando",
    "the", "and", "for", "with", "from", "this", "that", "what", "about",
    "hoy", "este", "esta", "esto", "una", "uno", "por", "para", "del", "las",
    "los", "con", "hay", "tiene", "tell", "me", "please", "sobre", "pasa",
}

_VOICE = None


def llm_available() -> bool:
    return bool(os.getenv("GROQ_API_KEY", "").strip() or os.getenv("OPENAI_API_KEY", "").strip())


def takeaways_of(briefing: Briefing) -> list[str]:
    raw = [str(line).strip().lstrip("•- ") for line in (briefing.takeaways or []) if str(line).strip()]
    if raw:
        return raw[:3]
    rec = briefing.recommendation or ""
    lines = [line.strip().lstrip("•- ") for line in rec.splitlines() if line.strip()]
    return [
        line
        for line in lines
        if "asesoría" not in line.lower() and "asesoria" not in line.lower()
    ][:3]


def briefing_context(briefing: Briefing) -> str:
    when = briefing.generated_at.strftime("%Y-%m-%d %H:%M") if briefing.generated_at else "hoy"
    lines = [
        f"Briefing DATA-LAB {when}. Perfil {briefing.profile}.",
        "Key takeaways:",
        *[f"- {point}" for point in takeaways_of(briefing)],
    ]
    if briefing.market:
        quotes = ", ".join(f"{k}: {v}" for k, v in briefing.market.items() if k != "Fuente")
        if quotes:
            lines.append(f"Mercado: {quotes}")
    lines.append("Noticias:")
    for idx, item in enumerate(briefing.items, start=1):
        tags = ", ".join(item.tags) if item.tags else ""
        lines.append(
            f"{idx}. [{item.source_name} | {item.category} | {item.language or 'es'} | {tags}] "
            f"{item.title}. {item.summary_es}"
        )
    return "\n".join(lines)


def local_answer(briefing: Briefing, question: str) -> str:
    q = fold(question)
    takes = takeaways_of(briefing)
    if any(word in q for word in ("takeaway", "clave", "resumen", "conclusion", "conclusión", "sintesis", "síntesis")):
        if takes:
            return " ".join(takes)
    if briefing.market and any(word in q for word in ("mercado", "trm", "brent", "wti", "tes", "indice", "índice")):
        quotes = ", ".join(f"{k} {v}" for k, v in briefing.market.items() if k != "Fuente")
        if quotes:
            return f"En el tablero de mercado: {quotes}."
    tokens = [tok for tok in re.findall(r"[a-záéíóúñ0-9]{3,}", q) if tok not in STOP]
    scored: list[tuple[int, object]] = []
    for item in briefing.items:
        blob = fold(f"{item.title} {item.summary_es} {' '.join(item.tags)} {item.source_name}")
        hits = sum(1 for tok in tokens if tok in blob)
        if item.category == "nacional" and any(tok in q for tok in ("colombia", "peso", "banrep", "dane")):
            hits += 1
        scored.append((hits, item))
    scored.sort(key=lambda row: -row[0])
    if scored and scored[0][0] > 0:
        chosen = [item for hits, item in scored if hits == scored[0][0]][:2]
        parts = [(item.summary_es or item.title).strip() for item in chosen]
        return " ".join(part for part in parts if part)
    if takes:
        return (
            "Eso no aparece con claridad en el briefing. Lo más relevante hoy: "
            + " ".join(takes)
        )
    return "Eso no aparece en el briefing de hoy. Pregunte por las noticias, el dólar, las tasas o los takeaways."


def _chat(messages: list[dict[str, str]]) -> str | None:
    groq = os.getenv("GROQ_API_KEY", "").strip()
    openai = os.getenv("OPENAI_API_KEY", "").strip()
    attempts: list[tuple[str, str, str]] = []
    if groq:
        chat_model = os.getenv("GROQ_CHAT_MODEL", "llama-3.1-8b-instant")
        summary_model = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile")
        attempts.append(("https://api.groq.com/openai/v1/chat/completions", groq, chat_model))
        if summary_model != chat_model:
            attempts.append(("https://api.groq.com/openai/v1/chat/completions", groq, summary_model))
    if openai:
        attempts.append(
            (
                "https://api.openai.com/v1/chat/completions",
                openai,
                os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
            )
        )
    for url, key, model in attempts:
        text = _openai_compatible(
            url,
            key,
            model,
            messages,
            max_tokens=220,
            temperature=0.2,
            timeout=22,
        )
        if text:
            return text
    return _llm_chat(messages, max_tokens=220, temperature=0.2, timeout=22)


def answer_question(briefing: Briefing, question: str, history: list[dict[str, str]] | None = None) -> str:
    question = (question or "").strip()
    if not question:
        return "¿Sobre qué parte del briefing quiere preguntar?"
    fallback = local_answer(briefing, question)
    if not llm_available():
        return fallback
    messages = [
        {"role": "system", "content": CHAT_SYSTEM},
        {"role": "user", "content": f"Briefing:\n{briefing_context(briefing)}"},
    ]
    for turn in (history or [])[-4:]:
        if turn.get("q"):
            messages.append({"role": "user", "content": turn["q"]})
        if turn.get("a"):
            messages.append({"role": "assistant", "content": turn["a"]})
    messages.append({"role": "user", "content": question})
    polished = _chat(messages)
    return polished or fallback


def transcribe_audio(data: bytes, mime: str = "audio/wav") -> str | None:
    groq = os.getenv("GROQ_API_KEY", "").strip()
    if not groq or not data:
        return None
    import requests

    suffix = ".webm"
    if "mp3" in mime:
        suffix = ".mp3"
    elif "wav" in mime:
        suffix = ".wav"
    elif "ogg" in mime:
        suffix = ".ogg"
    elif "mp4" in mime or "m4a" in mime:
        suffix = ".m4a"
    model = os.getenv("GROQ_WHISPER_MODEL", "whisper-large-v3-turbo")
    try:
        resp = requests.post(
            "https://api.groq.com/openai/v1/audio/transcriptions",
            headers={"Authorization": f"Bearer {groq}"},
            files={"file": (f"ask{suffix}", data, mime or "application/octet-stream")},
            data={"model": model, "temperature": "0"},
            timeout=30,
        )
        resp.raise_for_status()
        text = (resp.json().get("text") or "").strip()
        return text or None
    except Exception:
        return None


def _run_async(coro):
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        return asyncio.run(coro)

    def runner():
        return asyncio.run(coro)

    from concurrent.futures import ThreadPoolExecutor

    with ThreadPoolExecutor(max_workers=1) as pool:
        return pool.submit(runner).result(timeout=25)


async def _edge_save(text: str, voice: str, dest: Path) -> None:
    import edge_tts

    await edge_tts.Communicate(text=text, voice=voice, rate="+8%").save(str(dest))


def synthesize_reply(text: str) -> Path | None:
    text = re.sub(r"\s+", " ", (text or "").strip())
    if not text:
        return None
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    dest = AUDIO_DIR / "assistant_reply.mp3"
    spanish = looks_spanish(text)
    voice = "es-CO-GonzaloNeural" if spanish else "en-US-GuyNeural"
    lang = "es" if spanish else "en"
    try:
        _run_async(_edge_save(text[:900], voice, dest))
        if dest.exists() and dest.stat().st_size > 400:
            return dest
    except Exception:
        pass
    try:
        from gtts import gTTS

        gTTS(text=text[:900], lang=lang).save(str(dest))
        if dest.exists() and dest.stat().st_size > 400:
            return dest
    except Exception:
        return None
    return dest if dest.exists() and dest.stat().st_size > 400 else None


def voice_ask(key: str = "jl_voice"):
    global _VOICE
    import streamlit.components.v1 as components

    if _VOICE is None:
        _VOICE = components.declare_component("jl_voice_ask", path=str(ASSETS_DIR / "voice_ask"))
    try:
        return _VOICE(key=key, default=None)
    except Exception:
        return None
