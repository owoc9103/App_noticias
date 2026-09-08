from __future__ import annotations

import re
from urllib.parse import urljoin, urlparse

from bs4 import BeautifulSoup

from src.config import MAX_BODY_CHARS, SKIP_PATH_BITS
from src.http_client import get
from src.text_utils import clean_text

ARTICLE_SELECTORS = (
    "article",
    "[itemprop='articleBody']",
    ".article-body",
    ".article-content",
    ".noticia-contenido",
    ".entry-content",
    ".post-content",
    ".story-body",
    ".ArticleBody",
    "#article-content",
)

STRIP_TAGS = ("script", "style", "noscript", "iframe", "nav", "footer", "aside", "form")


def _meta(soup: BeautifulSoup, *keys: str) -> str:
    for key in keys:
        tag = soup.find("meta", attrs={"property": key}) or soup.find("meta", attrs={"name": key})
        if tag and tag.get("content"):
            return clean_text(tag["content"])
    return ""


def extract_from_html(html: str, url: str) -> dict[str, str]:
    soup = BeautifulSoup(html, "lxml")
    title = _meta(soup, "og:title", "twitter:title")
    if not title and soup.title:
        title = clean_text(soup.title.get_text(" "))
    snippet = _meta(soup, "og:description", "twitter:description", "description")

    for tag_name in STRIP_TAGS:
        for node in soup.find_all(tag_name):
            node.decompose()

    paragraphs: list[str] = []
    for selector in ARTICLE_SELECTORS:
        node = soup.select_one(selector)
        if not node:
            continue
        found = [clean_text(p.get_text(" ")) for p in node.find_all("p")]
        found = [p for p in found if len(p) > 40]
        if len(found) >= 2:
            paragraphs = found
            break

    if not paragraphs:
        paragraphs = [clean_text(p.get_text(" ")) for p in soup.find_all("p")]
        paragraphs = [p for p in paragraphs if 50 <= len(p) <= 500]

    body = " ".join(paragraphs)
    if len(body) > MAX_BODY_CHARS:
        body = body[:MAX_BODY_CHARS].rsplit(" ", 1)[0]
    return {"title": title, "snippet": snippet, "body": body, "url": url}


def fetch_article(url: str) -> dict[str, str]:
    url = resolve_url(url)
    try:
        resp = get(url, timeout=8)
        resp.raise_for_status()
        if "text" not in (resp.headers.get("Content-Type") or ""):
            if not resp.text:
                return {"title": "", "snippet": "", "body": "", "url": url}
        return extract_from_html(resp.text, resp.url or url)
    except Exception:
        return {"title": "", "snippet": "", "body": "", "url": url}


def resolve_url(url: str) -> str:
    if not url or "news.google.com" not in url:
        return url
    try:
        resp = get(url, timeout=8, allow_redirects=True)
        final = resp.url or url
        if "news.google.com" not in final:
            return final
        soup = BeautifulSoup(resp.text, "lxml")
        for a in soup.find_all("a", href=True):
            href = a["href"]
            if href.startswith("http") and "news.google.com" not in href and "google.com" not in urlparse(href).netloc:
                return href
        canonical = soup.find("link", rel="canonical")
        if canonical and canonical.get("href"):
            href = canonical["href"]
            if "news.google.com" not in href:
                return href
    except Exception:
        return url
    return url


def harvest_homepage_links(home: str, html: str, allowed_hosts: tuple[str, ...]) -> list[tuple[str, str]]:
    soup = BeautifulSoup(html, "lxml")
    seen: set[str] = set()
    found: list[tuple[str, str]] = []
    for a in soup.find_all("a", href=True):
        href = a["href"].strip()
        if not href or href.startswith("#"):
            continue
        absolute = urljoin(home, href)
        parsed = urlparse(absolute)
        host = parsed.netloc.lower().replace("www.", "")
        if allowed_hosts and not any(host.endswith(h) for h in allowed_hosts):
            continue
        path = parsed.path.lower()
        if any(bit in (path + absolute.lower()) for bit in SKIP_PATH_BITS):
            continue
        if path in {"", "/"}:
            continue
        title = clean_text(a.get_text(" "))
        if len(title) < 32 or len(title) > 220:
            continue
        key = re.sub(r"[#?].*$", "", absolute)
        if key in seen:
            continue
        seen.add(key)
        found.append((title, key))
    return found
