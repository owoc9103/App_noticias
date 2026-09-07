from __future__ import annotations

from datetime import datetime, timezone

from src.config import COLOMBIA_KEYWORDS, HIGH_KEYWORDS, JUNK_TITLE_BITS, MEDIUM_KEYWORDS, TOP_N
from src.models import NewsItem
from src.text_utils import fold


def _hits(text: str, words: tuple[str, ...]) -> int:
    return sum(1 for word in words if word in text)


def recency_score(item: NewsItem, now: datetime | None = None) -> float:
    now = now or datetime.now(timezone.utc)
    if not item.published:
        return 0.45
    published = item.published
    if published.tzinfo is None:
        published = published.replace(tzinfo=timezone.utc)
    hours = max(0.0, (now - published).total_seconds() / 3600)
    if hours <= 12:
        return 1.0
    if hours <= 36:
        return 0.85
    if hours <= 72:
        return 0.65
    if hours <= 24 * 10:
        return 0.4
    return 0.15


def is_junk(item: NewsItem) -> bool:
    title = fold(item.title)
    url = fold(item.url)
    if any(bit in title or bit in url for bit in JUNK_TITLE_BITS):
        return True
    if any(bit in url for bit in ("/empleo", "/vacante", "/carrera", "/careers", "/jobs")):
        return True
    core = item.title
    for bit in (item.source_name, "Ministerio de Hacienda y Crédito Público", "Minhacienda"):
        core = core.replace(bit, "")
    if len(core.strip(" -|:")) < 18:
        return True
    return False


def _usable_snippet(snippet: str) -> str:
    text = fold(snippet)
    noise = ("suscri", "acceso digital", "cookie", "iniciar sesion", "noticias economicas importantes")
    if any(bit in text for bit in noise):
        return ""
    return snippet


def finance_signal(item: NewsItem) -> tuple[float, float, float]:
    title = fold(item.title)
    snip = fold(_usable_snippet(item.snippet))
    high = 2 * _hits(title, HIGH_KEYWORDS) + 1.3 * _hits(snip, HIGH_KEYWORDS)
    mid = 2 * _hits(title, MEDIUM_KEYWORDS) + _hits(snip, MEDIUM_KEYWORDS)
    col = 2 * _hits(title, COLOMBIA_KEYWORDS) + _hits(snip, COLOMBIA_KEYWORDS)
    return high, mid, col


def is_relevant(item: NewsItem) -> bool:
    if is_junk(item):
        return False
    high, mid, col = finance_signal(item)
    if item.category == "oficial":
        return high + mid + col >= 1 or any(
            w in fold(item.title) for w in ("comunicado", "junta", "informe", "boletín", "boletin", "ipc", "pib")
        )
    if item.category == "internacional":
        return high >= 1 or mid >= 2
    return high >= 1 or mid >= 1 or col >= 1


def score_item(item: NewsItem) -> float:
    if is_junk(item):
        item.score = 0.0
        return 0.0
    high, mid, col = finance_signal(item)
    official = 1.1 if item.category == "oficial" and high + mid > 0 else 0.0
    body_bonus = 0.5 if len(item.body) > 280 else 0.15 if item.snippet else 0.0
    category_w = {"oficial": 1.12, "nacional": 1.15, "internacional": 1.0}.get(item.category, 1.0)
    raw = (3.4 * high) + (1.1 * mid) + (2.0 * col) + official + body_bonus + (2.0 * recency_score(item))
    if not is_relevant(item):
        raw *= 0.15
    item.score = round(raw * category_w, 3)
    return item.score


def pick_top(items: list[NewsItem], n: int = TOP_N) -> list[NewsItem]:
    usable = [item for item in items if not is_junk(item)]
    relevant = [item for item in usable if is_relevant(item)]
    pool = relevant or usable
    for item in pool:
        score_item(item)
    ranked = sorted(pool, key=lambda i: (i.score, recency_score(i)), reverse=True)

    chosen: list[NewsItem] = []
    per_source: dict[str, int] = {}
    counts = {"nacional": 0, "internacional": 0, "oficial": 0}

    def can_take(item: NewsItem, relax: bool) -> bool:
        if per_source.get(item.source_id, 0) >= (2 if relax else 1):
            if not relax:
                return False
            if per_source.get(item.source_id, 0) >= 2:
                return False
        return True

    def take(item: NewsItem) -> None:
        chosen.append(item)
        per_source[item.source_id] = per_source.get(item.source_id, 0) + 1
        counts[item.category] = counts.get(item.category, 0) + 1

    quotas = (("oficial", 1), ("nacional", 2), ("internacional", 2))
    used: set[str] = set()
    for category, need in quotas:
        for item in ranked:
            if id(item) in used or item.category != category:
                continue
            if not can_take(item, relax=False):
                continue
            take(item)
            used.add(id(item))
            if counts[category] >= need:
                break

    for relax in (False, True):
        for item in ranked:
            if len(chosen) >= n:
                break
            if id(item) in used:
                continue
            if not can_take(item, relax=relax):
                continue
            take(item)
            used.add(id(item))

    chosen.sort(key=lambda i: i.score, reverse=True)
    return chosen[:n]
