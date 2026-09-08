from __future__ import annotations

import asyncio
import re
import subprocess
import tempfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from src.config import AUDIO_DIR, DEFAULT_READER, DEFAULT_VOICE, PODCAST_SIGN_OFF, READERS
from src.models import NewsItem
from src.summarize import detect_item_language
from src.text_utils import looks_english

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
EN_ORDINALS = {
    1: "first",
    2: "second",
    3: "third",
    4: "fourth",
    5: "fifth",
    6: "sixth",
    7: "seventh",
}


def greeting(now: datetime | None = None) -> str:
    now = now or datetime.now(BOGOTA)
    hour = now.hour
    if hour < 12:
        return "Buenos días"
    if hour < 19:
        return "Buenas tardes"
    return "Buenas noches"


def item_is_english(item: NewsItem) -> bool:
    return detect_item_language(item) == "en"


def build_script(
    items: list[NewsItem],
    recommendation: str,
    now: datetime | None = None,
    reader_key: str = DEFAULT_READER,
) -> str:
    cues = build_cues(items, recommendation, now=now, reader_key=reader_key)
    script = " ".join(cue.text.strip() for cue in cues if cue.text.strip())
    if not script.endswith(PODCAST_SIGN_OFF):
        script = f"{script} {PODCAST_SIGN_OFF}"
    return script


@dataclass
class _Cue:
    text: str
    pause_ms: int
    rate: str
    pitch: str
    lang: str = "es"


def _tone(reader_key: str) -> tuple[tuple[str, str], tuple[str, str], tuple[str, str]]:
    if reader_key == "hombre":
        return ("-11%", "-3Hz"), ("-16%", "-4Hz"), ("-13%", "-5Hz")
    return ("-9%", "+1Hz"), ("-14%", "-1Hz"), ("-12%", "-2Hz")


def english_voice(reader_key: str) -> str:
    info = READERS.get(reader_key, READERS[DEFAULT_READER])
    return str(info.get("en_voice") or "am_michael")


def _edge_pair(reader_key: str) -> tuple[str, str]:
    info = READERS.get(reader_key, READERS[DEFAULT_READER])
    return (
        str(info.get("edge_voice") or "es-CO-GonzaloNeural"),
        str(info.get("edge_en") or "en-US-GuyNeural"),
    )


def build_cues(
    items: list[NewsItem],
    recommendation: str,
    now: datetime | None = None,
    reader_key: str = DEFAULT_READER,
) -> list[_Cue]:
    now = now or datetime.now(BOGOTA)
    meses = (
        "enero", "febrero", "marzo", "abril", "mayo", "junio",
        "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
    )
    fecha = f"{now.day} de {meses[now.month - 1]} de {now.year}"
    body, title, close = _tone(reader_key)
    cues = [
        _Cue(f"{greeting(now)}. Desde Cali, DATA LAB de la Javeriana.", 620, *body, "es"),
        _Cue(f"Es {fecha}.", 700, *body, "es"),
        _Cue(
            "Presentamos el top siete. Colombia en español; el mundo, en el idioma original.",
            780,
            *body,
            "es",
        ),
    ]
    for idx, item in enumerate(items, start=1):
        title_text = item.title.rstrip(".")
        summary = (item.summary_es or item.snippet or title_text).strip()
        if item_is_english(item):
            ordinal = EN_ORDINALS.get(idx, f"number {idx}")
            cues.append(
                _Cue(
                    f"Story {ordinal}. {item.source_name}. {title_text}. {summary}",
                    380,
                    *title,
                    "en",
                )
            )
        else:
            ordinal = ORDINALS.get(idx, f"noticia número {idx}")
            cues.append(
                _Cue(
                    f"La {ordinal} noticia. {item.source_name}. {title_text}. {summary}",
                    380,
                    *title,
                    "es",
                )
            )
    cues.append(_Cue("Cierre de edición. Recomendación financiera del día.", 900, *title, "es"))
    if recommendation.strip():
        reco_lang = "en" if looks_english(recommendation) else "es"
        cues.append(_Cue(recommendation.strip(), 560, *body, reco_lang))
    cues.append(_Cue(PODCAST_SIGN_OFF, 250, *close, "es"))
    return cues


