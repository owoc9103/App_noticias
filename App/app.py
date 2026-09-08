from __future__ import annotations

import base64
import html
import importlib
import sys
from datetime import datetime
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

import streamlit as st

import src.config as _config_mod

if not hasattr(_config_mod, "DEFAULT_PROFILE"):
    _config_mod = importlib.reload(_config_mod)

from src.config import ASSETS_DIR, DEFAULT_PROFILE, DEFAULT_READER, IMPACT_LABELS, PROFILES, READERS, SOURCES
from src.export_pdf import briefing_pdf, briefing_share_text
from src.history import list_history, load_briefing, load_today, save_briefing
from src.pipeline import reader_voice, run_briefing
from src.podcast import synthesize
from src.recommend import key_takeaways

BOGOTA = ZoneInfo("America/Bogota")
DISCLAIMER = "Lectura académica de coyuntura. No constituye asesoría de inversión."

SOURCE_GROUPS = (
    (
        "Internacionales",
        ("reuters", "bloomberg", "ft", "wsj", "economist", "cnbc", "marketwatch"),
    ),
    (
        "Colombia",
        (
            "banrep",
            "dane",
            "minhacienda",
            "superfinanciera",
            "larepublica",
            "portafolio",
            "bloomberglinea",
            "valora",
            "forbesco",
        ),
    ),
)

_page = {
    "page_title": "Market Briefing | DATA-LAB",
    "layout": "centered",
    "initial_sidebar_state": "collapsed",
}
if (ASSETS_DIR / "favicon.svg").exists():
    _page["page_icon"] = str(ASSETS_DIR / "favicon.svg")
st.set_page_config(**_page)


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


def init_state() -> None:
    defaults = {
        "briefing": load_today(),
        "audio_job": False,
        "drive_mode": str(st.query_params.get("drive", "")).lower() in {"1", "true", "si"},
        "pdf_bytes": None,
        "pdf_key": "",
    }
    for key, value in defaults.items():
        if key not in st.session_state:
            st.session_state[key] = value


def selected_source_ids() -> list[str]:
    chosen = [source.id for source in SOURCES if st.session_state.get(f"src_{source.id}", True)]
    return chosen or [source.id for source in SOURCES]


def audio_ready(briefing) -> bool:
    return bool(briefing and briefing.audio_path and Path(briefing.audio_path).exists())


def estimate_minutes(briefing) -> int:
    if not briefing:
        return 6
    words = len((briefing.script or "").split())
    if words:
        return max(4, min(8, round(words / 145)))
    return max(5, min(7, 1 + len(briefing.items)))


def format_date(stamp: datetime | None = None) -> str:
    now = stamp or datetime.now(BOGOTA)
    months = (
        "ene", "feb", "mar", "abr", "may", "jun",
        "jul", "ago", "sep", "oct", "nov", "dic",
    )
    return f"{now.day} {months[now.month - 1]} {now.year}"


def briefing_takeaways(briefing) -> list[str]:
    raw = [line.strip().lstrip("•- ") for line in (getattr(briefing, "takeaways", None) or []) if str(line).strip()]
    if raw:
        return raw[:3]
    rec = briefing.recommendation or ""
    lines = [line.strip().lstrip("•- ") for line in rec.splitlines() if line.strip()]
    lines = [
        line
        for line in lines
        if "asesoría" not in line.lower() and "asesoria" not in line.lower() and len(line) < 200
    ]
    if lines:
        return lines[:3]
    return key_takeaways(briefing.items)


def compact_header(briefing=None) -> None:
    logo = ASSETS_DIR / "javeriana-logo-azul.svg"
    img = ""
    if logo.exists():
        encoded = base64.b64encode(logo.read_bytes()).decode("ascii")
        img = f'<img src="data:image/svg+xml;base64,{encoded}" alt="Javeriana Cali" />'
    stories = len(briefing.items) if briefing else "—"
    minutes = estimate_minutes(briefing) if briefing else "5–7"
    when = format_date(briefing.generated_at if briefing and briefing.generated_at else None)
    st.markdown(
        f"""
        <div class="jl-hero">
          <div class="jl-brandline">{img}<span>DATA-LAB · JAVERIANA CALI</span></div>
          <h1>Market Briefing</h1>
          <p class="jl-sub">Global markets &amp; Colombia</p>
          <p class="jl-meta-line">{when} · {stories} stories · {minutes} min</p>
        </div>
        """,
        unsafe_allow_html=True,
    )


def render_player(briefing) -> None:
    st.markdown('<div class="jl-player-dock">', unsafe_allow_html=True)
    if briefing.audio_note:
        st.caption(briefing.audio_note)
    audio_path = Path(briefing.audio_path)
    mime = audio_mime(audio_path)
    st.audio(str(audio_path.resolve()), format=mime, autoplay=False)
    if not st.session_state.get("drive_mode"):
        st.download_button(
            "Descargar audio",
            data=audio_path.read_bytes(),
            file_name=audio_path.name,
            mime=mime,
            use_container_width=True,
        )
    st.markdown("</div>", unsafe_allow_html=True)


