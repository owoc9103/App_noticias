from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
CACHE_DIR = DATA_DIR / "cache"
AUDIO_DIR = DATA_DIR / "audio"
ASSETS_DIR = ROOT / "assets"

PODCAST_SIGN_OFF = "Esto te lo dice la app de javeriana Cali"
CACHE_MINUTES = 25
MAX_CANDIDATES_PER_SOURCE = 8
MAX_BODY_CHARS = 7000
TOP_N = 7

DEFAULT_READER = "hombre"
READERS = {
    "hombre": {
        "label": "Hombre",
        "voice": "es-CO-GonzaloNeural",
        "name": "Gonzalo",
        "accent": "Colombia",
    },
    "mujer": {
        "label": "Mujer",
        "voice": "es-CO-SalomeNeural",
        "name": "Salomé",
        "accent": "Colombia",
    },
}
DEFAULT_VOICE = READERS[DEFAULT_READER]["voice"]
VOICES = {info["voice"]: f'{info["name"]} · {info["accent"]}' for info in READERS.values()}

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
)

GOOGLE_NEWS = (
    "https://news.google.com/rss/search?q={query}&hl=es-419&gl=CO&ceid=CO:es"
)


@dataclass(frozen=True)
class Source:
    id: str
    name: str
    category: str  # nacional | internacional | oficial
    home: str
    feeds: tuple[str, ...] = field(default_factory=tuple)
    google_query: str = ""
    hosts: tuple[str, ...] = field(default_factory=tuple)


SOURCES: tuple[Source, ...] = (
    Source(
        id="larepublica",
        name="La República",
        category="nacional",
        home="https://www.larepublica.co/",
        feeds=("https://www.larepublica.co/rss",),
        google_query="site:larepublica.co when:2d (economía OR finanzas OR dólar OR inflación OR bancos)",
        hosts=("larepublica.co",),
    ),
    Source(
        id="portafolio",
        name="Portafolio",
        category="nacional",
        home="https://www.portafolio.co/",
        feeds=(),
        google_query="site:portafolio.co when:2d (economía OR finanzas OR dólar OR inflación)",
        hosts=("portafolio.co",),
    ),
    Source(
        id="bloomberglinea",
        name="Bloomberg Línea Colombia",
        category="nacional",
        home="https://www.bloomberglinea.com/latinoamerica/colombia/",
        feeds=(),
        google_query="site:bloomberglinea.com Colombia when:2d (economía OR mercados OR dólar)",
        hosts=("bloomberglinea.com",),
    ),
    Source(
        id="valora",
        name="Valora Analitik",
        category="nacional",
        home="https://www.valoraanalitik.com/",
        feeds=("https://www.valoraanalitik.com/feed/",),
        google_query="site:valoraanalitik.com when:2d (economía OR finanzas OR petróleo OR bancos)",
        hosts=("valoraanalitik.com",),
    ),
    Source(
        id="forbesco",
        name="Forbes Colombia",
        category="nacional",
        home="https://forbes.co/",
        feeds=(),
        google_query="site:forbes.co when:2d (economía OR negocios OR finanzas OR inversión)",
        hosts=("forbes.co",),
    ),
    Source(
        id="reuters",
        name="Reuters",
        category="internacional",
        home="https://www.reuters.com/",
        feeds=(
            "https://www.reutersagency.com/feed/?best-topics=business-finance&post_type=best",
            "https://www.reutersagency.com/feed/?best-topics=economy&post_type=best",
        ),
        google_query="site:reuters.com (markets OR inflation OR Fed OR oil)",
        hosts=("reuters.com", "reutersagency.com"),
    ),
    Source(
        id="bloomberg",
        name="Bloomberg",
        category="internacional",
        home="https://www.bloomberg.com/",
        feeds=(),
        google_query="site:bloomberg.com when:2d (markets OR inflation OR Fed OR oil OR stocks)",
        hosts=("bloomberg.com",),
    ),
    Source(
        id="ft",
        name="Financial Times",
        category="internacional",
        home="https://www.ft.com/",
        feeds=(
            "https://www.ft.com/markets?format=rss",
            "https://www.ft.com/global-economy?format=rss",
        ),
        google_query="site:ft.com when:2d (markets OR economy OR inflation OR oil OR emerging)",
        hosts=("ft.com",),
    ),
    Source(
        id="wsj",
        name="The Wall Street Journal",
        category="internacional",
        home="https://www.wsj.com/",
        feeds=(
            "https://feeds.a.dj.com/rss/RSSMarketsMain.xml",
            "https://feeds.content.dowjones.io/public/rss/RSSWorldNews",
        ),
        google_query="site:wsj.com when:2d (markets OR Fed OR stocks OR economy)",
        hosts=("wsj.com", "dowjones.com"),
    ),
    Source(
        id="economist",
        name="The Economist",
        category="internacional",
        home="https://www.economist.com/",
        feeds=("https://www.economist.com/finance-and-economics/rss.xml",),
        google_query="site:economist.com when:3d (finance OR economy OR emerging OR inflation)",
        hosts=("economist.com",),
    ),
    Source(
        id="cnbc",
        name="CNBC",
        category="internacional",
        home="https://www.cnbc.com/",
        feeds=("https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=100003114",),
        google_query="site:cnbc.com when:2d (markets OR Fed OR stocks OR oil)",
        hosts=("cnbc.com",),
    ),
    Source(
        id="marketwatch",
        name="MarketWatch",
        category="internacional",
        home="https://www.marketwatch.com/",
        feeds=("https://feeds.content.dowjones.io/public/rss/mw_topstories",),
        google_query="site:marketwatch.com when:2d (markets OR stocks OR Fed OR economy)",
        hosts=("marketwatch.com",),
    ),
    Source(
        id="banrep",
        name="Banco de la República",
        category="oficial",
        home="https://www.banrep.gov.co/",
        feeds=(),
        google_query="site:banrep.gov.co when:14d (tasa OR inflación OR junta OR comunicado OR política monetaria)",
        hosts=("banrep.gov.co",),
    ),
    Source(
        id="dane",
        name="DANE",
        category="oficial",
        home="https://www.dane.gov.co/",
        feeds=(),
        google_query="site:dane.gov.co when:14d (IPC OR desempleo OR PIB OR inflación OR empleo)",
        hosts=("dane.gov.co",),
    ),
    Source(
        id="superfinanciera",
        name="Superintendencia Financiera de Colombia",
        category="oficial",
        home="https://www.superfinanciera.gov.co/",
        feeds=(),
        google_query="site:superfinanciera.gov.co when:14d (circular OR comunicado OR establecimientos de crédito OR mercados)",
        hosts=("superfinanciera.gov.co",),
    ),
    Source(
        id="minhacienda",
        name="Ministerio de Hacienda y Crédito Público",
        category="oficial",
        home="https://www.minhacienda.gov.co/",
        feeds=(),
        google_query="site:minhacienda.gov.co when:14d (comunicado OR presupuesto OR deuda OR fiscal)",
        hosts=("minhacienda.gov.co",),
    ),
)

