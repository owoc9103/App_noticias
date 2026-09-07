from __future__ import annotations

from datetime import datetime
from typing import Callable
from zoneinfo import ZoneInfo

from src.config import SOURCE_BY_ID, SOURCES, TOP_N, Source
from src.fetch_news import collect_all, enrich_bodies
from src.models import Briefing
from src.podcast import build_script, synthesize
from src.rank import pick_top, score_item
from src.recommend import recommend
from src.summarize import summarize_many

ProgressFn = Callable[[str], None]
BOGOTA = ZoneInfo("America/Bogota")


def selected_sources(ids: list[str] | None) -> list[Source]:
    if not ids:
        return list(SOURCES)
    return [SOURCE_BY_ID[i] for i in ids if i in SOURCE_BY_ID]


def run_briefing(
    source_ids: list[str] | None = None,
    voice: str = "es-CO-GonzaloNeural",
    use_llm: bool = True,
    use_cache: bool = True,
    make_audio: bool = True,
    progress: ProgressFn | None = None,
) -> Briefing:
    def note(message: str) -> None:
        if progress:
            progress(message)

    sources = selected_sources(source_ids)
    note("Recolectando titulares de las fuentes oficiales…")
    candidates, ok, fail = collect_all(sources, progress=note, use_cache=use_cache)
    for item in candidates:
        score_item(item)

    preselected = pick_top(candidates, n=min(18, max(TOP_N * 3, 12)))
    note("Abriendo las notas para extraer el cuerpo y resumir…")
    enrich_bodies(preselected, limit=18, progress=note)

    top = pick_top(preselected or candidates, n=TOP_N)
    note("Redactando resúmenes en español…")
    summarize_many(top, use_llm=use_llm)

    note("Elaborando la recomendación financiera…")
    reco = recommend(top, use_llm=use_llm)

    note("Escribiendo el guion del noticiero…")
    script = build_script(top, reco)

    audio_path = ""
    if make_audio:
        note("Generando el podcast en español…")
        audio_path = str(synthesize(script, voice=voice))

    note("Briefing listo.")
    return Briefing(
        items=top,
        recommendation=reco,
        script=script,
        audio_path=audio_path,
        generated_at=datetime.now(BOGOTA),
        sources_ok=sorted(ok),
        sources_fail=sorted(fail),
        candidates=len(candidates),
    )


if __name__ == "__main__":
    result = run_briefing(use_llm=False, make_audio=False, progress=print)
    print("OK", result.candidates, "candidatos;", len(result.items), "en el top")
    for i, item in enumerate(result.items, start=1):
        print(f"{i}. [{item.source_name}] {item.title}")
    print(result.recommendation[:400])
