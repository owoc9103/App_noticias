from __future__ import annotations

import asyncio
import re
import subprocess
import tempfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from src.config import AUDIO_DIR, DEFAULT_READER, DEFAULT_VOICE, PODCAST_SIGN_OFF
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
        f"{greeting(now)}. Desde Cali, DATA LAB de la Javeriana.",
        f"Es {fecha}.",
        "Presentamos el top siete de las noticias económicas más relevantes de Colombia y el mundo.",
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


@dataclass
class _Cue:
    text: str
    pause_ms: int
    rate: str
    pitch: str


def _cues_from_script(script: str, reader_key: str = DEFAULT_READER) -> list[_Cue]:
    """Parte el mismo guion en frases de locución, sin cambiar las palabras."""
    body_rate, body_pitch = ("-11%", "-3Hz") if reader_key == "hombre" else ("-9%", "+1Hz")
    title_rate, title_pitch = ("-16%", "-4Hz") if reader_key == "hombre" else ("-14%", "-1Hz")
    close_rate, close_pitch = ("-13%", "-5Hz") if reader_key == "hombre" else ("-12%", "-2Hz")

    sentences = [part.strip() for part in re.split(r"(?<=[\.!?…])\s+", script.strip()) if part.strip()]
    cues: list[_Cue] = []
    for sentence in sentences:
        low = sentence.lower()
        pause = 420
        rate, pitch = body_rate, body_pitch
        if low.startswith(("buenos días", "buenas tardes", "buenas noches")):
            pause = 620
        elif low.startswith("es ") and " de " in low:
            pause = 700
        elif "presentamos el top" in low or "data lab" in low:
            pause = 780
        elif re.match(r"^la (primera|segunda|tercera|cuarta|quinta|sexta|séptima|noticia)", low):
            pause = 380
            rate, pitch = title_rate, title_pitch
        elif low.startswith("según "):
            pause = 520
        elif "cierre de edición" in low or "recomendación financiera" in low:
            pause = 900
            rate, pitch = title_rate, title_pitch
        elif PODCAST_SIGN_OFF.lower() in low:
            pause = 250
            rate, pitch = close_rate, close_pitch
        elif len(sentence) > 180:
            pause = 560
        cues.append(_Cue(sentence, pause, rate, pitch))
    return cues or [_Cue(script, 300, body_rate, body_pitch)]


def _pack_cues(cues: list[_Cue]) -> list[_Cue]:
    """Agrupa frases en bloques de noticiero para pocas llamadas de voz."""
    if not cues:
        return cues
    packs: list[_Cue] = []
    bucket: list[_Cue] = []

    def flush(pause: int) -> None:
        if not bucket:
            return
        last = bucket[-1]
        packs.append(_Cue(" ".join(item.text for item in bucket), pause, last.rate, last.pitch))
        bucket.clear()

    for cue in cues:
        low = cue.text.lower()
        new_block = bool(
            re.match(r"^la (primera|segunda|tercera|cuarta|quinta|sexta|séptima)\b", low)
            or "cierre de edición" in low
            or PODCAST_SIGN_OFF.lower() in low
        )
        if new_block:
            flush(520)
        bucket.append(cue)
        if PODCAST_SIGN_OFF.lower() in low:
            flush(180)
    flush(280)
    return packs or cues


def synthesize(
    script: str,
    voice: str = DEFAULT_VOICE,
    reader_key: str = DEFAULT_READER,
) -> Path:
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(BOGOTA).strftime("%Y%m%d_%H%M%S")
    errors: list[str] = []

    cues = _pack_cues(_cues_from_script(script, reader_key))
    mp3 = AUDIO_DIR / f"briefing_{stamp}.mp3"
    engines = (_speak_edge, _speak_gtts) if _edge_reachable() else (_speak_gtts, _speak_edge)
    for engine in engines:
        try:
            if engine is _speak_edge:
                engine(cues, voice, mp3)
            else:
                engine(cues, mp3)
            if mp3.exists() and mp3.stat().st_size > 500:
                return mp3
            errors.append(f"{engine.__name__} no produjo un archivo válido")
        except Exception as exc:
            errors.append(f"{engine.__name__}: {exc}")

    wav = AUDIO_DIR / f"briefing_{stamp}.wav"
    try:
        _speak_windows(cues, wav, reader_key)
        if wav.exists() and wav.stat().st_size > 500:
            return wav
        errors.append("La voz local de Windows no produjo un archivo válido")
    except Exception as exc:
        errors.append(f"Voz local de Windows: {exc}")

    raise RuntimeError(
        "No se pudo generar el podcast. "
        + " | ".join(errors)
        + ". Revise la red o instale una voz en español en Windows."
    )


def _edge_reachable() -> bool:
    import socket

    previous = socket.getdefaulttimeout()
    try:
        socket.setdefaulttimeout(1.2)
        socket.getaddrinfo("speech.platform.bing.com", 443)
        return True
    except OSError:
        return False
    finally:
        socket.setdefaulttimeout(previous)


def _ffmpeg() -> str | None:
    try:
        import imageio_ffmpeg

        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return None


