# Briefing económico DATA-LAB · Javeriana Cali

Aplicación en Python y Streamlit que arma el **top 7** de noticias económicas de Colombia y el mundo, resume el cuerpo de cada nota, genera una **recomendación financiera de coyuntura** y lo convierte en un **podcast en español**.

El cierre del audio es siempre:

> Esto te lo dice la app de javeriana Cali

## Qué hace

1. Consulta las fuentes oficiales (RSS, portada o Google News filtrado por el dominio).
2. Extrae titular, fecha y cuerpo disponible de la nota.
3. Ordena por relevancia económica, actualidad y diversidad de fuentes.
4. Resume en español, aunque la pieza original esté en inglés.
5. Escribe una lectura financiera (tasas, dólar, petróleo, liquidez).
6. Sintetiza un noticiero con voz colombiana (`es-CO-GonzaloNeural` por defecto).

La app muestra resúmenes, no el texto completo de los medios. Cada tarjeta enlaza a la nota original.

## Fuentes

**Medios Colombia:** [La República](https://www.larepublica.co/), [Portafolio](https://www.portafolio.co/), [Bloomberg Línea Colombia](https://www.bloomberglinea.com/latinoamerica/colombia/), [Valora Analitik](https://www.valoraanalitik.com/), [Forbes Colombia](https://forbes.co/).

**Internacionales:** [Reuters](https://www.reuters.com/), [Bloomberg](https://www.bloomberg.com/), [Financial Times](https://www.ft.com/), [The Wall Street Journal](https://www.wsj.com/), [The Economist](https://www.economist.com/), [CNBC](https://www.cnbc.com/), [MarketWatch](https://www.marketwatch.com/).

**Oficiales:** [Banco de la República](https://www.banrep.gov.co/), [DANE](https://www.dane.gov.co/), [Superintendencia Financiera](https://www.superfinanciera.gov.co/), [Ministerio de Hacienda](https://www.minhacienda.gov.co/).

## Cómo ejecutar

En PowerShell, desde esta carpeta:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
streamlit run app.py
```

La interfaz queda en `http://localhost:8501`.

## Redacción con modelo (opcional)

Sin llaves la app resume con extracción de oraciones y traduce al español. Para un tono más de noticiero, copie `.env.example` a `.env` y agregue `GROQ_API_KEY` o `OPENAI_API_KEY`. En la barra lateral active **Mejorar redacción con API**.

## Aviso

La recomendación es académica y de coyuntura. No es asesoría de inversión personalizada. Sitios con muro de pago o protección antibot pueden entregar solo titular y entradilla; en esos casos el resumen se construye con el material público disponible.
