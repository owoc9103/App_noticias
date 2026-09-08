from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class NewsItem:
    source_id: str
    source_name: str
    category: str
    title: str
    url: str
    published: datetime | None = None
    snippet: str = ""
    body: str = ""
    summary_es: str = ""
    score: float = 0.0
    language: str = ""
    fetch_method: str = ""
    tags: list[str] = field(default_factory=list)
    why: str = ""
    body_quality: str = "titular"
    related_sources: list[str] = field(default_factory=list)


@dataclass
class Briefing:
    items: list[NewsItem] = field(default_factory=list)
    recommendation: str = ""
    script: str = ""
    audio_path: str = ""
    generated_at: datetime | None = None
    sources_ok: list[str] = field(default_factory=list)
    sources_fail: list[str] = field(default_factory=list)
    candidates: int = 0
    reader_key: str = "hombre"
    reader_label: str = "Hombre"
    audio_note: str = ""
    profile: str = "tesoreria"
    market: dict[str, str] = field(default_factory=dict)
    delta_vs_yesterday: list[str] = field(default_factory=list)
