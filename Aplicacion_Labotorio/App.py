import streamlit as st
from streamlit_option_menu import option_menu

st.set_page_config(layout="wide")

# --- Barra principal ---
selected = option_menu(
    menu_title=None,
    options=[
        "Inicio", "Quiénes Somos", "Docencia", "Consultoría",
        "Investigación", "Visualizaciones", "Servicios", "Contacto"
    ],
    icons=[
        "house", "people", "book", "briefcase",
        "search", "bar-chart", "gear", "envelope"
    ],
    orientation="horizontal",
    styles={
        "container": {"background-color": "#003366"},
        "icon": {"color": "white", "font-size": "20px"},
        "nav-link": {"color": "white", "font-size": "18px", "padding": "10px"},
        "nav-link-selected": {"background-color": "#FFD700", "color": "black"},
    }
)

# --- Contenido dinámico ---
if selected == "Inicio":
    st.title("Bienvenido al Laboratorio de Analítica")
    st.markdown("""
    
    **Pontificia Universidad Javeriana Cali**

    Bienvenido al **Laboratorio de Analítica**, un espacio diseñado para explorar, experimentar y aprender sobre **análisis de datos, minería de información y machine learning**.  

    Aquí podrás:

    - 💡 Aplicar conceptos de **estadística y análisis de datos** en casos prácticos.  
    - 📊 Visualizar información de manera interactiva usando herramientas modernas.  
    - 🤖 Experimentar con **modelos de machine learning y algoritmos de inteligencia artificial**.  
    - 🧪 Desarrollar proyectos que integren teoría y práctica, fortaleciendo tu aprendizaje.

    > Este laboratorio busca fomentar la curiosidad, la creatividad y la capacidad de **tomar decisiones basadas en datos**. ¡Prepárate para explorar y descubrir!

    """)

elif selected == "Quiénes Somos":


    st.markdown("""
    # 👥 Quiénes Somos
    **Laboratorio de Analítica**  
    **Pontificia Universidad Javeriana Cali**

    Somos un equipo apasionado por **la ciencia de datos, la analítica avanzada y la inteligencia artificial**, comprometidos con la formación de estudiantes y profesionales capaces de **tomar decisiones basadas en datos**.

    Nuestro laboratorio tiene como objetivos:

    - 🔍 Fomentar la **investigación aplicada** en análisis de datos.  
    - 📊 Desarrollar proyectos innovadores que integren **estadística, machine learning y visualización de datos**.  
    - 🤝 Colaborar con docentes y estudiantes para fortalecer el aprendizaje práctico y la resolución de problemas reales.  
    - 🌱 Crear un espacio de **curiosidad, experimentación y crecimiento profesional** en analítica de datos.

    Creemos en la **educación colaborativa** y en el poder de los datos para transformar la sociedad y los negocios.  
    ¡Únete a nosotros y sé parte de la exploración analítica!  
    """)


elif selected == "Docencia":
    st.title("Docencia")
    st.write("Selecciona una subopción:")

    sub_selected = option_menu(
        menu_title=None,
        options=["Cursos", "Programas", "Capacitaciones"],
        icons=["book", "mortarboard", "chalkboard-teacher"],
        orientation="horizontal",
        styles={
            "container": {"background-color": "#f0f0f0"},
            "icon": {"color": "black", "font-size": "16px"},
            "nav-link": {"color": "black", "font-size": "16px"},
            "nav-link-selected": {"background-color": "#FFD700", "color": "black"},
        }
    )

    if sub_selected == "Cursos":

        st.markdown("""
        # 📚 Cursos Impactados:

        A continuación se presentan los cursos que se beneficiarán de los procesos de **Gestión Humana**, organizados por departamento:

        ## 🏛️ Departamento de Organizaciones
        - **Administración de Recursos Humanos**  
        - **Desarrollo Organizacional**  

        ## ⚙️ Departamento de Finanzas
        - **Gestión Financiera**  
        - **Planeación y Control Financiero**  

        ## 📈 Departamento de Mercadeo
        - **Investigación de Mercados**  
        - **Gestión de Marca y Publicidad**  

        ## 🌐 Departamento de Negocios Internacionales
        - **Comercio Internacional**  
        - **Negociación y Estrategias Globales**  

        > Estos cursos integran estrategias y prácticas de **Gestión Humana** para fortalecer las habilidades de los estudiantes y profesionales en sus respectivas áreas.
        """)
    elif sub_selected == "Programas":
        st.markdown("""
        # 📚 Programas:

        A continuación se presentan los cursos que se beneficiarán de los procesos de **Gestión Humana**, organizados por departamento:
        ## Finanzas
     
        ## Economía
        
        ## Administración de Empresas
        
        ## Mercadeo y Negocios Internacionales
        """)
    elif sub_selected == "Capacitaciones":
        st.subheader("🧑‍🏫 Capacitaciones")
        st.write("Capacitaciones disponibles para la comunidad.")

elif selected == "Consultoría":
    st.title("Consultoría")

elif selected == "Investigación":
    st.title("Investigación")

elif selected == "Visualizaciones":
    st.title("Visualizaciones")

elif selected == "Servicios":
    st.title("Servicios")

elif selected == "Contacto":
    st.title("Contacto")
