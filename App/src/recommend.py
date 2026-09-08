from __future__ import annotations

from src.config import IMPACT_LABELS
from src.models import NewsItem
from src.summarize import LLM_SYSTEM, _llm_chat
from src.text_utils import fold

DISCLAIMER = (
    "Esta lectura es académica y de coyuntura. No constituye asesoría de inversión "
    "personalizada ni una recomendación para comprar o vender un activo específico."
)


def _blob(items: list[NewsItem]) -> str:
    return fold(" ".join(f"{i.title} {i.summary_es} {i.snippet}" for i in items))


def detect_themes(items: list[NewsItem]) -> dict[str, bool]:
    text = _blob(items)
    tagged = {tag for item in items for tag in item.tags}
    return {
        "inflacion": "inflacion" in tagged or any(w in text for w in ("inflacion", "ipc", "cpi", "precios al consumidor")),
        "alza_tasas": any(w in text for w in ("sube la tasa", "alza de tasas", "rate hike", "aumento de 75", "aumento de la tasa")),
        "baja_tasas": any(w in text for w in ("recorte", "baja de tasas", "rate cut", "recorta la tasa", "mantuvo inalterada")),
        "dolar_alza": "dolar" in tagged or any(w in text for w in ("dolar", "dólar", "trm", "depreci", "peso se debilita")),
        "petroleo": "petroleo" in tagged or any(w in text for w in ("petroleo", "petróleo", "brent", "wti", "crudo", "opep")),
        "riesgo": any(w in text for w in ("caida", "caída", "selloff", "recesion", "recesión", "guerra", "arancel", "volatilidad")),
        "oficial": any(i.category == "oficial" for i in items),
        "banca": "banca" in tagged or any(w in text for w in ("superfinanciera", "cartera", "credito", "crédito", "bancos")),
        "empleo": "empleo" in tagged or any(w in text for w in ("desempleo", "empleo", "nomina", "nómina", "payroll")),
        "tasas": "tasas" in tagged,
        "fiscal": "fiscal" in tagged,
    }


def rule_recommendation(items: list[NewsItem]) -> str:
    t = detect_themes(items)
    bits: list[str] = []

    if t["inflacion"] and t["alza_tasas"]:
        bits.append(
            "El cruce entre inflación y un tono restrictivo en tasas sugiere priorizar liquidez "
            "y plazos cortos: CDT o fondos de bajo duration, y revisar indexación de deudas."
        )
    elif t["inflacion"]:
        bits.append(
            "La inflación vuelve al centro del radar. Conviene seguir el IPC del DANE, las "
            "expectativas del BanRep y el efecto sobre el poder adquisitivo y las tasas reales."
        )
    elif t["baja_tasas"]:
        bits.append(
            "Un sesgo más suave en tasas favorece, en el margen, activos de mayor duration y "
            "cierta recuperación de crédito. Aun así, el movimiento debe confirmarse con datos."
        )
    else:
        bits.append(
            "Sin un choque único dominante, la lectura prudente es diversificar, mantener "
            "colchón de liquidez y no concentrar apuestas en un solo escenario macro."
        )

    if t["dolar_alza"]:
        bits.append(
            "Si el dólar se tensiona, hay que vigilar costos importados, pasivos en moneda "
            "extranjera y la prima de riesgo país. Empresas con ingresos en dólares quedan más cubiertas."
        )
    if t["petroleo"]:
        bits.append(
            "El crudo sigue siendo un canal fiscal y cambiario para Colombia: mueve cuentas "
            "externas, Ecopetrol y el humor del peso. Un choque de oferta pide seguimiento diario."
        )
    if t["riesgo"]:
        bits.append(
            "El tono de riesgo global invita a no apalancar de más y a preferir calidad crediticia. "
            "En jornadas de aversión, la liquidez vale más que perseguir el rebote inmediato."
        )
    if t["oficial"]:
        bits.append(
            "Hay señales de fuentes oficiales. Esas piezas —BanRep, DANE, Superfinanciera o Hacienda— "
            "deben pesar más que el titular de mercado a la hora de armar el escenario base."
        )
    if t["banca"]:
        bits.append(
            "En banca y regulación, la recomendación es leer la circular o el comunicado original "
            "antes de ajustar exposición a entidades financieras o a cartera."
        )
    if t["empleo"]:
        bits.append(
            "Los datos de empleo anticipan consumo y mora. Si el mercado laboral se enfría, "
            "el crédito al consumo y el comercio suelen sentir el golpe con rezago."
        )
    if t.get("fiscal"):
        bits.append(
            "El canal fiscal está activo: presupuesto, TES o Hacienda. Conviene leer el comunicado "
            "oficial antes de asumir un cambio de financiamiento o de prima de riesgo."
        )
    if t.get("tasas") and not t["alza_tasas"] and not t["baja_tasas"]:
        bits.append(
            "Hay movimiento o expectativa en tasas. El ancla sigue siendo el dato oficial del BanRep "
            "y la curva de TES, no el titular más ruidoso."
        )

    bits.append(DISCLAIMER)
    return " ".join(bits)


