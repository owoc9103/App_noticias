from __future__ import annotations

import base64
import html
import sys
from datetime import timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

try:
    from dotenv import load_dotenv
except ImportError:
    def load_dotenv(*_args, **_kwargs):
        return False

load_dotenv(ROOT / ".env")

import streamlit as st

from src.config import ASSETS_DIR, DEFAULT_READER, READERS, SOURCES
from src.pipeline import reader_voice, run_briefing
from src.podcast import synthesize

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
                <p>La app consulta las fuentes, resume el cuerpo de cada nota y lo convierte en un podcast en español, con cierre financiero.</p>
              </div>
            </div>
            <div class="jl-badge">Audio siempre en español</div>
          </div>
        </div>
        """,
        unsafe_allow_html=True,
    )


def render_item(idx: int, item) -> None:
    when = item.published.strftime("%Y-%m-%d %H:%M") if item.published else "hora no reportada"
    st.markdown(
        f"""
        <div class="jl-card {item.category}">
          <div class="jl-meta">
            <span class="jl-rank">{idx}</span>
            <span>{item.source_name}</span>
            <span>{CAT_LABEL.get(item.category, item.category)}</span>
            <span>{when}</span>
          </div>
          <h3>{html.escape(item.title)}</h3>
          <p>{html.escape(item.summary_es)}</p>
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
        st.subheader("Podcast")
        st.caption(f"Lo lee: {current.reader_label}")
        if current.audio_note:
            st.warning(current.audio_note)
        if current.audio_path and Path(current.audio_path).exists():
            audio_bytes = Path(current.audio_path).read_bytes()
            suffix = Path(current.audio_path).suffix.lower()
            mime = "audio/wav" if suffix == ".wav" else "audio/mp3"
            st.audio(audio_bytes, format=mime)
            st.download_button(
                "Descargar audio",
                data=audio_bytes,
                file_name=Path(current.audio_path).name,
                mime=mime,
                use_container_width=True,
            )
            return
        if not st.session_state.get("audio_job"):
            st.caption("Active el podcast o pulse «Volver a narrar con esta voz».")
            return
        if not st.session_state.get("tts_armed"):
            st.session_state.tts_armed = True
            st.info("Preparando el podcast… ya puede leer el briefing.")
            return
        voice, _label, chosen = reader_voice(current.reader_key or reader_key)
        with st.spinner("Narrando el noticiero…"):
            try:
                current.audio_path = str(synthesize(current.script, voice=voice, reader_key=chosen))
                current.audio_note = (
                    "Se usó la voz local de Windows porque el servicio en la nube no estuvo disponible."
                    if current.audio_path.endswith(".wav")
                    else ""
                )
            except Exception as exc:
                current.audio_note = f"El briefing quedó listo, pero el audio falló: {exc}"
        st.session_state.briefing = current
        st.session_state.audio_job = False
        st.rerun()

    panel()


def main() -> None:
    load_css()
    hero()
    if "briefing" not in st.session_state:
        st.session_state.briefing = None
    if "audio_job" not in st.session_state:
        st.session_state.audio_job = False
    if "tts_armed" not in st.session_state:
        st.session_state.tts_armed = False

    with st.sidebar:
        st.header("Edición")
        st.caption("Las fuentes son las páginas oficiales. Si un sitio bloquea el acceso, se usa su canal RSS o Google News filtrado por ese dominio.")
        default_ids = [s.id for s in SOURCES]
        by_cat = {
            "Colombia · medios": [s for s in SOURCES if s.category == "nacional"],
            "Internacionales": [s for s in SOURCES if s.category == "internacional"],
            "Oficiales de Colombia": [s for s in SOURCES if s.category == "oficial"],
        }
        chosen: list[str] = []
        for label, group in by_cat.items():
            st.subheader(label)
            for source in group:
                if st.checkbox(source.name, value=True, key=f"src_{source.id}"):
                    chosen.append(source.id)
                st.caption(source.home)

        st.subheader("Quién lee las noticias")
        reader_keys = list(READERS)
        reader_choice = st.radio(
            "Locutor o locutora del podcast",
            options=reader_keys,
            index=reader_keys.index(DEFAULT_READER),
            format_func=lambda key: READERS[key]["label"],
            horizontal=True,
            help="Ambas voces son colombianas y mantienen el tono de noticiero en español.",
        )
        reader_key = reader_choice
        reader_info = READERS[reader_key]
        st.caption(f"Voz: {reader_info['name']} · {reader_info['accent']}")
        use_llm = st.toggle("Mejorar redacción con API (Groq u OpenAI)", value=False)
        use_cache = st.toggle("Usar caché de 25 minutos", value=True)
        make_audio = st.toggle("Generar podcast en español", value=True)
        st.caption("Opcional: cree un archivo .env con GROQ_API_KEY u OPENAI_API_KEY.")
        run = st.button("Generar briefing del día", type="primary", use_container_width=True)
        rerender = st.button(
            "Volver a narrar con esta voz",
            use_container_width=True,
            disabled=st.session_state.get("briefing") is None,
            help="Repite el audio del briefing actual, sin volver a consultar las fuentes.",
        )

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
            "Pulse **Generar briefing del día** para consultar las fuentes, extraer el top 7, "
            "resumir cada nota y producir el audio en español."
        )
        with st.expander("Fuentes que consulta la app"):
            for source in SOURCES:
                st.markdown(f"- **{source.name}** · [{source.home}]({source.home})")
        return

    left, right = st.columns((1.55, 1), gap="large")
    with left:
        st.subheader("Top 7")
        st.caption(f"{briefing.candidates} titulares evaluados · {briefing.generated_at.strftime('%Y-%m-%d %H:%M')} hora Colombia")
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
        _render_podcast_panel(briefing, reader_key)
        with st.expander("Guion del noticiero"):
            st.write(briefing.script)
        st.markdown('<p class="jl-signoff">Esto te lo dice la app de javeriana Cali</p>', unsafe_allow_html=True)
        if briefing.sources_ok:
            st.success("Fuentes con titulares: " + ", ".join(briefing.sources_ok))
        if briefing.sources_fail:
            st.warning("Sin piezas en esta ronda: " + ", ".join(briefing.sources_fail))


if __name__ == "__main__":
    main()

