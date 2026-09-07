from __future__ import annotations

import asyncio
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from src.config import AUDIO_DIR, DEFAULT_VOICE, PODCAST_SIGN_OFF
from src.models import NewsItem

BOGOTA = ZoneInfo("America/Bogota")
ORDINALS = {
    1: "primera",
    2: "segunda",
    3: "tercera",
    4: "cuarta",
    5: "quinta",
    6: "sexta",
    7: "séptima",
}


def greeting(now: datetime | None = None) -> str:
    now = now or datetime.now(BOGOTA)
    hour = now.hour
    if hour < 12:
        return "Buenos días"
    if hour < 19:
        return "Buenas tardes"
    return "Buenas noches"


def build_script(items: list[NewsItem], recommendation: str, now: datetime | None = None) -> str:
    now = now or datetime.now(BOGOTA)
    meses = (
        "enero",
        "febrero",
        "marzo",
        "abril",
        "mayo",
        "junio",
        "julio",
        "agosto",
        "septiembre",
        "octubre",
        "noviembre",
        "diciembre",
    )
    fecha = f"{now.day} de {meses[now.month - 1]} de {now.year}"

    parts = [
        f"{greeting(now)}. Es {fecha}.",
        "Presentamos el top siete de las noticias económicas más relevantes de Colombia y el mundo, "
        "preparado por el DATA LAB de la Pontificia Universidad Javeriana Cali.",
        "El tono es de noticiero. Los resúmenes no reemplazan la nota original.",
    ]

    for idx, item in enumerate(items, start=1):
        ordinal = ORDINALS.get(idx, f"noticia número {idx}")
        title = item.title.rstrip(".")
        summary = (item.summary_es or item.snippet or title).strip()
        parts.append(f"La {ordinal} noticia. {item.source_name}. {title}. {summary}")

    parts.append("Cierre de edición. Recomendación financiera del día.")
    parts.append(recommendation)
    parts.append(PODCAST_SIGN_OFF)
    script = " ".join(p.strip() for p in parts if p.strip())
    if not script.endswith(PODCAST_SIGN_OFF):
        script = f"{script} {PODCAST_SIGN_OFF}"
    return script


def synthesize(script: str, voice: str = DEFAULT_VOICE) -> Path:
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(BOGOTA).strftime("%Y%m%d_%H%M%S")
    path = AUDIO_DIR / f"briefing_{stamp}.mp3"
    asyncio.run(_speak(script, voice, path))
    return path


async def _speak(script: str, voice: str, path: Path) -> None:
    import edge_tts

    communicate = edge_tts.Communicate(text=script, voice=voice, rate="-6%", pitch="-2Hz")
    await communicate.save(str(path))
