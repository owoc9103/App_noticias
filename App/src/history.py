from __future__ import annotations

import json
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

from src.config import HISTORY_DIR
from src.models import Briefing, NewsItem
from src.rank import same_story

BOGOTA = ZoneInfo("America/Bogota")


def _path_for(day: datetime | None = None) -> Path:
    HISTORY_DIR.mkdir(parents=True, exist_ok=True)
    day = day or datetime.now(BOGOTA)
    return HISTORY_DIR / f"{day.strftime('%Y-%m-%d')}.json"


def save_briefing(briefing: Briefing) -> Path:
    path = _path_for(briefing.generated_at)
    payload = {
        "generated_at": briefing.generated_at.isoformat() if briefing.generated_at else None,
        "recommendation": briefing.recommendation,
        "takeaways": list(briefing.takeaways or []),
        "script": briefing.script,
        "audio_path": briefing.audio_path,
        "candidates": briefing.candidates,
        "profile": briefing.profile,
        "market": briefing.market,
        "delta_vs_yesterday": briefing.delta_vs_yesterday,
        "reader_key": briefing.reader_key,
        "reader_label": briefing.reader_label,
        "items": [
            {
                "source_id": item.source_id,
                "source_name": item.source_name,
                "category": item.category,
                "title": item.title,
                "url": item.url,
                "published": item.published.isoformat() if item.published else None,
                "summary_es": item.summary_es,
                "score": item.score,
                "tags": item.tags,
                "why": item.why,
                "body_quality": item.body_quality,
                "related_sources": item.related_sources,
                "language": item.language,
            }
            for item in briefing.items
        ],
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def load_briefing(day: datetime | None = None) -> Briefing | None:
    path = _path_for(day)
    if not path.exists():
        return None
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    items = []
    for row in raw.get("items", []):
        published = row.get("published")
        items.append(
            NewsItem(
                source_id=row.get("source_id", ""),
                source_name=row.get("source_name", ""),
                category=row.get("category", ""),
                title=row.get("title", ""),
                url=row.get("url", ""),
                published=datetime.fromisoformat(published) if published else None,
                summary_es=row.get("summary_es", ""),
                score=float(row.get("score") or 0),
                tags=list(row.get("tags") or []),
                why=row.get("why", ""),
                body_quality=row.get("body_quality", "titular"),
                related_sources=list(row.get("related_sources") or []),
                language=row.get("language", ""),
            )
        )
    stamp = raw.get("generated_at")
    return Briefing(
        items=items,
        recommendation=raw.get("recommendation", ""),
        takeaways=list(raw.get("takeaways") or []),
        script=raw.get("script", ""),
        audio_path=raw.get("audio_path", ""),
        generated_at=datetime.fromisoformat(stamp) if stamp else None,
        candidates=int(raw.get("candidates") or 0),
        reader_key=raw.get("reader_key", "hombre"),
        reader_label=raw.get("reader_label", "Hombre"),
        profile=raw.get("profile", "tesoreria"),
        market=dict(raw.get("market") or {}),
        delta_vs_yesterday=list(raw.get("delta_vs_yesterday") or []),
    )


def load_today() -> Briefing | None:
    return load_briefing()


def titles_for(day: datetime) -> list[str]:
    stored = load_briefing(day)
    if not stored:
        return []
    return [item.title for item in stored.items]


def delta_vs_yesterday(items: list[NewsItem]) -> list[str]:
    previous = load_briefing(datetime.now(BOGOTA) - timedelta(days=1))
    if not previous or not previous.items:
        return []
    new_ones = [
        item.title
        for item in items
        if not any(same_story(item, old) for old in previous.items)
    ]
    if not new_ones:
        return ["La edición de hoy mantiene el mismo tablero temático de ayer."]
    return [f"Nuevo vs ayer: {title}" for title in new_ones[:4]]


def list_history(limit: int = 7) -> list[Path]:
    HISTORY_DIR.mkdir(parents=True, exist_ok=True)
    files = sorted(HISTORY_DIR.glob("*.json"), reverse=True)
    return files[:limit]