def _run_ffmpeg(args: list[str]) -> None:
    exe = _ffmpeg()
    if not exe:
        raise RuntimeError("ffmpeg no está disponible")
    subprocess.run(
        [exe, "-y", *args],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def _silence_mp3(path: Path, ms: int = 400) -> Path:
    cached = AUDIO_DIR / f"_silence_{int(ms)}.mp3"
    if cached.exists() and cached.stat().st_size > 200:
        if path != cached:
            path.write_bytes(cached.read_bytes())
        return cached
    seconds = max(0.18, ms / 1000)
    _run_ffmpeg(
        [
            "-f",
            "lavfi",
            "-i",
            "anullsrc=channel_layout=mono:sample_rate=24000",
            "-t",
            f"{seconds:.2f}",
            "-q:a",
            "6",
            str(cached),
        ]
    )
    if path != cached and cached.exists():
        path.write_bytes(cached.read_bytes())
    return cached


def _join_mp3(parts: list[Path], dest: Path) -> None:
    exe = _ffmpeg()
    if exe and len(parts) > 1:
        listing = dest.with_suffix(".concat.txt")
        listing.write_text(
            "\n".join(f"file '{part.resolve().as_posix()}'" for part in parts),
            encoding="utf-8",
        )
        try:
            _run_ffmpeg(
                ["-f", "concat", "-safe", "0", "-i", str(listing), "-q:a", "5", str(dest)]
            )
            listing.unlink(missing_ok=True)
            if dest.exists() and dest.stat().st_size > 500:
                return
        except Exception:
            listing.unlink(missing_ok=True)
    dest.write_bytes(b"".join(part.read_bytes() for part in parts))


def _soften_mp3(path: Path) -> None:
    """Evita cortes secos al inicio y al final de cada frase."""
    if not _ffmpeg():
        return
    tmp = path.with_name(path.stem + "_soft.mp3")
    try:
        _run_ffmpeg(
            [
                "-i",
                str(path),
                "-af",
                "afade=t=in:st=0:d=0.05,afade=t=out:d=0.08",
                "-q:a",
                "5",
                str(tmp),
            ]
        )
        if tmp.exists() and tmp.stat().st_size > 400:
            tmp.replace(path)
        else:
            tmp.unlink(missing_ok=True)
    except Exception:
        tmp.unlink(missing_ok=True)


def _speak_edge(cues: list[_Cue], voice: str, path: Path) -> None:
    asyncio.run(_speak_edge_async(cues, voice, path))


async def _speak_edge_async(cues: list[_Cue], voice: str, path: Path) -> None:
    import edge_tts

    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        clips: list[Path] = []
        for idx, cue in enumerate(cues):
            clip = folder / f"c{idx:03d}.mp3"
            communicate = edge_tts.Communicate(
                text=cue.text,
                voice=voice,
                rate=cue.rate,
                pitch=cue.pitch,
            )
            await communicate.save(str(clip))
            clips.append(clip)
            if cue.pause_ms:
                hush = folder / f"s{idx:03d}.mp3"
                try:
                    _silence_mp3(hush, min(cue.pause_ms, 450))
                    clips.append(hush)
                except Exception:
                    pass
        _join_mp3(clips, path)


def _speak_gtts(cues: list[_Cue], path: Path) -> None:
    from concurrent.futures import ThreadPoolExecutor

    from gtts import gTTS

    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)

        def render(idx_cue: tuple[int, _Cue]) -> Path:
            idx, cue = idx_cue
            clip = folder / f"c{idx:03d}.mp3"
            gTTS(text=cue.text, lang="es", tld="com.co").save(str(clip))
            return clip

        with ThreadPoolExecutor(max_workers=min(8, max(2, len(cues)))) as pool:
            voice_clips = list(pool.map(render, enumerate(cues)))

        hush = folder / "pause.mp3"
        try:
            _silence_mp3(hush, 420)
        except Exception:
            hush = None

        clips: list[Path] = []
        for idx, clip in enumerate(voice_clips):
            clips.append(clip)
            if hush and idx < len(voice_clips) - 1:
                clips.append(hush)
        _join_mp3(clips, path)


def _speak_windows(cues: list[_Cue], path: Path, reader_key: str) -> None:
    import pyttsx3

    engine = pyttsx3.init()
    voices = engine.getProperty("voices") or []
    chosen = _pick_windows_voice(voices, reader_key)
    if chosen:
        engine.setProperty("voice", chosen)
    engine.setProperty("rate", 148)
    spoken = " ... ".join(cue.text for cue in cues)
    engine.save_to_file(spoken, str(path))
    engine.runAndWait()
    engine.stop()


def _pick_windows_voice(voices: list, reader_key: str) -> str | None:
    want_female = reader_key == "mujer"
    scored: list[tuple[int, str]] = []
    for voice in voices:
        name = f"{getattr(voice, 'name', '')} {getattr(voice, 'id', '')}".lower()
        gender = str(getattr(voice, "gender", "")).lower()
        score = 0
        if any(bit in name for bit in ("es-es", "es-mx", "es-co", "spanish", "español", "sabina", "helena", "pablo", "jorge")):
            score += 5
        if want_female and any(bit in name + gender for bit in ("female", "mujer", "sabina", "helena", "zira", "salome")):
            score += 3
        if not want_female and any(bit in name + gender for bit in ("male", "hombre", "pablo", "jorge", "david", "gonzalo")):
            score += 3
        if score:
            scored.append((score, voice.id))
    scored.sort(reverse=True)
    if scored:
        return scored[0][1]
    return voices[0].id if voices else None
