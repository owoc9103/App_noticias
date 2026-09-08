from __future__ import annotations

import json
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

from src.config import CACHE_DIR
from src.http_client import get

_CACHE = CACHE_DIR / "markets.json"
_TTL = timedelta(minutes=20)


def _read_cache() -> dict[str, str] | None:
    if not _CACHE.exists():
        return None
    try:
        payload = json.loads(_CACHE.read_text(encoding="utf-8"))
        stamp = datetime.fromisoformat(payload["ts"])
        if datetime.now(timezone.utc) - stamp > _TTL:
            return None
        return payload.get("data") or None
    except (OSError, KeyError, ValueError, json.JSONDecodeError):
        return None


def _write_cache(data: dict[str, str]) -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    _CACHE.write_text(
        json.dumps({"ts": datetime.now(timezone.utc).isoformat(), "data": data}, ensure_ascii=False),
        encoding="utf-8",
    )


def fetch_markets() -> dict[str, str]:
    cached = _read_cache()
    if cached:
        return cached
    jobs = {"TRM": _trm, "Brent": _brent}
    data: dict[str, str] = {}
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = {key: pool.submit(fn) for key, fn in jobs.items()}
        for key, future in futures.items():
            try:
                value = future.result(timeout=5) or ""
            except Exception:
                value = ""
            if value:
                data[key] = value
    if data:
        data["Fuente"] = "datos.gov.co / Stooq"
        _write_cache(data)
    return data


def _trm() -> str:
    try:
        resp = get(
            "https://www.datos.gov.co/resource/32sa-8pi3.json",
            timeout=4,
            params={"$limit": 1, "$order": "vigenciadesde DESC"},
        )
        resp.raise_for_status()
        row = resp.json()[0]
        value = row.get("valor") or row.get("valortrm")
        date = (row.get("vigenciadesde") or "")[:10]
        if value:
            return f"${float(value):,.2f}".replace(",", "X").replace(".", ",").replace("X", ".") + (f" · {date}" if date else "")
    except Exception:
        return ""
    return ""


def _brent() -> str:
    try:
        resp = get("https://stooq.com/q/l/?s=ukoil.f&f=sd2t2ohlcv&h&e=csv", timeout=4)
        resp.raise_for_status()
        lines = resp.text.strip().splitlines()
        if len(lines) < 2:
            return ""
        close = lines[1].split(",")[6]
        price = float(close)
        return f"USD {price:,.2f}"
    except Exception:
        return ""
