from __future__ import annotations

import asyncio
import os
import re
from pathlib import Path

from src.config import ASSETS_DIR, AUDIO_DIR
from src.groq_client import chat_model, groq_api_key, groq_chat, summary_model
from src.models import Briefing
from src.summarize import _llm_chat, _openai_compatible, looks_spanish
from src.text_utils import fold

CHAT_SYSTEM = (
    "Eres el asistente de voz de DATA-LAB (Javeriana Cali). "
    "Estás en una conversación hablada: 2 a 5 frases cortas, naturales, sin markdown, "
    "sin viñetas y sin URLs. Responde en el idioma de la persona. "
    "Puedes hablar del briefing económico del día SI te pasan ese contexto, "
    "y también de temas generales (explicar, conversar, aclarar). "
    "Si la pregunta es de coyuntura y hay briefing, usa esos hechos y no inventes cifras. "
    "Si la pregunta es general, responde con conocimiento general de forma breve. "
    "No des asesoría de inversión personalizada ni tickers para comprar."
)

STOP = {
    "que", "qué", "como", "cómo", "cual", "cuál", "donde", "dónde", "cuando",
    "the", "and", "for", "with", "from", "this", "that", "what", "about",
    "hoy", "este", "esta", "esto", "una", "uno", "por", "para", "del", "las",
    "los", "con", "hay", "tiene", "tell", "me", "please", "sobre", "pasa",
}

_VOICE = None


def looks_like_echo(heard: str, spoken: str) -> bool:
    a, b = fold(heard), fold(spoken)
    if not a or not b:
        return False
    if "groq_api_key" in a or "puedo conversar en general" in a:
        return True
    if a in b or b in a:
        return True
    words_a, words_b = set(a.split()), set(b.split())
    if len(words_a) >= 4 and len(words_a & words_b) / max(len(words_a), 1) >= 0.55:
        return True
    return False


def llm_available() -> bool:
    return bool(groq_api_key() or os.getenv("OPENAI_API_KEY", "").strip())


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


def local_answer(briefing: Briefing | None, question: str) -> str:
    if briefing is None:
        return "No pude conectar con el modelo en este momento. Intente de nuevo en unos segundos."
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
    if groq_api_key():
        for model in (chat_model(), summary_model()):
            text = groq_chat(
                messages,
                model=model,
                max_tokens=320,
                temperature=0.35,
                timeout=28,
            )
            if text:
                return text
    openai_key = os.getenv("OPENAI_API_KEY", "").strip()
    if openai_key:
        text = _openai_compatible(
            "https://api.openai.com/v1/chat/completions",
            openai_key,
            os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
            messages,
            max_tokens=220,
            temperature=0.2,
            timeout=22,
        )
        if text:
            return text
    return _llm_chat(messages, max_tokens=220, temperature=0.2, timeout=22)


def answer_question(briefing: Briefing | None, question: str, history: list[dict[str, str]] | None = None) -> str:
    question = (question or "").strip()
    if not question:
        return "Dígame, lo escucho."
    fallback = local_answer(briefing, question)
    if not llm_available():
        return fallback
    messages = [{"role": "system", "content": CHAT_SYSTEM}]
    if briefing and briefing.items:
        messages.append(
            {
                "role": "user",
                "content": (
                    "Contexto opcional del briefing de hoy. Úsalo si la pregunta es de mercados o Colombia; "
                    f"si es general, ignóralo.\n{briefing_context(briefing)}"
                ),
            }
        )
        messages.append(
            {
                "role": "assistant",
                "content": "Listo. Puedo hablar del briefing o de lo que quiera, en voz.",
            }
        )
    for turn in (history or [])[-8:]:
        if turn.get("q"):
            messages.append({"role": "user", "content": turn["q"]})
        if turn.get("a"):
            messages.append({"role": "assistant", "content": turn["a"]})
    messages.append({"role": "user", "content": question})
    polished = _chat(messages)
    return polished or fallback


def transcribe_audio(data: bytes, mime: str = "audio/wav") -> str | None:
    groq = groq_api_key()
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


def voice_ask(key: str = "jl_voice", reply: str = "", speak_id: int = 0, loop: bool = True):
    global _VOICE
    import streamlit.components.v1 as components

    if _VOICE is None:
        _VOICE = components.declare_component("jl_voice_ask", path=str(ASSETS_DIR / "voice_ask"))
    try:
        return _VOICE(
            reply=reply or "",
            speak_id=int(speak_id or 0),
            loop=bool(loop),
            key=key,
            default=None,
        )
    except Exception:
        return None
