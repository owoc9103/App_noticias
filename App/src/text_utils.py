from __future__ import annotations

import re
import unicodedata
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from html import unescape

from bs4 import BeautifulSoup

SENTENCE_SPLIT = re.compile(r"(?<=[\.!?…])\s+(?=[A-ZÁÉÍÓÚÜÑ¿¡0-9])")
WS = re.compile(r"\s+")
EN_MARKERS = (
    " the ",
    " and ",
    " of ",
    " with ",
    " from ",
    " that ",
    " this ",
    " will ",
    " would ",
    " market",
    " inflation",
    " federal ",
)
ES_MARKERS = (
    " de ",
    " la ",
    " el ",
    " los ",
    " las ",
    " que ",
    " del ",
    " para ",
    " con ",
    " por ",
    " una ",
    " inflación",
    " economía",
)


def clean_text(text: str) -> str:
    text = unescape(text or "")
    text = re.sub(r"<[^>]+>", " ", text)
    text = WS.sub(" ", text).strip()
    return text


def html_to_text(html: str) -> str:
    if not html:
        return ""
    soup = BeautifulSoup(html, "lxml")
    return clean_text(soup.get_text(" "))


def fold(text: str) -> str:
    text = unicodedata.normalize("NFKD", text or "")
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    return text.lower()


def looks_english(text: str) -> bool:
    raw = (text or "").strip()
    sample = f" {fold(raw)[:800]} "
    en = sum(1 for m in EN_MARKERS if m in sample)
    es = sum(1 for m in ES_MARKERS if m in sample)
    if raw[:4].lower().startswith(("the ", "a ", "an ")) and es < 3:
        return True
    return en >= 2 and en > es


def clean_title(title: str, source_name: str = "") -> str:
    text = clean_text(title)
    suffixes = (
        source_name,
        "Portafolio.co",
        "Bloomberg Línea",
        "Bloomberg.com",
        "Banco de la República",
        "DANE",
        "Minhacienda",
        "Ministerio de Hacienda y Crédito Público",
    )
    for suffix in suffixes:
        if suffix:
            text = re.sub(rf"\s*[-|–]\s*{re.escape(suffix)}\s*$", "", text, flags=re.I)
    return text.strip(" -|")


def split_sentences(text: str) -> list[str]:
    text = clean_text(text)
    if not text:
        return []
    parts = SENTENCE_SPLIT.split(text)
    out: list[str] = []
    for part in parts:
        piece = part.strip()
        if 40 <= len(piece) <= 420:
            out.append(piece)
        elif len(piece) > 420:
            out.append(piece[:417].rsplit(" ", 1)[0] + "…")
    return out


def parse_date(value: object) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value
    text = str(value).strip()
    if not text:
        return None
    try:
        dt = parsedate_to_datetime(text)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except (TypeError, ValueError, OverflowError):
        pass
    for fmt in ("%Y-%m-%d", "%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%SZ"):
        try:
            dt = datetime.strptime(text.replace("Z", "+0000") if fmt.endswith("%z") else text, fmt)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt
        except ValueError:
            continue
    return None


def title_key(title: str) -> str:
    t = re.sub(r"[^a-z0-9 ]+", " ", fold(title))
    return WS.sub(" ", t).strip()[:140]
