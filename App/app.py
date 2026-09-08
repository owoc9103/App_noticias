from __future__ import annotations

import base64
import html
import sys
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

try:
    from dotenv import load_dotenv
except ImportError:
    def load_dotenv(*_args, **_kwargs):
        return False

load_dotenv(ROOT / ".env")

import importlib

import streamlit as st

import src.config as _config_mod

if not hasattr(_config_mod, "DEFAULT_PROFILE"):
    _config_mod = importlib.reload(_config_mod)

from src.config import ASSETS_DIR, DEFAULT_PROFILE, DEFAULT_READER, IMPACT_LABELS, PROFILES, READERS, SOURCES
from src.export_pdf import briefing_pdf, briefing_share_text
from src.history import list_history, load_briefing, load_today, save_briefing
from src.pipeline import reader_voice, run_briefing
from src.podcast import synthesize

BOGOTA = ZoneInfo("America/Bogota")

_page = {
    "page_title": "Briefing DATA-LAB | Javeriana Cali",
    "layout": "wide",
}
if (ASSETS_DIR / "favicon.svg").exists():
    _page["page_icon"] = str(ASSETS_DIR / "favicon.svg")
st.set_page_config(**_page)

CAT_LABEL = {
    "nacional": "Colombia · medios",
    "internacional": "Mundo",
    "oficial": "Fuente oficial",
}
QUALITY_LABEL = {
    "cuerpo": "Cuerpo de la nota",
    "entradilla": "Solo entradilla pública",
    "titular": "Solo titular público",
}


def lan_url() -> str:
    import socket

    try:
        port = int(st.get_option("server.port") or 8501)
    except Exception:
        port = 8501
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        ip = sock.getsockname()[0]
    except OSError:
        ip = "127.0.0.1"
    finally:
        sock.close()
    return f"http://{ip}:{port}"


def audio_mime(path: Path) -> str:
    return "audio/wav" if path.suffix.lower() == ".wav" else "audio/mpeg"


def load_css() -> None:
    css = (ASSETS_DIR / "styles.css").read_text(encoding="utf-8")
    st.markdown(f"<style>{css}</style>", unsafe_allow_html=True)


def hero() -> None:
    logo = ASSETS_DIR / "javeriana-logo-azul.svg"
    img = ""
    if logo.exists():
        encoded = base64.b64encode(logo.read_bytes()).decode("ascii")
        img = f'<img src="data:image/svg+xml;base64,{encoded}" alt="Javeriana Cali" />'
    st.markdown(
        f"""
        <div class="jl-hero">
          <div class="jl-hero-row">
            <div class="jl-brand">
              {img}
              <div>
                <p class="jl-kicker">DATA LAB · Pontificia Universidad Javeriana Cali</p>
                <h1>Briefing económico: top 7 noticias</h1>
                <p>Más mundo que plaza local. Colombia en español; Reuters, FT o Bloomberg se oyen en inglés. Pensado para el carro.</p>
              </div>
            </div>
            <div class="jl-badge">Podcast bilingüe</div>
          </div>
        </div>
        """,
        unsafe_allow_html=True,
    )


def render_item(idx: int, item) -> None:
    when = item.published.strftime("%Y-%m-%d %H:%M") if item.published else "hora no reportada"
    chips = "".join(
        f'<span class="jl-chip">{html.escape(IMPACT_LABELS.get(tag, tag))}</span>'
        for tag in item.tags
    )
    st.markdown(
        f"""
        <div class="jl-card {item.category}">
          <div class="jl-meta">
            <span class="jl-rank">{idx}</span>
            <span>{html.escape(item.source_name)}</span>
            <span>{CAT_LABEL.get(item.category, item.category)}</span>
            <span>{when}</span>
            <span>{QUALITY_LABEL.get(item.body_quality, item.body_quality)}</span>
            <span>{"EN" if getattr(item, "language", "") == "en" else "ES"}</span>
          </div>
          <h3>{html.escape(item.title)}</h3>
          <p>{html.escape(item.summary_es)}</p>
          <p class="jl-why">{html.escape(item.why)}</p>
          <div class="jl-chips">{chips}</div>
        </div>
        """,
        unsafe_allow_html=True,
    )
    st.link_button("Abrir la nota original", item.url, use_container_width=False)