def _cues_from_script(script: str, reader_key: str = DEFAULT_READER) -> list[_Cue]:
    """Parte el mismo guion en frases de locución, sin cambiar las palabras."""
    body, title, close = _tone(reader_key)
    sentences = [part.strip() for part in re.split(r"(?<=[\.!?…])\s+", script.strip()) if part.strip()]
    cues: list[_Cue] = []
    for sentence in sentences:
        low = sentence.lower()
        pause = 420
        rate, pitch = body
        lang = "en" if looks_english(sentence) else "es"
        if low.startswith(("buenos días", "buenas tardes", "buenas noches")):
            pause = 620
            lang = "es"
        elif low.startswith("es ") and " de " in low:
            pause = 700
            lang = "es"
        elif "presentamos el top" in low or "data lab" in low:
            pause = 780
            lang = "es"
        elif re.match(r"^la (primera|segunda|tercera|cuarta|quinta|sexta|séptima|noticia)", low):
            pause = 380
            rate, pitch = title
            lang = "es"
        elif re.match(r"^story (first|second|third|fourth|fifth|sixth|seventh|number)", low):
            pause = 380
            rate, pitch = title
            lang = "en"
        elif low.startswith("según "):
            pause = 520
        elif "cierre de edición" in low or "recomendación financiera" in low:
            pause = 900
            rate, pitch = title
            lang = "es"
        elif PODCAST_SIGN_OFF.lower() in low:
            pause = 250
            rate, pitch = close
            lang = "es"
        elif len(sentence) > 180:
            pause = 560
        cues.append(_Cue(sentence, pause, rate, pitch, lang))
    return cues or [_Cue(script, 300, *body, "es")]


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
        packs.append(_Cue(" ".join(item.text for item in bucket), pause, last.rate, last.pitch, last.lang))
        bucket.clear()

    for cue in cues:
        low = cue.text.lower()
        new_block = bool(
            re.match(r"^la (primera|segunda|tercera|cuarta|quinta|sexta|séptima)\b", low)
            or re.match(r"^story (first|second|third|fourth|fifth|sixth|seventh|number)\b", low)
            or "cierre de edición" in low
            or PODCAST_SIGN_OFF.lower() in low
            or (bucket and bucket[-1].lang != cue.lang)
        )
        if new_block:
            flush(520)
        bucket.append(cue)
        if PODCAST_SIGN_OFF.lower() in low:
            flush(180)
    flush(280)
    return packs or cues


def _ensure_mp3(path: Path) -> Path:
    if path.suffix.lower() == ".mp3" and path.exists() and path.stat().st_size > 500:
        return path
    dest = path.with_suffix(".mp3")
    if not _ffmpeg() or not path.exists():
        return path
    try:
        _run_ffmpeg(["-i", str(path), "-q:a", "5", str(dest)])
        if dest.exists() and dest.stat().st_size > 500:
            return dest
    except Exception:
        dest.unlink(missing_ok=True)
    return path


_KOKORO = {}


def _prepare_espeak() -> None:
    try:
        import espeakng_loader
        from phonemizer.backend.espeak.wrapper import EspeakWrapper

        EspeakWrapper.set_library(espeakng_loader.get_library_path())
        if hasattr(EspeakWrapper, "set_data_path"):
            EspeakWrapper.set_data_path(espeakng_loader.get_data_path())
    except Exception:
        pass


def _kokoro_pipeline(lang: str):
    code = "e" if lang == "es" else "a"
    pipe = _KOKORO.get(code)
    if pipe is not None:
        return pipe
    import os

    os.environ.setdefault("HF_HUB_DISABLE_PROGRESS_BARS", "1")
    os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
    _prepare_espeak()
    from kokoro import KPipeline

    pipe = KPipeline(lang_code=code, repo_id="hexgrad/Kokoro-82M")
    _KOKORO[code] = pipe
    return pipe


