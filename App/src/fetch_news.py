from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Callable
from urllib.parse import quote_plus

import feedparser

from src.config import CACHE_DIR, CACHE_MINUTES, GOOGLE_NEWS, MAX_CANDIDATES_PER_SOURCE, Source
from src.extract import fetch_article, harvest_homepage_links
from src.http_client import get
from src.models import NewsItem
from src.rank import is_junk
from src.text_utils import clean_text, clean_title, html_to_text, parse_date, title_key

ProgressFn = Callable[[str], None]


def _cache_path(source_id: str) -> Path:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    return CACHE_DIR / f"{source_id}.json"


def _load_cache(source_id: str) -> list[NewsItem] | None:
    path = _cache_path(source_id)
    if not path.exists():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    stamp = parse_date(payload.get("ts"))
    if not stamp or datetime.now(timezone.utc) - stamp > timedelta(minutes=CACHE_MINUTES):
        return None
    items: list[NewsItem] = []
    for raw in payload.get("items", []):
        items.append(
            NewsItem(
                source_id=raw["source_id"],
                source_name=raw["source_name"],
                category=raw["category"],
                title=raw["title"],
                url=raw["url"],
                published=parse_date(raw.get("published")),
                snippet=raw.get("snippet", ""),
                body=raw.get("body", ""),
                fetch_method=raw.get("fetch_method", "cache"),
            )
        )
    return items or None


def _save_cache(source_id: str, items: list[NewsItem]) -> None:
    payload = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "items": [
            {
                "source_id": i.source_id,
                "source_name": i.source_name,
                "category": i.category,
                "title": i.title,
                "url": i.url,
                "published": i.published.isoformat() if i.published else None,
                "snippet": i.snippet,
                "body": i.body[:4000],
                "fetch_method": i.fetch_method,
            }
            for i in items
        ],
    }
    _cache_path(source_id).write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")


def _from_entry(source: Source, entry: object, method: str) -> NewsItem | None:
    title = clean_title(getattr(entry, "title", "") or "", source.name)
    link = getattr(entry, "link", "") or ""
    if not title or not link:
        return None
    snippet = html_to_text(getattr(entry, "summary", "") or getattr(entry, "description", "") or "")
    published = None
    if getattr(entry, "published", None):
        published = parse_date(entry.published)
    elif getattr(entry, "updated", None):
        published = parse_date(entry.updated)
    return NewsItem(
        source_id=source.id,
        source_name=source.name,
        category=source.category,
        title=title,
        url=link,
        published=published,
        snippet=snippet,
        fetch_method=method,
    )


def _from_rss(source: Source, url: str, method: str) -> list[NewsItem]:
    try:
        resp = get(url, timeout=8)
        resp.raise_for_status()
        parsed = feedparser.parse(resp.content)
    except Exception:
        return []
    items: list[NewsItem] = []
    for entry in parsed.entries[: MAX_CANDIDATES_PER_SOURCE + 4]:
        item = _from_entry(source, entry, method)
        if item and not is_junk(item):
            items.append(item)
    return items


def _from_google(source: Source) -> list[NewsItem]:
    if not source.google_query:
        return []
    url = GOOGLE_NEWS.format(query=quote_plus(source.google_query))
    return _from_rss(source, url, "google_news")


def _from_home(source: Source) -> list[NewsItem]:
    try:
        resp = get(source.home, timeout=8)
        resp.raise_for_status()
        pairs = harvest_homepage_links(source.home, resp.text, source.hosts)
    except Exception:
        return []
    items: list[NewsItem] = []
    for title, link in pairs[: MAX_CANDIDATES_PER_SOURCE + 6]:
        candidate = NewsItem(
            source_id=source.id,
            source_name=source.name,
            category=source.category,
            title=title,
            url=link,
            snippet="",
            fetch_method="homepage",
        )
        if not is_junk(candidate):
            items.append(candidate)
    return items


def _dedupe(items: list[NewsItem]) -> list[NewsItem]:
    seen: set[str] = set()
    out: list[NewsItem] = []
    for item in items:
        key = title_key(item.title) or item.url
        if key in seen:
            continue
        seen.add(key)
        out.append(item)
    return out


def _source_cap(source: Source) -> int:
    return 10 if source.category == "internacional" else MAX_CANDIDATES_PER_SOURCE


def collect_source(source: Source, use_cache: bool = True) -> list[NewsItem]:
    cap = _source_cap(source)
    if use_cache:
        cached = _load_cache(source.id)
        if cached:
            return cached[:cap]

    bag: list[NewsItem] = []
    for feed in source.feeds:
        bag.extend(_from_rss(source, feed, "rss"))
    bag.extend(_from_google(source))
    if len(bag) < 3:
        bag.extend(_from_home(source))

    items = _dedupe(bag)[:cap]
    if items:
        _save_cache(source.id, items)
    return items


def enrich_bodies(items: list[NewsItem], limit: int = 22, progress: ProgressFn | None = None) -> None:
    from concurrent.futures import ThreadPoolExecutor, as_completed

    targets = [i for i in items if not i.body][:limit]
    if not targets:
        return

    def work(item: NewsItem) -> None:
        data = fetch_article(item.url)
        if data.get("url"):
            item.url = data["url"]
        if data.get("title") and len(data["title"]) > 20:
            item.title = clean_title(data["title"], item.source_name)
        if data.get("snippet") and not item.snippet:
            item.snippet = data["snippet"]
        if data.get("body"):
            item.body = data["body"]

    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = {pool.submit(work, item): item for item in targets}
        done = 0
        for future in as_completed(futures):
            done += 1
            try:
                future.result()
            except Exception:
                pass
            if progress:
                progress(f"Leyendo cuerpos de artículos ({done}/{len(targets)})")


def collect_all(
    sources: list[Source],
    progress: ProgressFn | None = None,
    use_cache: bool = True,
) -> tuple[list[NewsItem], list[str], list[str]]:
    from concurrent.futures import ThreadPoolExecutor, as_completed

    ok: list[str] = []
    fail: list[str] = []
    collected: list[NewsItem] = []

    with ThreadPoolExecutor(max_workers=10) as pool:
        futures = {pool.submit(collect_source, source, use_cache): source for source in sources}
        finished = 0
        for future in as_completed(futures):
            source = futures[future]
            finished += 1
            try:
                items = future.result()
                if items:
                    collected.extend(items)
                    ok.append(source.name)
                else:
                    fail.append(source.name)
            except Exception:
                fail.append(source.name)
            if progress:
                progress(f"Consultando fuentes ({finished}/{len(sources)}): {source.name}")

    return _dedupe(collected), ok, fail