def _render_podcast_panel(briefing, reader_key: str) -> None:
    fragment_kw = {"run_every": timedelta(seconds=1)} if st.session_state.get("audio_job") else {}

    @st.fragment(**fragment_kw)
    def panel() -> None:
        current = st.session_state.get("briefing") or briefing
        st.markdown('<div class="jl-drive">', unsafe_allow_html=True)
        st.subheader("Escuchar en el carro")
        st.caption(
            f"Lo lee: {current.reader_label} · español de Cali e inglés de noticiero. "
            "Un toque a play; en iPhone, si no suena, descargue el MP3."
        )
        if current.audio_note:
            st.warning(current.audio_note)
        if current.audio_path and Path(current.audio_path).exists():
            audio_path = Path(current.audio_path)
            mime = audio_mime(audio_path)
            st.audio(str(audio_path.resolve()), format=mime, autoplay=st.session_state.get("drive_mode", False))
            st.download_button(
                "Descargar MP3 para el celular o el carro",
                data=audio_path.read_bytes(),
                file_name=audio_path.with_suffix(".mp3" if mime == "audio/mpeg" else audio_path.suffix).name,
                mime=mime,
                use_container_width=True,
            )
            if not st.session_state.get("drive_mode"):
                st.caption("Capítulos")
                for idx, item in enumerate(current.items, start=1):
                    lang = "EN" if item.language == "en" else "ES"
                    st.markdown(f"{idx}. [{lang}] {item.source_name}: {item.title}")
                st.markdown(f"{len(current.items) + 1}. Recomendación financiera")
            st.markdown("</div>", unsafe_allow_html=True)
            return
        if not st.session_state.get("audio_job"):
            st.caption("Pulse «Volver a narrar» para armar el audio. En el celular, descargue el MP3 y reprodúzcalo con la pantalla bloqueada.")
            st.markdown("</div>", unsafe_allow_html=True)
            return
        if not st.session_state.get("tts_armed"):
            st.session_state.tts_armed = True
            st.info("Preparando el podcast… ya puede manejar; el audio aparece aquí en unos segundos.")
            st.markdown("</div>", unsafe_allow_html=True)
            return
        voice, _label, chosen = reader_voice(current.reader_key or reader_key)
        with st.spinner("Narrando el noticiero bilingüe…"):
            try:
                current.audio_path = str(
                    synthesize(
                        current.script,
                        voice=voice,
                        reader_key=chosen,
                        items=current.items,
                        recommendation=current.recommendation,
                    )
                )
                current.audio_note = (
                    "Se usó la voz local de Windows. Si el celular no reproduce WAV, descargue el archivo o vuelva a narrar con red."
                    if current.audio_path.endswith(".wav")
                    else ""
                )
            except Exception as exc:
                current.audio_note = f"El briefing quedó listo, pero el audio falló: {exc}"
        st.session_state.briefing = current
        st.session_state.audio_job = False
        try:
            save_briefing(current)
        except OSError:
            pass
        st.rerun()

    panel()