def _kokoro_voice(lang: str, reader_key: str) -> str:
    info = READERS.get(reader_key, READERS[DEFAULT_READER])
    if lang == "en":
        return str(info.get("en_voice") or "am_michael")
    return str(info.get("voice") or "em_alex")


def _speak_kokoro(cues: list[_Cue], path: Path, reader_key: str) -> None:
    import numpy as np
    import soundfile as sf

    sample_rate = 24000
    pieces: list[np.ndarray] = []
    for cue in cues:
        pipe = _kokoro_pipeline(cue.lang)
        voice = _kokoro_voice(cue.lang, reader_key)
        chunks: list[np.ndarray] = []
        for _gs, _ps, audio in pipe(cue.text, voice=voice, speed=0.94):
            if audio is None:
                continue
            chunk = np.asarray(audio, dtype=np.float32).reshape(-1)
            if chunk.size:
                chunks.append(chunk)
        if not chunks:
            raise RuntimeError(f"Kokoro no generó audio para un bloque en {cue.lang}")
        block = np.concatenate(chunks)
        if float(np.sqrt(np.mean(np.square(block)))) < 1e-4:
            raise RuntimeError(f"Kokoro devolvió silencio en {cue.lang}")
        pieces.append(block)
        if cue.pause_ms:
            hush = int(sample_rate * min(cue.pause_ms, 420) / 1000)
            pieces.append(np.zeros(hush, dtype=np.float32))
    wav = path.with_name(path.stem + "_kokoro.wav")
    sf.write(str(wav), np.concatenate(pieces), sample_rate)
    converted = _ensure_mp3(wav)
    path.write_bytes(converted.read_bytes())
    if converted != wav:
        wav.unlink(missing_ok=True)


def synthesize(
    script: str,
    voice: str = DEFAULT_VOICE,
    reader_key: str = DEFAULT_READER,
    items: list[NewsItem] | None = None,
    recommendation: str | None = None,
) -> Path:
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(BOGOTA).strftime("%Y%m%d_%H%M%S")
    errors: list[str] = []

    raw_cues = (
        build_cues(items, recommendation or "", reader_key=reader_key)
        if items
        else _cues_from_script(script, reader_key)
    )
    cues = _pack_cues(raw_cues)
    mp3 = AUDIO_DIR / f"briefing_{stamp}.mp3"
    engines = (_speak_kokoro, _speak_gtts, _speak_edge) if not _edge_reachable() else (_speak_kokoro, _speak_edge, _speak_gtts)
    for engine in engines:
        try:
            if engine is _speak_kokoro:
                engine(cues, mp3, reader_key)
            elif engine is _speak_edge:
                engine(cues, voice, mp3, reader_key)
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
            return _ensure_mp3(wav)
        errors.append("La voz local de Windows no produjo un archivo válido")
    except Exception as exc:
        errors.append(f"Voz local de Windows: {exc}")

    raise RuntimeError(
        "No se pudo generar el podcast. "
        + " | ".join(errors)
        + ". Revise la red o instale una voz en español o inglés en Windows."
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


def _speak_edge(cues: list[_Cue], voice: str, path: Path, reader_key: str = DEFAULT_READER) -> None:
    asyncio.run(_speak_edge_async(cues, voice, path, reader_key))


async def _speak_edge_async(
    cues: list[_Cue],
    voice: str,
    path: Path,
    reader_key: str = DEFAULT_READER,
) -> None:
    import edge_tts

    voice_es, voice_en = _edge_pair(reader_key)
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        clips: list[Path] = []
        for idx, cue in enumerate(cues):
            clip = folder / f"c{idx:03d}.mp3"
            chosen = voice_en if cue.lang == "en" else voice_es
            communicate = edge_tts.Communicate(
                text=cue.text,
                voice=chosen,
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
            if cue.lang == "en":
                gTTS(text=cue.text, lang="en", tld="com").save(str(clip))
            else:
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
