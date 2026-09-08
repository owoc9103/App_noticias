from __future__ import annotations

from io import BytesIO
from pathlib import Path

from src.config import IMPACT_LABELS, PODCAST_SIGN_OFF, PROFILES
from src.models import Briefing

WIN_FONT = Path(r"C:\Windows\Fonts\arial.ttf")
WIN_FONT_BOLD = Path(r"C:\Windows\Fonts\arialbd.ttf")


def briefing_pdf(briefing: Briefing) -> bytes:
    from fpdf import FPDF

    pdf = FPDF()
    pdf.set_auto_page_break(auto=True, margin=16)
    pdf.add_page()
    unicode_ok = WIN_FONT.exists()
    if unicode_ok:
        pdf.add_font("ArialUni", "", str(WIN_FONT))
        if WIN_FONT_BOLD.exists():
            pdf.add_font("ArialUni", "B", str(WIN_FONT_BOLD))
        font = "ArialUni"
    else:
        font = "Helvetica"

    def write(size: int, text: str, bold: bool = False) -> None:
        style = "B" if bold and unicode_ok and WIN_FONT_BOLD.exists() else ""
        pdf.set_x(pdf.l_margin)
        pdf.set_font(font, style=style, size=size)
        pdf.multi_cell(0, 6, text or " ", new_x="LMARGIN", new_y="NEXT")

    when = briefing.generated_at.strftime("%Y-%m-%d %H:%M") if briefing.generated_at else ""
    write(16, "Briefing económico DATA-LAB · Javeriana Cali", bold=True)
    write(10, f"{when} · Lectura académica de coyuntura, no es asesoría de inversión.")
    pdf.ln(2)
    if briefing.market:
        write(11, "Mercado", bold=True)
        write(10, "  ·  ".join(f"{k}: {v}" for k, v in briefing.market.items() if k != "Fuente"))
        pdf.ln(1)
    write(11, "Recomendación", bold=True)
    write(10, briefing.recommendation)
    pdf.ln(2)
    write(11, "Top 7", bold=True)
    for idx, item in enumerate(briefing.items, start=1):
        tags = ", ".join(IMPACT_LABELS.get(tag, tag) for tag in item.tags)
        write(11, f"{idx}. {item.title}", bold=True)
        meta = f"{item.source_name} · {item.why}"
        if tags:
            meta += f" · {tags}"
        write(9, meta)
        write(10, item.summary_es or "")
        pdf.ln(1)
    write(9, PODCAST_SIGN_OFF)
    out = BytesIO()
    pdf.output(out)
    return out.getvalue()


def briefing_share_text(briefing: Briefing) -> str:
    when = briefing.generated_at.strftime("%Y-%m-%d %H:%M") if briefing.generated_at else ""
    profile = PROFILES.get(briefing.profile, briefing.profile)
    lines = [
        "Briefing económico DATA-LAB · Javeriana Cali",
        f"{when} · perfil {profile}",
        "Lectura académica de coyuntura, no es asesoría de inversión.",
        "",
    ]
    if briefing.market:
        quotes = " · ".join(f"{k}: {v}" for k, v in briefing.market.items() if k != "Fuente")
        if quotes:
            lines.extend([quotes, ""])
    for idx, item in enumerate(briefing.items, start=1):
        tags = ", ".join(IMPACT_LABELS.get(tag, tag) for tag in item.tags)
        lines.append(f"{idx}. {item.title}")
        meta = item.source_name
        if tags:
            meta += f" · {tags}"
        lines.append(meta)
        if item.summary_es:
            lines.append(item.summary_es)
        lines.append("")
    lines.append("Recomendación")
    lines.append(briefing.recommendation)
    lines.append("")
    lines.append(PODCAST_SIGN_OFF)
    return "\n".join(lines)