def main() -> None:
    load_css()
    hero()
    if "briefing" not in st.session_state:
        st.session_state.briefing = load_today()
    if "audio_job" not in st.session_state:
        st.session_state.audio_job = False
    if "tts_armed" not in st.session_state:
        st.session_state.tts_armed = False
    if "drive_mode" not in st.session_state:
        st.session_state.drive_mode = str(st.query_params.get("drive", "")).lower() in {"1", "true", "si"}

    phone = f"{lan_url()}/?drive=1"
    st.markdown(
        f"<div class='jl-lan'><strong>En el celular:</strong> misma Wi-Fi y abra "
        f"<a href='{html.escape(phone)}'>{html.escape(phone)}</a>. "
        "Si no carga, permita Python en el firewall de Windows. "
        "Para manejar: Modo al volante → Play o descargue el MP3.</div>",
        unsafe_allow_html=True,
    )
    top_l, top_r = st.columns(2)
    with top_l:
        st.toggle(
            "Modo al volante",
            key="drive_mode",
            help="Deja el reproductor arriba, esconde el texto y sirve para oír mientras maneja.",
        )
    with top_r:
        run_main = st.button("Generar / actualizar briefing", type="primary", use_container_width=True, key="run_main")
    rerender_main = st.button(
        "Volver a narrar",
        use_container_width=True,
        key="rerender_main",
        disabled=st.session_state.get("briefing") is None,
    )

    with st.sidebar:
        st.header("Edición")
        st.caption("Si ya hay briefing de hoy, se abre de inmediato. Generar de nuevo actualiza la edición.")
        st.caption(f"URL del celular: {phone}")
        profile = st.radio(
            "Perfil de lectura",
            options=list(PROFILES),
            index=list(PROFILES).index(DEFAULT_PROFILE),
            format_func=lambda key: PROFILES[key],
            horizontal=True,
        )
        default_ids = [s.id for s in SOURCES]
        chosen: list[str] = []
        with st.expander("Fuentes", expanded=False):
            by_cat = {
                "Colombia · medios": [s for s in SOURCES if s.category == "nacional"],
                "Internacionales": [s for s in SOURCES if s.category == "internacional"],
                "Oficiales de Colombia": [s for s in SOURCES if s.category == "oficial"],
            }
            for label, group in by_cat.items():
                st.caption(label)
                for source in group:
                    if st.checkbox(source.name, value=True, key=f"src_{source.id}"):
                        chosen.append(source.id)

        st.subheader("Quién lee las noticias")
        reader_keys = list(READERS)
        reader_choice = st.radio(
            "Locutor o locutora del podcast",
            options=reader_keys,
            index=reader_keys.index(DEFAULT_READER),
            format_func=lambda key: READERS[key]["label"],
            horizontal=True,
            help="Español con acento caleño; las notas en inglés las lee una voz de noticiero en inglés.",
        )
        reader_key = reader_choice
        reader_info = READERS[reader_key]
        st.caption(f"Voz ES: {reader_info['name']} · {reader_info['accent']} · EN: noticiero")
        use_llm = st.toggle("Mejorar redacción con API (Groq u OpenAI)", value=False)
        use_cache = st.toggle("Usar caché de 25 minutos", value=True)
        make_audio = st.toggle("Generar podcast bilingüe", value=True)
        st.caption("Opcional: cree un archivo .env con GROQ_API_KEY u OPENAI_API_KEY.")
        run = st.button("Generar briefing del día", type="primary", use_container_width=True, key="run_sidebar")
        rerender = st.button(
            "Volver a narrar con esta voz",
            use_container_width=True,
            key="rerender_sidebar",
            disabled=st.session_state.get("briefing") is None,
            help="Repite el audio del briefing actual, sin volver a consultar las fuentes.",
        )

    run = run or run_main
    rerender = rerender or rerender_main

    if rerender and st.session_state.briefing:
        briefing = st.session_state.briefing
        _, reader_label, reader_key = reader_voice(reader_key)
        briefing.audio_path = ""
        briefing.reader_key = reader_key
        briefing.reader_label = reader_label
        briefing.audio_note = ""
        st.session_state.briefing = briefing
        st.session_state.audio_job = True
        st.session_state.tts_armed = False

    if run:
        if not chosen:
            st.warning("Seleccione al menos una fuente.")
            return
        status = st.status("Preparando la edición…", expanded=True)
        def progress(message: str) -> None:
            status.write(message)
        try:
            briefing = run_briefing(
                source_ids=chosen or default_ids,
                reader_key=reader_key,
                profile=profile,
                use_llm=use_llm,
                use_cache=use_cache,
                make_audio=False,
                progress=progress,
            )
            st.session_state.briefing = briefing
            st.session_state.audio_job = make_audio
            st.session_state.tts_armed = False
            status.update(label="Edición lista. El podcast se arma en segundo plano.", state="complete")
        except Exception as exc:
            status.update(label="No se pudo completar la edición", state="error")
            st.error(f"Error al construir el briefing: {exc}")
            return

    briefing = st.session_state.briefing
    if not briefing:
        st.info(
            "Pulse **Generar briefing del día** para armar el top 7. "
            "Si ya se generó hoy, la próxima apertura lo muestra al instante."
        )
        with st.expander("Fuentes que consulta la app"):
            for source in SOURCES:
                st.markdown(f"- **{source.name}** · [{source.home}]({source.home})")
        return

    st.markdown(
        "<div class='jl-disclaimer'><strong>Aviso:</strong> esta es una lectura académica de coyuntura "
        "del DATA-LAB. No es asesoría de inversión personalizada ni una orden de compra o venta.</div>",
        unsafe_allow_html=True,
    )

    _render_podcast_panel(briefing, reader_key)
    when = briefing.generated_at.strftime("%Y-%m-%d %H:%M") if briefing.generated_at else ""
    drive_mode = st.session_state.get("drive_mode", False)

    if drive_mode:
        st.markdown(
            f"""
            <div class="jl-reco">
              <h2>Recomendación</h2>
              <p>{html.escape(briefing.recommendation).replace(chr(10), "<br/>")}</p>
            </div>
            """,
            unsafe_allow_html=True,
        )
        st.caption("Modo al volante: las fichas quedan ocultas. Apáguelo para leer el top 7.")
        return

    if briefing.market:
        cells = "".join(
            f"<div><span>{html.escape(key)}</span><strong>{html.escape(str(value))}</strong></div>"
            for key, value in briefing.market.items()
            if key != "Fuente"
        )
        st.markdown(f"<div class='jl-market'>{cells}</div>", unsafe_allow_html=True)

    if briefing.delta_vs_yesterday:
        with st.expander("Qué cambió vs ayer", expanded=True):
            for line in briefing.delta_vs_yesterday:
                st.markdown(f"- {line}")

    left, right = st.columns((1.55, 1), gap="large")
    with left:
        intl = sum(1 for item in briefing.items if item.category == "internacional")
        st.subheader("Top 7")
        st.caption(
            f"{briefing.candidates} titulares · {intl} internacionales · {when} hora Colombia · "
            f"perfil {PROFILES.get(briefing.profile, briefing.profile)}"
        )
        for idx, item in enumerate(briefing.items, start=1):
            render_item(idx, item)

    with right:
        st.markdown(
            f"""
            <div class="jl-reco">
              <h2>Recomendación financiera</h2>
              <p>{html.escape(briefing.recommendation).replace(chr(10), "<br/>")}</p>
            </div>
            """,
            unsafe_allow_html=True,
        )
        stamp = when.replace(":", "").replace(" ", "_") or "hoy"
        pdf_key = f"{stamp}_{briefing.profile}_{briefing.candidates}_{len(briefing.items)}"
        if st.session_state.get("pdf_key") != pdf_key:
            try:
                st.session_state.pdf_bytes = briefing_pdf(briefing)
                st.session_state.pdf_key = pdf_key
            except Exception:
                st.session_state.pdf_bytes = None
                st.session_state.pdf_key = pdf_key
        if st.session_state.get("pdf_bytes"):
            st.download_button(
                "Descargar briefing en PDF",
                data=st.session_state.pdf_bytes,
                file_name=f"briefing_datalab_{stamp}.pdf",
                mime="application/pdf",
                use_container_width=True,
            )
        else:
            st.caption("El PDF no se pudo armar en este equipo.")
        st.download_button(
            "Descargar texto para WhatsApp o correo",
            data=briefing_share_text(briefing).encode("utf-8"),
            file_name=f"briefing_datalab_{stamp}.txt",
            mime="text/plain",
            use_container_width=True,
        )
        with st.expander("Guion del noticiero"):
            st.write(briefing.script)
        history_files = list_history()
        if history_files:
            with st.expander("Historial"):
                labels = [path.stem for path in history_files]
                pick = st.selectbox("Edición guardada", labels, key="history_pick")
                if st.button("Abrir esta edición", use_container_width=True):
                    loaded = load_briefing(datetime.strptime(pick, "%Y-%m-%d").replace(tzinfo=BOGOTA))
                    if loaded:
                        st.session_state.briefing = loaded
                        st.session_state.audio_job = False
                        st.session_state.tts_armed = False
                        st.rerun()
                    else:
                        st.caption("No se pudo abrir esa edición.")
        st.markdown('<p class="jl-signoff">Esto te lo dice la app de javeriana Cali</p>', unsafe_allow_html=True)
        if briefing.sources_ok:
            st.success("Fuentes con titulares: " + ", ".join(briefing.sources_ok))
        if briefing.sources_fail:
            st.warning("Sin piezas en esta ronda: " + ", ".join(briefing.sources_fail))


if __name__ == "__main__":
    main()

