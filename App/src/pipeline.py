from __future__ import annotations

from datetime import datetime
from typing import Callable
from zoneinfo import ZoneInfo

from src.config import DEFAULT_PROFILE, DEFAULT_READER, READERS, SOURCE_BY_ID, SOURCES, TOP_N, Source
from src.fetch_news import collect_all, enrich_bodies
from src.history import delta_vs_yesterday, save_briefing
from src.markets import fetch_markets
from src.models import Briefing
from src.podcast import build_script, synthesize
from src.rank import annotate_item, pick_top, score_item
from src.recommend import recommend
from src.summarize import summarize_many

ProgressFn = Callable[[str], None]
BOGOTA = ZoneInfo("America/Bogota")


def selected_sources(ids: list[str] | None) -> list[Source]:
    if not ids:
        return list(SOURCES)
    return [SOURCE_BY_ID[i] for i in ids if i in SOURCE_BY_ID]


def _market_result(job) -> dict[str, str]:
    try:
        return job.result(timeout=5) or {}
    except Exception:
        return {}


def reader_voice(reader_key: str) -> tuple[str, str, str]:
    info = READERS.get(reader_key, READERS[DEFAULT_READER])
    return info["voice"], info["label"], reader_key if reader_key in READERS else DEFAULT_READER


def run_briefing(
    source_ids: list[str] | None = None,
    voice: str | None = None,
    reader_key: str = DEFAULT_READER,
    profile: str = DEFAULT_PROFILE,
    use_llm: bool = True,
    use_cache: bool = True,
    make_audio: bool = True,
    progress: ProgressFn | None = None,
) -> Briefing:
    def note(message: str) -> None:
        if progress:
            progress(message)

    from concurrent.futures import ThreadPoolExecutor

    sources = selected_sources(source_ids)
    market_pool = ThreadPoolExecutor(max_workers=1)
    market_job = market_pool.submit(fetch_markets)
    try:
        note("Recolectando titulares de las fuentes oficiales…")
        candidates, ok, fail = collect_all(sources, progress=note, use_cache=use_cache)
        for item in candidates:
            score_item(item)

        preselected = pick_top(candidates, n=min(12, max(TOP_N * 2, 10)))
        note("Abriendo las notas para extraer el cuerpo y resumir…")
        enrich_bodies(preselected, limit=10, progress=note)

        top = pick_top(preselected or candidates, n=TOP_N)
        for item in top:
            annotate_item(item)

        note("Redactando resúmenes en el idioma de cada nota…")
        summarize_many(top, use_llm=use_llm)
        for item in top:
            annotate_item(item)

        chosen_voice, reader_label, reader_key = reader_voice(reader_key)
        if voice:
            chosen_voice = voice

        note("Elaborando la recomendación financiera…")
        reco = recommend(top, use_llm=use_llm, profile=profile)

        note("Escribiendo el guion bilingüe…")
        script = build_script(top, reco, reader_key=reader_key)

        audio_path = ""
        audio_note = ""
        if make_audio:
            note(f"Generando el podcast bilingüe con voz de {reader_label.lower()}…")
            try:
                audio_path = str(
                    synthesize(
                        script,
                        voice=chosen_voice,
                        reader_key=reader_key,
                        items=top,
                        recommendation=reco,
                    )
                )
                if audio_path.endswith(".wav"):
                    audio_note = "Se usó la voz local de Windows porque el servicio en la nube no estuvo disponible. En el celular, descargue el audio si el reproductor no abre."
            except Exception as exc:
                audio_note = f"El briefing se armó, pero el audio no se pudo generar: {exc}"
                note(audio_note)

        briefing = Briefing(
            items=top,
            recommendation=reco,
            script=script,
            audio_path=audio_path,
            generated_at=datetime.now(BOGOTA),
            sources_ok=sorted(ok),
            sources_fail=sorted(fail),
            candidates=len(candidates),
            reader_key=reader_key,
            reader_label=reader_label,
            audio_note=audio_note,
            profile=profile,
            market=_market_result(market_job),
            delta_vs_yesterday=delta_vs_yesterday(top),
        )
        save_briefing(briefing)
        note("Briefing listo.")
        return briefing
    finally:
        market_pool.shutdown(wait=False)


if __name__ == "__main__":
    result = run_briefing(use_llm=False, make_audio=False, progress=print)
    print("OK", result.candidates, "candidatos;", len(result.items), "en el top")
    for i, item in enumerate(result.items, start=1):
        print(f"{i}. [{item.source_name}] {item.title} | {item.tags} | {item.why}")
    print(result.recommendation[:400])