SOURCE_BY_ID = {s.id: s for s in SOURCES}

HIGH_KEYWORDS = (
    "inflacion",
    "inflación",
    "ipc",
    "tasa de interes",
    "tasa de interés",
    "tasas",
    "banrep",
    "banco de la republica",
    "banco de la república",
    "dolar",
    "dólar",
    "trm",
    "petroleo",
    "petróleo",
    "brent",
    "wti",
    "oil",
    "crude",
    "fed",
    "federal reserve",
    "fomc",
    "pib",
    "gdp",
    "desempleo",
    "unemployment",
    "dane",
    "superfinanciera",
    "minhacienda",
    "recesion",
    "recesión",
    "recession",
    "default",
    "deuda",
    "bonos",
    "tes",
    "emergentes",
    "emerging",
    "wall street",
    "s&p",
    "nasdaq",
    "cpi",
    "payroll",
    "ecopetrol",
    "bancolombia",
    "politica monetaria",
    "política monetaria",
    "tipo de cambio",
    "riesgo pais",
    "riesgo país",
    "presupuesto",
    "deficit",
    "déficit",
)

MEDIUM_KEYWORDS = (
    "acciones",
    "bolsa",
    "bvc",
    "mercados",
    "markets",
    "stocks",
    "finanzas",
    "economia",
    "economía",
    "economy",
    "banco",
    "banca",
    "credito",
    "crédito",
    "inversion",
    "inversión",
    "arancel",
    "tariff",
    "opep",
    "opec",
    "china",
    "europa",
    "guerra",
    "geopolitica",
    "geopolítica",
    "empleo",
    "salarios",
    "vivienda",
    "hipoteca",
    "fiscal",
    "presupuesto",
    "impuesto",
    "tributaria",
    "comercio",
    "aduana",
    "aduanero",
    "exportacion",
    "exportación",
    "importacion",
    "importación",
    "cafe",
    "café",
    "carbon",
    "carbón",
    "oro",
    "nvidia",
    "inteligencia artificial",
)

COLOMBIA_KEYWORDS = (
    "colombia",
    "colombiano",
    "colombiana",
    "bogota",
    "bogotá",
    "cali",
    "medellin",
    "medellín",
    "banrep",
    "ecopetrol",
    "isa",
    "grupo aval",
    "davivienda",
    "bancolombia",
    "peso colombiano",
    "cop",
)

JUNK_TITLE_BITS = (
    "aspirantes",
    "vacantes",
    "hoja de vida",
    "convocatoria de empleo",
    "trabaje con nosotros",
    "subscribe",
    "newsletter",
    "crossword",
    "privacy policy",
    "terminos y condiciones",
    "términos y condiciones",
    "cookies",
    "horoscopo",
    "horóscopo",
    "receta",
    "descarga",
    "encuentra resoluciones",
    "sentencias y conciliaciones",
    "(copiar)",
    "distribuciones del mhcp",
    "tramites y servicios",
    "trámites y servicios",
    "trámites",
    "tramites",
)

SKIP_PATH_BITS = (
    "/tag/",
    "/tags/",
    "/autor/",
    "/author/",
    "/categoria/",
    "/category/",
    "/seccion/",
    "/secciones/",
    "/wp-login",
    "/login",
    "/suscri",
    "/subscribe",
    "/podcast",
    "/video/",
    "/videos/",
    "/opinion/",
    "/columnistas/",
    "#",
    "javascript:",
    "mailto:",
)