def narrate(briefing, reader_key: str):
    voice, reader_label, chosen = reader_voice(briefing.reader_key or reader_key)
    briefing.reader_key = chosen
    briefing.reader_label = reader_label
    briefing.audio_path = str(
        synthesize(
            briefing.script,
            voice=voice,
            reader_key=chosen,
            items=briefing.items,
            recommendation=briefing.recommendation,
        )
    )
    briefing.audio_note = (
        ""
        if briefing.audio_path.endswith(".mp3")
        else "Audio en WAV. En el celular, descárguelo si el reproductor no abre."
    )
    return briefing


def generate_edition(reader_key: str, profile: str, use_llm: bool, use_cache: bool, make_audio: bool):
    briefing = run_briefing(
        source_ids=selected_source_ids(),
        reader_key=reader_key,
        profile=profile,
        use_llm=use_llm,
        use_cache=use_cache,
        make_audio=False,
        progress=None,
    )
    if make_audio:
        briefing = narrate(briefing, reader_key)
        try:
            save_briefing(briefing)
        except OSError:
            pass
    return briefing


def render_sidebar():
    drive = st.session_state.get("drive_mode", False)
    with st.sidebar:
        st.markdown("### Configuración")
        if drive:
            st.caption("Modo al volante. Cierre el panel para oír sin distracciones.")
            return DEFAULT_PROFILE, DEFAULT_READER, True, True, False

        with st.expander("Celular", expanded=False):
            st.caption(f"{lan_url()}/?drive=1")

        profile = st.radio(
            "Perfil",
            options=list(PROFILES),
            index=list(PROFILES).index(DEFAULT_PROFILE),
            format_func=lambda key: PROFILES[key],
            horizontal=True,
        )
        reader_keys = list(READERS)
        reader_choice = st.radio(
            "Voz",
            options=reader_keys,
            index=reader_keys.index(DEFAULT_READER),
            format_func=lambda key: READERS[key]["label"],
            horizontal=True,
        )
        st.caption(f"{READERS[reader_choice]['name']} · Kokoro")

        with st.expander("Fuentes", expanded=False):
            known = {source.id for source in SOURCES}
            listed: set[str] = set()
            for label, ids in SOURCE_GROUPS:
                st.caption(label)
                for source_id in ids:
                    source = next((item for item in SOURCES if item.id == source_id), None)
                    if not source:
                        continue
                    listed.add(source.id)
                    st.checkbox(source.name, value=True, key=f"src_{source.id}")
            extras = [source for source in SOURCES if source.id not in listed and source.id in known]
            if extras:
                st.caption("Otras")
                for source in extras:
                    st.checkbox(source.name, value=True, key=f"src_{source.id}")

        use_llm = st.toggle("Mejorar redacción con API", value=False)
        use_cache = st.toggle("Usar caché", value=True)
        make_audio = st.toggle("Generar podcast", value=True)
        refresh = st.button("Actualizar edición", use_container_width=True, key="run_sidebar")
        rerender = st.button(
            "Volver a narrar",
            use_container_width=True,
            key="rerender_sidebar",
            disabled=st.session_state.get("briefing") is None,
        )
        history_files = list_history()
        if history_files:
            with st.expander("Historial", expanded=False):
                labels = [path.stem for path in history_files]
                pick = st.selectbox("Edición guardada", labels, key="history_pick")
                if st.button("Abrir esta edición", use_container_width=True):
                    loaded = load_briefing(datetime.strptime(pick, "%Y-%m-%d").replace(tzinfo=BOGOTA))
                    if loaded:
                        st.session_state.briefing = loaded
                        st.session_state.audio_job = False
                        st.rerun()
        return profile, reader_choice, use_llm, use_cache, make_audio, refresh, rerender


def render_exports(briefing) -> None:
    when = briefing.generated_at.strftime("%Y-%m-%d %H:%M") if briefing.generated_at else ""
    stamp = when.replace(":", "").replace(" ", "_") or "hoy"
    pdf_key = f"{stamp}_{briefing.profile}_{briefing.candidates}_{len(briefing.items)}"
    if st.session_state.get("pdf_key") != pdf_key:
        try:
            st.session_state.pdf_bytes = briefing_pdf(briefing)
            st.session_state.pdf_key = pdf_key
        except Exception:
            st.session_state.pdf_bytes = None
            st.session_state.pdf_key = pdf_key
    with st.expander("Exportar", expanded=False):
        if st.session_state.get("pdf_bytes"):
            st.download_button(
                "PDF",
                data=st.session_state.pdf_bytes,
                file_name=f"market_brief_{stamp}.pdf",
                mime="application/pdf",
                use_container_width=True,
            )
        st.download_button(
            "Texto",
            data=briefing_share_text(briefing).encode("utf-8"),
            file_name=f"market_brief_{stamp}.txt",
            mime="text/plain",
            use_container_width=True,
        )
        if briefing.script:
            st.caption("Guion")
            st.write(briefing.script)


