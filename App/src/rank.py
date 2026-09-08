from __future__ import annotations

import re
from datetime import datetime, timezone

from src.config import COLOMBIA_KEYWORDS, HIGH_KEYWORDS, IMPACT_LABELS, JUNK_TITLE_BITS, MEDIUM_KEYWORDS, TOP_N
from src.models import NewsItem
from src.text_utils import fold, title_key


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
        return high >= 1 or mid >= 1
    return high >= 1 or mid >= 1 or col >= 1


def score_item(item: NewsItem) -> float:
    if is_junk(item):
        item.score = 0.0
        return 0.0
    high, mid, col = finance_signal(item)
    official = 1.1 if item.category == "oficial" and high + mid > 0 else 0.0
    body_bonus = 0.5 if len(item.body) > 280 else 0.15 if item.snippet else 0.0
    category_w = {"oficial": 1.08, "nacional": 1.06, "internacional": 1.22}.get(item.category, 1.0)
    raw = (3.4 * high) + (1.1 * mid) + (2.0 * col) + official + body_bonus + (2.0 * recency_score(item))
    if not is_relevant(item):
        raw *= 0.15
    item.score = round(raw * category_w, 3)
    return item.score


_STOP = {
    "para", "como", "este", "esta", "estos", "esta", "desde", "hasta", "sobre",
    "tras", "entre", "segun", "según", "despues", "después", "colombia",
    "colombiano", "colombiana", "mundo", "nueva", "nuevo", "anos", "años",
}

_TAG_RULES: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("inflacion", ("inflacion", "inflación", "ipc", "cpi", "precios")),
    ("tasas", ("tasa", "tasas", "banrep", "fed", "fomc", "interes", "interés")),
    ("dolar", ("dolar", "dólar", "trm", "divisas", "peso", "depreci")),
    ("petroleo", ("petroleo", "petróleo", "brent", "wti", "crudo", "oil", "opep")),
    ("fiscal", ("presupuesto", "deficit", "déficit", "hacienda", "deuda", "tes", "fiscal")),
    ("banca", ("banco", "banca", "superfinanciera", "credito", "crédito", "cartera")),
    ("empleo", ("empleo", "desempleo", "nomina", "nómina", "payroll")),
)


def story_tokens(title: str) -> set[str]:
    return {
        word
        for word in fold(title).replace(".", " ").split()
        if len(word) > 3 and word not in _STOP
    }


def same_story(left: NewsItem, right: NewsItem) -> bool:
    a, b = story_tokens(left.title), story_tokens(right.title)
    if not a or not b:
        return title_key(left.title) == title_key(right.title)
    overlap = len(a & b)
    return overlap >= 3 and overlap / len(a | b) >= 0.42


def dedupe_stories(items: list[NewsItem]) -> list[NewsItem]:
    ranked = sorted(items, key=lambda i: i.score, reverse=True)
    winners: list[NewsItem] = []
    for item in ranked:
        twin = next((other for other in winners if same_story(item, other)), None)
        if twin:
            if item.source_name not in twin.related_sources and item.source_name != twin.source_name:
                twin.related_sources.append(item.source_name)
            continue
        winners.append(item)
    return winners


def _has_term(blob: str, word: str) -> bool:
    if len(word) <= 4:
        return re.search(rf"\b{re.escape(word)}\b", blob) is not None
    return word in blob


def tag_item(item: NewsItem) -> list[str]:
    blob = fold(f"{item.title} {item.snippet} {item.summary_es}")
    tags = [key for key, words in _TAG_RULES if any(_has_term(blob, word) for word in words)]
    item.tags = tags
    return tags


def body_quality(item: NewsItem) -> str:
    if len(item.body or "") >= 280:
        item.body_quality = "cuerpo"
    elif (item.snippet or "").strip():
        item.body_quality = "entradilla"
    else:
        item.body_quality = "titular"
    return item.body_quality


def why_item(item: NewsItem) -> str:
    high, mid, col = finance_signal(item)
    bits: list[str] = []
    if recency_score(item) >= 0.85:
        bits.append("última hora")
    if item.category == "internacional":
        bits.append("agenda internacional")
    if item.category == "oficial":
        bits.append(f"fuente oficial ({item.source_name})")
    if col:
        bits.append("relevancia Colombia")
    if high:
        bits.append("peso económico")
    if item.tags:
        bits.append("impacto en " + ", ".join(IMPACT_LABELS.get(tag, tag) for tag in item.tags[:2]))
    elif mid:
        bits.append("coyuntura de mercados")
    if item.related_sources:
        bits.append("también en " + ", ".join(item.related_sources[:2]))
    item.why = "Entra al top 7 por " + "; ".join(bits[:3]) + "." if bits else "Entra al top 7 por relevancia de la edición."
    return item.why


def annotate_item(item: NewsItem) -> NewsItem:
    score_item(item)
    tag_item(item)
    body_quality(item)
    why_item(item)
    return item


def item_section(item: NewsItem) -> str:
    if item.category != "internacional":
        return "colombia"
    tags = set(item.tags)
    if tags & {"tasas", "inflacion", "empleo"}:
        return "policy"
    if "petroleo" in tags:
        return "commodities"
    if "dolar" in tags:
        return "fx"
    return "markets"


SECTION_ORDER = {"markets": 0, "policy": 1, "fx": 2, "commodities": 3, "colombia": 4}


def order_for_briefing(items: list[NewsItem]) -> list[NewsItem]:
    return sorted(items, key=lambda item: (SECTION_ORDER.get(item_section(item), 9), -item.score))


def pick_top(items: list[NewsItem], n: int = TOP_N) -> list[NewsItem]:
    usable = [item for item in items if not is_junk(item)]
    relevant = [item for item in usable if is_relevant(item)]
    pool = relevant or usable
    for item in pool:
        score_item(item)
    ranked = dedupe_stories(sorted(pool, key=lambda i: (i.score, recency_score(i)), reverse=True))

    chosen: list[NewsItem] = []
    per_source: dict[str, int] = {}
    intl_need = max(1, min(n - 1, round(n * 0.75)))
    col_need = n - intl_need
    used: set[int] = set()

    def can_take(item: NewsItem, relax: bool) -> bool:
        taken = per_source.get(item.source_id, 0)
        if taken >= (2 if relax else 1):
            return False
        return True

    def take(item: NewsItem) -> None:
        chosen.append(item)
        per_source[item.source_id] = per_source.get(item.source_id, 0) + 1
        used.add(id(item))

    def fill(predicate, need: int, relax: bool) -> None:
        if need <= 0:
            return
        got = 0
        for item in ranked:
            if got >= need or id(item) in used:
                continue
            if not predicate(item) or not can_take(item, relax):
                continue
            take(item)
            got += 1

    is_intl = lambda item: item.category == "internacional"
    is_col = lambda item: item.category in {"nacional", "oficial"}
    fill(is_intl, intl_need, False)
    fill(is_col, col_need, False)
    fill(is_intl, n - len(chosen), False)
    fill(is_col, n - len(chosen), False)
    fill(is_intl, n - len(chosen), True)
    fill(lambda _item: True, n - len(chosen), True)
    return order_for_briefing(chosen[:n])
