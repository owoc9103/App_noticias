from __future__ import annotations

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
    return {
        "inflacion": any(w in text for w in ("inflacion", "ipc", "cpi", "precios al consumidor")),
        "alza_tasas": any(w in text for w in ("sube la tasa", "alza de tasas", "rate hike", "aumento de 75", "aumento de la tasa")),
        "baja_tasas": any(w in text for w in ("recorte", "baja de tasas", "rate cut", "recorta la tasa", "mantuvo inalterada")),
        "dolar_alza": any(w in text for w in ("dolar", "dólar", "trm", "depreci", "peso se debilita")),
        "petroleo": any(w in text for w in ("petroleo", "petróleo", "brent", "wti", "crudo", "opep")),
        "riesgo": any(w in text for w in ("caida", "caída", "selloff", "recesion", "recesión", "guerra", "arancel", "volatilidad")),
        "oficial": any(i.category == "oficial" for i in items),
        "banca": any(w in text for w in ("superfinanciera", "cartera", "credito", "crédito", "bancos")),
        "empleo": any(w in text for w in ("desempleo", "empleo", "nomina", "nómina", "payroll")),
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

    bits.append(
        "Para un perfil académico o de tesorería conservadora: 1) caja y tesorería de corto plazo; "
        "2) seguimiento de TRM, TES y Brent; 3) no tomar decisiones solo con un titular."
    )
    bits.append(DISCLAIMER)
    return " ".join(bits)


def recommend(items: list[NewsItem], use_llm: bool = True) -> str:
    baseline = rule_recommendation(items)
    if not use_llm:
        return baseline
    material = "\n".join(f"- {i.source_name}: {i.title}. {i.summary_es}" for i in items)
    polished = _llm_chat(
        [
            {"role": "system", "content": LLM_SYSTEM},
            {
                "role": "user",
                "content": (
                    "Con estas 7 noticias, redacta una recomendación financiera de coyuntura "
                    "en 3 párrafos cortos, tono de analista, para oyentes en Colombia. "
                    "Habla de tasas, dólar, liquidez y qué vigilar. No des tickers para comprar. "
                    f"Cierra el último párrafo con: {DISCLAIMER}\n\n{material}"
                ),
            },
        ]
    )
    return polished or baseline