def render_rundown(briefing) -> None:
    rows = []
    for item in briefing.items:
        lang = "EN" if getattr(item, "language", "") == "en" else "ES"
        tags = " · ".join(IMPACT_LABELS.get(tag, tag) for tag in item.tags[:2])
        extra = f" · {tags}" if tags else ""
        rows.append(
            f"<li><span>{html.escape(item.source_name)} · {lang}{html.escape(extra)}</span>"
            f"{html.escape(item.title)}</li>"
        )
    st.markdown(f'<ol class="jl-rundown">{"".join(rows)}</ol>', unsafe_allow_html=True)


def render_takeaways(briefing) -> None:
    points = "".join(f"<li>{html.escape(point)}</li>" for point in briefing_takeaways(briefing))
    st.markdown(
        f"""
        <section class="jl-takeaways">
          <h2>Key Takeaways</h2>
          <ul>{points}</ul>
        </section>
        """,
        unsafe_allow_html=True,
    )


def main() -> None:
    load_css()
    init_state()

    drive = bool(st.session_state.get("drive_mode"))
    if drive:
        st.markdown(
            "<style>section[data-testid='stSidebar']{display:none!important}</style>",
            unsafe_allow_html=True,
        )

    sidebar = render_sidebar()
    if len(sidebar) == 5:
        profile, reader_key, use_llm, use_cache, make_audio = sidebar
        refresh = False
        rerender = False
    else:
        profile, reader_key, use_llm, use_cache, make_audio, refresh, rerender = sidebar

    compact_header(st.session_state.get("briefing"))

    if not drive:
        st.toggle(
            "Modo al volante",
            key="drive_mode",
            help="Deja solo título, duración y reproductor.",
        )

    has_audio = audio_ready(st.session_state.get("briefing"))
    listen = False
    if not (drive and has_audio):
        listen = st.button("▶ Escuchar briefing", type="primary", use_container_width=True, key="listen_main")

    if (refresh or listen) and (refresh or not audio_ready(st.session_state.get("briefing"))):
        try:
            if refresh or st.session_state.briefing is None:
                with st.spinner("Armando el briefing…"):
                    briefing = generate_edition(
                        reader_key,
                        profile,
                        use_llm,
                        use_cache,
                        make_audio or bool(listen),
                    )
                st.session_state.briefing = briefing
            elif listen and not audio_ready(st.session_state.briefing):
                with st.spinner("Narrando el briefing…"):
                    briefing = narrate(st.session_state.briefing, reader_key)
                    st.session_state.briefing = briefing
                    try:
                        save_briefing(briefing)
                    except OSError:
                        pass
        except Exception as exc:
            st.error(f"No se pudo armar la edición: {exc}")
            return

    if rerender and st.session_state.briefing:
        try:
            with st.spinner("Narrando el briefing…"):
                briefing = st.session_state.briefing
                briefing.audio_path = ""
                briefing.audio_note = ""
                st.session_state.briefing = narrate(briefing, reader_key)
                try:
                    save_briefing(st.session_state.briefing)
                except OSError:
                    pass
        except Exception as exc:
            st.error(f"El audio no se pudo generar: {exc}")

    briefing = st.session_state.briefing
    if not briefing:
        st.markdown(
            '<p class="jl-empty">Pulse <strong>Escuchar briefing</strong> para armar Global markets &amp; Colombia en 5–7 minutos.</p>',
            unsafe_allow_html=True,
        )
        if drive and st.button("Salir del modo al volante", use_container_width=True, key="exit_drive_empty"):
            st.session_state.drive_mode = False
            st.rerun()
        return

    minutes = estimate_minutes(briefing)
    if drive:
        st.markdown(
            f'<p class="jl-drive-meta">{len(briefing.items)} stories · {minutes} min</p>',
            unsafe_allow_html=True,
        )
        if audio_ready(briefing):
            render_player(briefing)
        else:
            st.caption("Pulse el botón de arriba y luego play.")
        st.markdown(f'<p class="jl-disclaimer">{DISCLAIMER}</p>', unsafe_allow_html=True)
        if st.button("Salir del modo al volante", use_container_width=True, key="exit_drive"):
            st.session_state.drive_mode = False
            st.rerun()
        return

    if audio_ready(briefing):
        render_player(briefing)
    else:
        st.caption("El briefing está listo. Pulse el botón para generar el audio.")

    render_rundown(briefing)
    render_takeaways(briefing)
    st.markdown(f'<p class="jl-disclaimer">{DISCLAIMER}</p>', unsafe_allow_html=True)
    render_exports(briefing)


if __name__ == "__main__":
    main()