def _profile_close(items: list[NewsItem], profile: str) -> str:
    tags = []
    for item in items:
        tags.extend(item.tags)
    watch = ", ".join(IMPACT_LABELS.get(tag, tag) for tag in list(dict.fromkeys(tags))[:4]) or "TRM, TES y Brent"
    if profile == "inversionista":
        return (
            f"Para un inversionista: no persiga el titular. Vigile {watch}, evite concentrar "
            "la tesis en un solo escenario y compare valuación con el dato oficial, no con el ruido."
        )
    if profile == "estudiante":
        return (
            f"Para lectura académica: identifique el canal de transmisión —{watch}— y separe "
            "hecho, interpretación y recomendación. Este briefing es un caso, no una receta."
        )
    return (
        f"Para tesorería: 1) caja y plazos cortos; 2) seguimiento de {watch}; "
        "3) no mover pasivos o coberturas solo con un titular."
    )


def key_takeaways(items: list[NewsItem], profile: str = "tesoreria") -> list[str]:
    t = detect_themes(items)
    out: list[str] = []
    if t["alza_tasas"] or t["baja_tasas"] or t.get("tasas"):
        out.append("US and global rates remain the main driver of markets.")
    if t["petroleo"]:
        out.append("Oil continues to affect Colombia’s fiscal outlook.")
    if t["dolar_alza"]:
        out.append("USD/COP volatility remains elevated.")
    if t["inflacion"] and len(out) < 3:
        out.append("Inflation is back on the radar for policy and prices.")
    if t["empleo"] and len(out) < 3:
        out.append("Labor data will shape the next move in rates.")
    if t["riesgo"] and len(out) < 3:
        out.append("Risk sentiment is fragile; liquidity still matters.")
    if t["fiscal"] and len(out) < 3:
        out.append("Fiscal news in Colombia can move TES and the peso.")
    if t["oficial"] and len(out) < 3:
        out.append("Official Colombian data should anchor the local read.")
    if not out:
        out.append("No single shock dominates; stay diversified and liquid.")
    if len(out) < 2:
        out.append("Colombia remains a complementary block to the global tape.")
    if profile == "tesoreria" and len(out) < 3:
        out.append("Keep cash buffers until the next official print.")
    elif len(out) < 3:
        out.append("Watch the next official print before changing the base case.")
    return out[:3]


def _parse_takeaway_lines(text: str) -> list[str]:
    lines: list[str] = []
    for raw in text.replace("\r", "").splitlines():
        line = raw.strip().lstrip("•-*").strip()
        if not line:
            continue
        low = line.lower()
        if "asesoría" in low or "asesoria" in low or "disclaimer" in low:
            continue
        if len(line) > 180:
            continue
        lines.append(line)
    return lines[:3]


def recommend(items: list[NewsItem], use_llm: bool = True, profile: str = "tesoreria") -> str:
    points = key_takeaways(items, profile)
    if use_llm:
        material = "\n".join(
            f"- {i.source_name}: {i.title}. {i.summary_es} [{', '.join(i.tags)}]" for i in items
        )
        polished = _llm_chat(
            [
                {"role": "system", "content": LLM_SYSTEM},
                {
                    "role": "user",
                    "content": (
                        "Write exactly 3 short Key Takeaways for a bilingual market briefing. "
                        "One line each, max 18 words, English. No tickers to buy. "
                        f"Audience profile: {profile}. Return only the 3 lines.\n\n{material}"
                    ),
                },
            ]
        )
        parsed = _parse_takeaway_lines(polished or "")
        if len(parsed) >= 2:
            points = parsed[:3]
    return "\n".join(points)
