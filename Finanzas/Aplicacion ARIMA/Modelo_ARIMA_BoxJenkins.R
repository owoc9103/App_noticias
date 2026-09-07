# ===================================================================
# ESTIMACIÓN DE MODELO ARIMA PARA DERIVADOS FINANCIEROS
# METODOLOGÍA BOX-JENKINS
# ===================================================================
# 
# Este script implementa la metodología Box-Jenkins para la estimación
# de modelos ARIMA (AutoRegressive Integrated Moving Average) aplicada
# a precios de derivados financieros.
#
# La metodología Box-Jenkins consta de tres etapas:
# 1. IDENTIFICACIÓN: Determinar los órdenes (p,d,q) del modelo ARIMA
# 2. ESTIMACIÓN: Estimar los parámetros del modelo identificado
# 3. DIAGNÓSTICO: Validar que el modelo cumple los supuestos estadísticos
#
# Autor: Laboratorio de Analítica
# Fecha: 2025
# ===================================================================

# ------------------------------------------------------------
# INSTALACIÓN Y CARGA DE LIBRERÍAS NECESARIAS
# ------------------------------------------------------------

# Verificar e instalar librerías si es necesario
paquetes_requeridos <- c("quantmod", "forecast", "tseries", "ggplot2", 
                         "gridExtra", "dplyr", "tidyr", "urca", "lmtest")

# Función para instalar paquetes faltantes
instalar_paquetes <- function(paquetes) {
  paquetes_faltantes <- paquetes[!(paquetes %in% installed.packages()[,"Package"])]
  if(length(paquetes_faltantes) > 0) {
    cat("Instalando paquetes faltantes:", paste(paquetes_faltantes, collapse = ", "), "\n")
    install.packages(paquetes_faltantes, dependencies = TRUE)
  }
}

# Instalar paquetes si es necesario
instalar_paquetes(paquetes_requeridos)

# Cargar librerías
library(quantmod)      # Para descargar datos financieros
library(forecast)      # Para modelos ARIMA y pronósticos
library(tseries)       # Para pruebas estadísticas de series de tiempo
library(ggplot2)       # Para visualizaciones
library(gridExtra)     # Para organizar múltiples gráficos
library(dplyr)         # Para manipulación de datos
library(tidyr)          # Para transformación de datos (pivot_longer)
library(urca)          # Para pruebas de raíz unitaria (ADF, KPSS)
library(lmtest)        # Para pruebas de diagnóstico (Ljung-Box, etc.)

cat("\n=== LIBRERÍAS CARGADAS EXITOSAMENTE ===\n\n")

# ------------------------------------------------------------
# CONFIGURACIÓN DE PARÁMETROS Y RUTAS
# ------------------------------------------------------------

# Función para solicitar y normalizar la ruta de resultados
# Esta función convierte backslashes (\) a forward slashes (/) para compatibilidad con R
solicitar_ruta_resultados <- function() {
  cat("\n=== CONFIGURACIÓN DE RUTA DE RESULTADOS ===\n")
  cat("Por favor, ingrese la ruta completa donde desea guardar los resultados.\n")
  cat("Ejemplo: C:\\Users\\Usuario\\Documentos\\Resultados\n")
  cat("O puede usar barras normales: C:/Users/Usuario/Documentos/Resultados\n")
  cat("(Puede dejar en blanco para usar la ruta por defecto)\n\n")
  
  # Solicitar ruta al usuario
  ruta_ingresada <- readline(prompt = "Ruta de resultados: ")
  
  # Si está vacía, usar ruta por defecto
  if(trimws(ruta_ingresada) == "") {
    ruta_resultados <- "Finanzas/Aplicacion ARIMA/Resultados"
    cat("\nUsando ruta por defecto:", ruta_resultados, "\n")
  } else {
    # Normalizar la ruta: convertir backslashes a forward slashes
    # R puede trabajar con ambos, pero es mejor usar forward slashes
    ruta_normalizada <- gsub("\\\\", "/", trimws(ruta_ingresada))
    
    # Eliminar trailing slash si existe
    ruta_normalizada <- gsub("/$", "", ruta_normalizada)
    
    ruta_resultados <- ruta_normalizada
    cat("\nRuta configurada:", ruta_resultados, "\n")
  }
  
  # Verificar si el directorio existe, si no, crearlo
  if(!dir.exists(ruta_resultados)) {
    cat("El directorio no existe. Creando directorio...\n")
    resultado_creacion <- tryCatch({
      dir.create(ruta_resultados, recursive = TRUE)
      TRUE
    }, error = function(e) {
      cat("ERROR: No se pudo crear el directorio:", e$message, "\n")
      cat("Usando directorio temporal en su lugar...\n")
      FALSE
    })
    
    if(resultado_creacion) {
      cat("Directorio creado exitosamente:", ruta_resultados, "\n")
    } else {
      # Usar directorio temporal como respaldo
      ruta_resultados <- file.path(tempdir(), "Resultados_ARIMA")
      dir.create(ruta_resultados, recursive = TRUE)
      cat("Usando directorio temporal:", ruta_resultados, "\n")
    }
  } else {
    cat("Directorio existe:", ruta_resultados, "\n")
  }
  
  return(ruta_resultados)
}

# Solicitar ruta de resultados al usuario
ruta_resultados <- solicitar_ruta_resultados()
cat("\n")

# ===================================================================
# LISTADO DE DERIVADOS FINANCIEROS DISPONIBLES
# ===================================================================
# A continuación se presenta un listado completo de símbolos de DERIVADOS
# financieros disponibles en Yahoo Finance para análisis ARIMA.
# Los derivados son instrumentos cuyo valor depende de un activo subyacente.
# Simplemente cambie el valor de 'simbolo_activo' más abajo.
# ===================================================================

# ------------------------------------------------------------
# FUTUROS SOBRE METALES PRECIOSOS
# ------------------------------------------------------------
# "GC=F"   - Gold Futures (Oro - COMEX)
# "SI=F"   - Silver Futures (Plata - COMEX)
# "PL=F"   - Platinum Futures (Platino - NYMEX)
# "PA=F"   - Palladium Futures (Paladio - NYMEX)
# "HG=F"   - Copper Futures (Cobre - COMEX)

# ------------------------------------------------------------
# FUTUROS SOBRE ENERGÍA
# ------------------------------------------------------------
# "CL=F"   - Crude Oil WTI Futures (Petróleo WTI - NYMEX)
# "BZ=F"   - Brent Crude Oil Futures (Petróleo Brent - ICE)
# "NG=F"   - Natural Gas Futures (Gas Natural - NYMEX)
# "RB=F"   - RBOB Gasoline Futures (Gasolina - NYMEX)
# "HO=F"   - Heating Oil Futures (Aceite de Calefacción - NYMEX)

# ------------------------------------------------------------
# FUTUROS SOBRE AGRICULTURA
# ------------------------------------------------------------
# "ZC=F"   - Corn Futures (Maíz - CBOT)
# "ZS=F"   - Soybean Futures (Soja - CBOT)
# "ZW=F"   - Wheat Futures (Trigo - CBOT)
# "KC=F"   - Coffee 'C' Futures (Café - ICE)
# "CT=F"   - Cotton No. 2 Futures (Algodón - ICE)
# "SB=F"   - Sugar No. 11 Futures (Azúcar - ICE)
# "CC=F"   - Cocoa Futures (Cacao - ICE)
# "OJ=F"   - Orange Juice Futures (Jugo de Naranja - ICE)

# ------------------------------------------------------------
# FUTUROS SOBRE ÍNDICES BURSÁTILES
# ------------------------------------------------------------
# "ES=F"   - E-mini S&P 500 Futures (S&P 500 Mini - CME)
# "NQ=F"   - E-mini NASDAQ-100 Futures (NASDAQ 100 Mini - CME)
# "YM=F"   - E-mini Dow Futures (Dow Jones Mini - CME)
# "RTY=F"  - E-mini Russell 2000 Futures (Russell 2000 Mini - CME)
# "MEX=F"  - E-mini S&P MidCap 400 Futures (MidCap 400 - CME)

# ------------------------------------------------------------
# FUTUROS SOBRE BONOS Y TASAS DE INTERÉS
# ------------------------------------------------------------
# "ZN=F"   - 10-Year T-Note Futures (Bono 10 años - CBOT)
# "ZB=F"   - 30-Year T-Bond Futures (Bono 30 años - CBOT)
# "ZF=F"   - 5-Year T-Note Futures (Bono 5 años - CBOT)
# "ZT=F"   - 2-Year T-Note Futures (Bono 2 años - CBOT)
# "FF=F"   - 30-Day Fed Funds Futures (Tasa Fed Funds - CME)

# ------------------------------------------------------------
# FUTUROS SOBRE DIVISAS (FOREX FUTURES)
# ------------------------------------------------------------
# "6E=F"   - Euro FX Futures (EUR/USD - CME)
# "6B=F"   - British Pound Futures (GBP/USD - CME)
# "6J=F"   - Japanese Yen Futures (USD/JPY - CME)
# "6A=F"   - Australian Dollar Futures (AUD/USD - CME)
# "6C=F"   - Canadian Dollar Futures (USD/CAD - CME)
# "6S=F"   - Swiss Franc Futures (USD/CHF - CME)
# "6N=F"   - New Zealand Dollar Futures (NZD/USD - CME)
# "6M=F"   - Mexican Peso Futures (USD/MXN - CME)

# ------------------------------------------------------------
# FUTUROS SOBRE VOLATILIDAD
# ------------------------------------------------------------
# "VX=F"   - CBOE Volatility Index Futures (VIX Futures - CBOE)

# ------------------------------------------------------------
# FUTUROS SOBRE CRIPTOMONEDAS
# ------------------------------------------------------------
# "BTC=F"  - Bitcoin Futures (CME)
# "ETH=F"  - Ethereum Futures (CME)

# ------------------------------------------------------------
# ÍNDICES COMO SUBYACENTES DE DERIVADOS
# ------------------------------------------------------------
# "^GSPC"  - S&P 500 (subyacente de futuros ES=F)
# "^IXIC"  - NASDAQ Composite (subyacente de futuros NQ=F)
# "^DJI"   - Dow Jones (subyacente de futuros YM=F)
# "^VIX"   - CBOE Volatility Index (subyacente de futuros VX=F)

# ------------------------------------------------------------
# COMMODITIES SPOT (Precios al contado - subyacentes)
# ------------------------------------------------------------
# "GC=F"   - Gold Spot (Oro spot)
# "CL=F"   - Crude Oil Spot (Petróleo spot)
# "NG=F"   - Natural Gas Spot (Gas natural spot)

# ===================================================================
# CONFIGURACIÓN DEL ACTIVO FINANCIERO A ANALIZAR
# ===================================================================
# Cambie el valor de 'simbolo_activo' según el activo que desee analizar
# Ejemplo: Para analizar Apple, cambie a: simbolo_activo <- "AAPL"
# ===================================================================

simbolo_activo <- "^GSPC"  # S&P 500 (por defecto)

# Fechas para la descarga de datos
# Se descargarán datos históricos desde la fecha_inicio hasta fecha_fin
fecha_inicio <- "2024-01-01"
fecha_fin <- format(Sys.Date(), "%Y-%m-%d") # Fecha actual

# Configuración de parámetros para el análisis
nivel_significancia <- 0.05  # Nivel de significancia para pruebas estadísticas (5%)
periodo_pronostico <- 30     # Número de períodos adelante para pronóstico

cat("=== CONFIGURACIÓN COMPLETADA ===\n")
cat("Activo seleccionado:", simbolo_activo, "\n")
cat("Período:", fecha_inicio, "a", fecha_fin, "\n")
cat("Nivel de significancia:", nivel_significancia, "\n\n")

# Mostrar resumen de derivados disponibles
cat("=== DERIVADOS FINANCIEROS DISPONIBLES (Resumen) ===\n")
cat("Para cambiar el derivado, modifique 'simbolo_activo' en la línea 176\n\n")
cat("FUTUROS METALES: GC=F (Oro), SI=F (Plata), PL=F (Platino), PA=F (Paladio), HG=F (Cobre)\n")
cat("FUTUROS ENERGÍA: CL=F (Petróleo WTI), BZ=F (Brent), NG=F (Gas Natural), RB=F (Gasolina)\n")
cat("FUTUROS AGRICULTURA: ZC=F (Maíz), ZS=F (Soja), ZW=F (Trigo), KC=F (Café), CT=F (Algodón)\n")
cat("FUTUROS ÍNDICES: ES=F (S&P 500 Mini), NQ=F (NASDAQ Mini), YM=F (Dow Mini), RTY=F (Russell)\n")
cat("FUTUROS BONOS: ZN=F (Bono 10 años), ZB=F (Bono 30 años), ZF=F (Bono 5 años), ZT=F (Bono 2 años)\n")
cat("FUTUROS DIVISAS: 6E=F (EUR/USD), 6B=F (GBP/USD), 6J=F (USD/JPY), 6A=F (AUD/USD), 6C=F (USD/CAD)\n")
cat("FUTUROS VOLATILIDAD: VX=F (VIX Futures)\n")
cat("FUTUROS CRIPTO: BTC=F (Bitcoin), ETH=F (Ethereum)\n")
cat("\nPara ver el listado completo con descripciones, consulte las líneas 63-167 del código.\n\n")

# ===================================================================
# ETAPA 1: IDENTIFICACIÓN DEL MODELO
# ===================================================================
# En esta etapa se busca determinar los órdenes (p,d,q) del modelo ARIMA
# mediante el análisis de la serie de tiempo y sus características
# estadísticas.
# ===================================================================

# ------------------------------------------------------------
# 1.1 DESCARGA DE DATOS FINANCIEROS
# ------------------------------------------------------------

cat("\n=== ETAPA 1: IDENTIFICACIÓN ===\n")
cat("--- Paso 1.1: Descarga de datos financieros ---\n")

# Descargar datos del activo financiero
# getSymbols() descarga datos de Yahoo Finance u otras fuentes
tryCatch({
  getSymbols(simbolo_activo, 
             src = "yahoo", 
             from = fecha_inicio, 
             to = fecha_fin,
             auto.assign = TRUE)
  
  # Extraer el objeto de datos (el nombre depende del símbolo)
  nombre_objeto <- gsub("\\^", "", simbolo_activo)
  datos_activo <- get(nombre_objeto)
  
  # Op(datos_activo)  # Open
  # Hi(datos_activo)  # High
  # Lo(datos_activo)  # Low
  # Cl(datos_activo)  # Close
  # Ad(datos_activo)  # Adjusted
  # Vo(datos_activo)  # Volume
  # # Extraer la serie de precios de cierre (Close)
  # Los precios de cierre son los más utilizados en análisis financiero
  precios_cierre <- Cl(datos_activo)
  
  # Convertir a serie de tiempo (ts) para análisis
  # Se asume frecuencia diaria (252 días hábiles por año)
  serie_precios <- ts(precios_cierre, frequency = 252, start = c(2024, 1))
  
  # Eliminar valores faltantes (NA) si existen
  serie_precios <- na.omit(serie_precios)
  
  cat("Datos descargados exitosamente\n")
  cat("Número de observaciones:", length(serie_precios), "\n")
  cat("Rango de fechas:", start(serie_precios), "a", end(serie_precios), "\n")
  cat("Primeros valores:\n")
  print(head(serie_precios))
  cat("Últimos valores:\n")
  print(tail(serie_precios))
  
}, error = function(e) {
  cat("ERROR al descargar datos:", e$message, "\n")
  cat("Usando datos simulados para demostración...\n")
  
  # Generar serie simulada si falla la descarga
  set.seed(123)
  n_obs <- 1000
  # Simular serie con tendencia y componente estocástica
  serie_precios <- ts(cumsum(rnorm(n_obs, mean = 0.1, sd = 10)) + 3000, 
                      frequency = 252, 
                      start = c(2020, 1))
})

# Guardar serie original
serie_original <- serie_precios

# ------------------------------------------------------------
# 1.2 ANÁLISIS EXPLORATORIO INICIAL
# ------------------------------------------------------------

cat("\n--- Paso 1.2: Análisis exploratorio inicial ---\n")

# Estadísticas descriptivas básicas
cat("\n=== ESTADÍSTICAS DESCRIPTIVAS ===\n")
cat("Media:", mean(serie_precios), "\n")
cat("Desviación estándar:", sd(serie_precios), "\n")
cat("Mínimo:", min(serie_precios), "\n")
cat("Máximo:", max(serie_precios), "\n")
cat("Coeficiente de variación:", sd(serie_precios)/mean(serie_precios), "\n")

# Gráfico 1: Serie de tiempo original
# Convertir serie de tiempo a data frame para ggplot2
df_serie_original <- data.frame(
  Tiempo = time(serie_precios),
  Precio = as.numeric(serie_precios)
)

p1 <- ggplot(df_serie_original, aes(x = Tiempo, y = Precio)) +
  geom_line(color = "darkblue", linewidth = 1.5) +
  labs(title = "Serie de Tiempo: Precios de Cierre",
       x = "Tiempo",
       y = "Precio") +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
        panel.grid.minor = element_blank())

# Mostrar gráfico
print(p1)

# Guardar gráfico
ggsave(file.path(ruta_resultados, "01_Serie_Tiempo_Original.png"), 
       plot = p1, 
       width = 12, height = 6, dpi = 150)
cat("Gráfico guardado: 01_Serie_Tiempo_Original.png\n")

# Gráfico 2: Histograma de la serie
p2 <- ggplot(df_serie_original, aes(x = Precio)) +
  geom_histogram(bins = 50, fill = "lightblue", color = "darkblue", alpha = 0.7) +
  geom_vline(xintercept = mean(serie_precios), color = "red", linetype = "dashed", linewidth = 1.5) +
  labs(title = "Distribución de Precios",
       x = "Precio",
       y = "Frecuencia",
       subtitle = paste("Media =", round(mean(serie_precios), 2))) +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
        plot.subtitle = element_text(hjust = 0.5, size = 10),
        panel.grid.minor = element_blank())

# Mostrar gráfico
print(p2)

# Guardar gráfico
ggsave(file.path(ruta_resultados, "02_Histograma_Precios.png"), 
       plot = p2, 
       width = 10, height = 6, dpi = 150)
cat("Gráfico guardado: 02_Histograma_Precios.png\n")

# ------------------------------------------------------------
# 1.3 PRUEBA DE ESTACIONARIEDAD: PRUEBA AUGMENTED DICKEY-FULLER (ADF)
# ------------------------------------------------------------

cat("\n--- Paso 1.3: Pruebas de estacionariedad ---\n")

# PRUEBA AUGMENTED DICKEY-FULLER (ADF)
# H0: La serie tiene raíz unitaria (no estacionaria)
# H1: La serie es estacionaria
# 
# Si p-valor < nivel_significancia: Rechazamos H0, la serie es estacionaria
# Si p-valor >= nivel_significancia: No rechazamos H0, la serie no es estacionaria

cat("\n=== PRUEBA AUGMENTED DICKEY-FULLER (ADF) ===\n")
cat("Hipótesis nula (H0): La serie tiene raíz unitaria (no estacionaria)\n")
cat("Hipótesis alternativa (H1): La serie es estacionaria\n")
cat("Nivel de significancia:", nivel_significancia, "\n\n")

# Realizar prueba ADF en la serie original
prueba_adf_original <- adf.test(serie_precios)

cat("Resultados de la prueba ADF en la serie original:\n")
cat("Estadístico ADF:", prueba_adf_original$statistic, "\n")
cat("P-valor:", prueba_adf_original$p.value, "\n")


# Interpretación de la prueba ADF
if(prueba_adf_original$p.value < nivel_significancia) {
  cat("\nINTERPRETACIÓN: P-valor <", nivel_significancia, 
      "→ Rechazamos H0 → La serie ES ESTACIONARIA\n")
  cat("Conclusión: No se requiere diferenciación (d = 0)\n")
  orden_diferencia <- 0
} else {
  cat("\nINTERPRETACIÓN: P-valor >=", nivel_significancia, 
      "→ No rechazamos H0 → La serie NO ES ESTACIONARIA\n")
  cat("Conclusión: Se requiere diferenciación (d > 0)\n")
  orden_diferencia <- NA  # Se determinará más adelante
}

# ------------------------------------------------------------
# 1.4 PRUEBA DE ESTACIONARIEDAD: PRUEBA KPSS
# ------------------------------------------------------------

# PRUEBA KPSS (Kwiatkowski-Phillips-Schmidt-Shin)
# H0: La serie es estacionaria (tendencia estacionaria)
# H1: La serie no es estacionaria
#
# Esta prueba complementa la ADF ya que tienen hipótesis nulas opuestas
# Si ambas pruebas coinciden, tenemos mayor confianza en el resultado

cat("\n=== PRUEBA KPSS ===\n")
cat("Hipótesis nula (H0): La serie es estacionaria\n")
cat("Hipótesis alternativa (H1): La serie no es estacionaria\n\n")

# Realizar prueba KPSS
prueba_kpss_original <- ur.kpss(serie_precios, type = "tau", lags = "short")

cat("Resultados de la prueba KPSS:\n")
cat("Estadístico KPSS:", prueba_kpss_original@teststat, "\n")
cat("Valor crítico al 5%:", prueba_kpss_original@cval[2], "\n")

# Interpretación KPSS
if(prueba_kpss_original@teststat < prueba_kpss_original@cval[2]) {
  cat("\nINTERPRETACIÓN: Estadístico < Valor crítico → No rechazamos H0\n")
  cat("Conclusión: La serie ES ESTACIONARIA (según KPSS)\n")
} else {
  cat("\nINTERPRETACIÓN: Estadístico >= Valor crítico → Rechazamos H0\n")
  cat("Conclusión: La serie NO ES ESTACIONARIA (según KPSS)\n")
}

# ------------------------------------------------------------
# 1.5 DIFERENCIACIÓN DE LA SERIE (si es necesario)
# ------------------------------------------------------------

cat("\n--- Paso 1.5: Diferenciación de la serie ---\n")

# Si la serie no es estacionaria, se aplica diferenciación
# La diferenciación ayuda a eliminar tendencias y hacer la serie estacionaria
# d = número de veces que se diferencia la serie

# Determinar el orden de diferenciación necesario
if(is.na(orden_diferencia) || prueba_kpss_original@teststat >= prueba_kpss_original@cval[2]) {
  cat("La serie no es estacionaria. Aplicando diferenciación...\n")
  
  # Aplicar primera diferenciación
  serie_diff1 <- diff(serie_precios)
  serie_diff1 <- na.omit(serie_diff1)
  
  # Probar estacionariedad de la serie diferenciada
  prueba_adf_diff1 <- adf.test(serie_diff1)
  prueba_kpss_diff1 <- ur.kpss(serie_diff1, type = "tau", lags = "short")
  
  cat("\nPrueba ADF en primera diferencia:\n")
  cat("P-valor:", prueba_adf_diff1$p.value, "\n")
  
  if(prueba_adf_diff1$p.value < nivel_significancia && 
     prueba_kpss_diff1@teststat < prueba_kpss_diff1@cval[2]) {
    cat("La primera diferencia es estacionaria → d = 1\n")
    orden_diferencia <- 1
    serie_estacionaria <- serie_diff1
  } else {
    # Intentar segunda diferenciación
    cat("La primera diferencia no es estacionaria. Aplicando segunda diferenciación...\n")
    serie_diff2 <- diff(serie_diff1)
    serie_diff2 <- na.omit(serie_diff2)
    
    prueba_adf_diff2 <- adf.test(serie_diff2)
    prueba_kpss_diff2 <- ur.kpss(serie_diff2, type = "tau", lags = "short")
    
    cat("\nPrueba ADF en segunda diferencia:\n")
    cat("P-valor:", prueba_adf_diff2$p.value, "\n")
    
    if(prueba_adf_diff2$p.value < nivel_significancia && 
       prueba_kpss_diff2@teststat < prueba_kpss_diff2@cval[2]) {
      cat("La segunda diferencia es estacionaria → d = 2\n")
      orden_diferencia <- 2
      serie_estacionaria <- serie_diff2
    } else {
      cat("ADVERTENCIA: La serie puede requerir más diferenciaciones o transformaciones\n")
      orden_diferencia <- 1  # Usar d=1 por defecto
      serie_estacionaria <- serie_diff1
    }
  }
} else {
  cat("La serie original es estacionaria → d = 0\n")
  orden_diferencia <- 0
  serie_estacionaria <- serie_precios
}

cat("\n=== ORDEN DE DIFERENCIACIÓN DETERMINADO: d =", orden_diferencia, "===\n")

# Gráfico de la serie estacionaria
# Convertir serie estacionaria a data frame
df_serie_estacionaria <- data.frame(
  Tiempo = time(serie_estacionaria),
  Valor = as.numeric(serie_estacionaria)
)

p3 <- ggplot(df_serie_estacionaria, aes(x = Tiempo, y = Valor)) +
  geom_line(color = "darkgreen", linewidth = 0.5) +
  geom_hline(yintercept = 0, color = "red", linetype = "dashed", linewidth = 1) +
  labs(title = paste("Serie Estacionaria (d =", orden_diferencia, ")"),
       x = "Tiempo",
       y = ifelse(orden_diferencia > 0, "Primera Diferencia", "Precio")) +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
        panel.grid.minor = element_blank())

# Mostrar gráfico
print(p3)

# Guardar gráfico
ggsave(file.path(ruta_resultados, "03_Serie_Estacionaria.png"), 
       plot = p3, 
       width = 12, height = 6, dpi = 150)
cat("Gráfico guardado: 03_Serie_Estacionaria.png\n")

# ------------------------------------------------------------
# 1.6 IDENTIFICACIÓN DE ORDENES AR Y MA: FUNCIONES ACF Y PACF
# ------------------------------------------------------------

cat("\n--- Paso 1.6: Identificación de órdenes AR(p) y MA(q) ---\n")
cat("Análisis de funciones de autocorrelación (ACF) y autocorrelación parcial (PACF)\n\n")

# FUNCIÓN DE AUTOCORRELACIÓN (ACF)
# Mide la correlación entre la serie y sus valores rezagados
# Patrones en ACF ayudan a identificar el orden q del componente MA

# FUNCIÓN DE AUTOCORRELACIÓN PARCIAL (PACF)
# Mide la correlación entre la serie y sus valores rezagados,
# controlando por los rezagos intermedios
# Patrones en PACF ayudan a identificar el orden p del componente AR

# Calcular ACF y PACF
acf_serie <- acf(serie_estacionaria, lag.max = 40, plot = FALSE)
pacf_serie <- pacf(serie_estacionaria, lag.max = 40, plot = FALSE)

# Gráficos de ACF y PACF usando ggAcf y ggPacf de forecast
p_acf <- ggAcf(serie_estacionaria, lag.max = 40) +
  labs(title = "Función de Autocorrelación (ACF) - Serie Estacionaria",
       y = "ACF") +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5, size = 12, face = "bold"),
        panel.grid.minor = element_blank())

p_pacf <- ggPacf(serie_estacionaria, lag.max = 40) +
  labs(title = "Función de Autocorrelación Parcial (PACF) - Serie Estacionaria",
       y = "PACF") +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5, size = 12, face = "bold"),
        panel.grid.minor = element_blank())

# Combinar gráficos
p4 <- grid.arrange(p_acf, p_pacf, nrow = 2)

# Mostrar gráfico
print(p4)

# Guardar gráfico
ggsave(file.path(ruta_resultados, "04_ACF_PACF.png"), 
       plot = p4, 
       width = 14, height = 7, dpi = 150)
cat("Gráfico guardado: 04_ACF_PACF.png\n")

# Interpretación de ACF y PACF para identificar órdenes
cat("\n=== INTERPRETACIÓN DE ACF Y PACF ===\n")
cat("Guía para identificación:\n")
cat("- Si PACF se corta después del lag k → AR(k) sugerido\n")
cat("- Si ACF se corta después del lag k → MA(k) sugerido\n")
cat("- Si ambos decaen gradualmente → ARMA(p,q) sugerido\n\n")

# Identificar puntos de corte significativos
# Un coeficiente es significativo si |coef| > 2/sqrt(n)
umbral_significancia_acf <- 2/sqrt(length(serie_estacionaria))

# Analizar PACF para identificar orden AR
coef_pacf <- pacf_serie$acf
lags_significativos_pacf <- which(abs(coef_pacf) > umbral_significancia_acf)

if(length(lags_significativos_pacf) > 0) {
  orden_ar_sugerido <- max(lags_significativos_pacf)
  cat("PACF: Coeficientes significativos hasta lag", orden_ar_sugerido, "\n")
  cat("Sugerencia: Considerar AR(", orden_ar_sugerido, ")\n")
} else {
  orden_ar_sugerido <- 0
  cat("PACF: No se identifican cortes claros\n")
}

# Analizar ACF para identificar orden MA
coef_acf <- acf_serie$acf[-1]  # Excluir lag 0
lags_significativos_acf <- which(abs(coef_acf) > umbral_significancia_acf)

if(length(lags_significativos_acf) > 0) {
  orden_ma_sugerido <- max(lags_significativos_acf)
  cat("ACF: Coeficientes significativos hasta lag", orden_ma_sugerido, "\n")
  cat("Sugerencia: Considerar MA(", orden_ma_sugerido, ")\n")
} else {
  orden_ma_sugerido <- 0
  cat("ACF: No se identifican cortes claros\n")
}

# ------------------------------------------------------------
# 1.7 COMPARACIÓN DE MÚLTIPLES MODELOS ARIMA: CRITERIOS DE INFORMACIÓN
# ------------------------------------------------------------

cat("\n--- Paso 1.7: Comparación de múltiples modelos ARIMA ---\n")
cat("Evaluando diferentes combinaciones de (p,d,q) usando criterios de información\n\n")

# Definir rango de órdenes a probar
# Basado en el análisis previo y buenas prácticas
max_p <- 3  # Máximo orden AR
max_q <- 3  # Máximo orden MA
max_d <- 1  # Máximo orden de diferenciación (ya determinado)

# Crear todas las combinaciones posibles de (p,d,q)
combinaciones <- expand.grid(p = 0:max_p, d = 0:max_d, q = 0:max_q)

# Eliminar combinaciones triviales (0,0,0)
combinaciones <- combinaciones[!(combinaciones$p == 0 & 
                                 combinaciones$d == 0 & 
                                 combinaciones$q == 0), ]

cat("Total de modelos a evaluar:", nrow(combinaciones), "\n")
cat("Esto puede tomar unos momentos...\n\n")

# Función para estimar modelo y extraer criterios
estimar_modelo <- function(p, d, q, serie) {
  tryCatch({
    modelo <- Arima(serie, 
                    order = c(p, d, q),
                    method = "CSS-ML",
                    include.mean = TRUE,
                    include.drift = FALSE)
    
    # Extraer criterios de información
    aic_val <- AIC(modelo)
    bic_val <- BIC(modelo)
    # AICc puede no estar disponible en todas las versiones
    aicc_val <- tryCatch({
      if(exists("AICc", mode = "function")) {
        AICc(modelo)
      } else {
        NA
      }
    }, error = function(e) NA)
    loglik_val <- modelo$loglik
    
    return(list(
      p = p, d = d, q = q,
      AIC = aic_val,
      BIC = bic_val,
      AICc = aicc_val,
      LogLik = loglik_val,
      modelo = modelo,
      exito = TRUE
    ))
  }, error = function(e) {
    return(list(
      p = p, d = d, q = q,
      AIC = NA, BIC = NA, AICc = NA, LogLik = NA,
      modelo = NULL,
      exito = FALSE
    ))
  })
}

# Evaluar todos los modelos
resultados_modelos <- list()
for(i in 1:nrow(combinaciones)) {
  p <- combinaciones$p[i]
  d <- combinaciones$d[i]
  q <- combinaciones$q[i]
  
  cat("Evaluando ARIMA(", p, ",", d, ",", q, ")... ", sep = "")
  resultado <- estimar_modelo(p, d, q, serie_precios)
  resultados_modelos[[i]] <- resultado
  
  if(resultado$exito) {
    cat("✓ AIC =", round(resultado$AIC, 2), "\n")
  } else {
    cat("✗ Error en estimación\n")
  }
}

# Crear tabla comparativa de modelos
tabla_comparacion <- data.frame(
  Modelo = paste0("ARIMA(", 
                   sapply(resultados_modelos, function(x) x$p), ",",
                   sapply(resultados_modelos, function(x) x$d), ",",
                   sapply(resultados_modelos, function(x) x$q), ")"),
  p = sapply(resultados_modelos, function(x) x$p),
  d = sapply(resultados_modelos, function(x) x$d),
  q = sapply(resultados_modelos, function(x) x$q),
  AIC = sapply(resultados_modelos, function(x) x$AIC),
  BIC = sapply(resultados_modelos, function(x) x$BIC),
  #AICc = sapply(resultados_modelos, function(x) x$AICc),
  LogLik = sapply(resultados_modelos, function(x) x$LogLik),
  Exito = sapply(resultados_modelos, function(x) x$exito)
)

# Filtrar solo modelos exitosos
tabla_comparacion <- tabla_comparacion[tabla_comparacion$Exito == TRUE, ]
tabla_comparacion$Exito <- NULL

# Ordenar por AIC (menor es mejor)
tabla_comparacion <- tabla_comparacion[order(tabla_comparacion$AIC), ]

cat("\n=== TABLA COMPARATIVA DE MODELOS ===\n")
print(tabla_comparacion, row.names = FALSE)

# Guardar tabla comparativa
write.csv(tabla_comparacion, 
          file.path(ruta_resultados, "Comparacion_Modelos_ARIMA.csv"), 
          row.names = FALSE)
cat("\nTabla guardada: Comparacion_Modelos_ARIMA.csv\n")

# Crear gráfico comparativo de criterios de información
# Preparar datos para gráfico (ordenar por AIC)
tabla_comparacion_ordenada <- tabla_comparacion %>%
  arrange(AIC) %>%
  mutate(Modelo = factor(Modelo, levels = Modelo))

# Preparar datos para gráfico de barras agrupadas
df_grafico <- tabla_comparacion_ordenada %>%
  select(Modelo, AIC, BIC) %>%
  pivot_longer(cols = c(AIC, BIC), 
               names_to = "Criterio", 
               values_to = "Valor")

# Gráfico 1: Barras agrupadas de todos los criterios
p_comparacion1 <- ggplot(df_grafico, aes(x = Modelo, y = Valor, fill = Criterio)) +
  geom_bar(stat = "identity", position = "dodge", alpha = 0.8) +
  labs(title = "Comparación de Criterios de Información para Modelos ARIMA",
       subtitle = "Menores valores indican mejor modelo",
       x = "Modelo ARIMA",
       y = "Valor del Criterio",
       fill = "Criterio") +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
        plot.subtitle = element_text(hjust = 0.5, size = 10),
        axis.text.x = element_text(angle = 45, hjust = 1, size = 8),
        legend.position = "bottom",
        panel.grid.minor = element_blank()) +
  scale_fill_brewer(palette = "Set2")

# Gráfico 2: Líneas para cada criterio (más fácil de comparar)
p_comparacion2 <- ggplot(df_grafico, aes(x = Modelo, y = Valor, color = Criterio, group = Criterio)) +
  geom_line(linewidth = 1.2, alpha = 0.7) +
  geom_point(size = 2.5, alpha = 0.8) +
  labs(title = "Evolución de Criterios de Información por Modelo ARIMA",
       subtitle = "Ordenados por AIC (menor a mayor)",
       x = "Modelo ARIMA (ordenado por AIC)",
       y = "Valor del Criterio",
       color = "Criterio") +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
        plot.subtitle = element_text(hjust = 0.5, size = 10),
        axis.text.x = element_text(angle = 45, hjust = 1, size = 8),
        legend.position = "bottom",
        panel.grid.minor = element_blank()) +
  scale_color_brewer(palette = "Set2")

# Combinar ambos gráficos
p_comparacion <- grid.arrange(p_comparacion1, p_comparacion2, nrow = 2, heights = c(1, 1))

# Mostrar gráfico
print(p_comparacion)

# Guardar gráfico
ggsave(file.path(ruta_resultados, "07_Comparacion_Modelos_ARIMA.png"), 
       plot = p_comparacion, 
       width = 16, height = 12, dpi = 150)
cat("Gráfico guardado: 07_Comparacion_Modelos_ARIMA.png\n")

# Seleccionar el mejor modelo según AIC (menor valor)
mejor_modelo_idx <- which.min(tabla_comparacion$AIC)
mejor_modelo_info <- tabla_comparacion[mejor_modelo_idx, ]

cat("\n=== MEJOR MODELO SELECCIONADO ===\n")
cat("Modelo:", mejor_modelo_info$Modelo, "\n")
cat("AIC:", round(mejor_modelo_info$AIC, 2), " (menor valor)\n")
cat("BIC:", round(mejor_modelo_info$BIC, 2), "\n")
cat("Log-Likelihood:", round(mejor_modelo_info$LogLik, 2), "\n\n")

# Extraer órdenes del mejor modelo
orden_p <- mejor_modelo_info$p
orden_diferencia <- mejor_modelo_info$d
orden_q <- mejor_modelo_info$q

# Obtener el objeto del mejor modelo
mejor_modelo_obj <- resultados_modelos[[which(sapply(resultados_modelos, function(x) 
  x$p == orden_p & x$d == orden_diferencia & x$q == orden_q))]]$modelo

cat("=== RESUMEN DE IDENTIFICACIÓN ===\n")
cat("Orden AR (p):", orden_p, "\n")
cat("Orden de diferenciación (d):", orden_diferencia, "\n")
cat("Orden MA (q):", orden_q, "\n")
cat("Modelo ARIMA(", orden_p, ",", orden_diferencia, ",", orden_q, ")\n\n")

# ===================================================================
# ETAPA 2: ESTIMACIÓN DEL MODELO
# ===================================================================
# Una vez identificados los órdenes (p,d,q), se procede a estimar
# los parámetros del modelo ARIMA mediante máxima verosimilitud.
# ===================================================================

cat("\n=== ETAPA 2: ESTIMACIÓN ===\n")

# ------------------------------------------------------------
# 2.1 ESTIMACIÓN DEL MEJOR MODELO ARIMA
# ------------------------------------------------------------

cat("--- Paso 2.1: Estimación de parámetros del mejor modelo ARIMA ---\n")
cat("Usando el modelo seleccionado:", mejor_modelo_info$Modelo, "\n\n")

# Usar el modelo ya estimado (mejor_modelo_obj) o re-estimarlo para mayor claridad
modelo_arima <- mejor_modelo_obj

cat("\n=== RESULTADOS DE LA ESTIMACIÓN DEL MEJOR MODELO ===\n")
print(summary(modelo_arima))

# Extraer coeficientes estimados
coeficientes <- coef(modelo_arima)
errores_estandar <- sqrt(diag(modelo_arima$var.coef))

# Crear tabla de coeficientes
tabla_coeficientes <- data.frame(
  Coeficiente = names(coeficientes),
  Estimacion = as.numeric(coeficientes),
  Error_Estándar = as.numeric(errores_estandar),
  t_valor = as.numeric(coeficientes / errores_estandar),
  p_valor = 2 * (1 - pnorm(abs(as.numeric(coeficientes / errores_estandar))))
)

cat("\n=== TABLA DE COEFICIENTES ===\n")
print(tabla_coeficientes)

# Interpretación de significancia
cat("\n=== INTERPRETACIÓN DE SIGNIFICANCIA ===\n")
cat("Hipótesis para cada coeficiente:\n")
cat("H0: Coeficiente = 0 (no significativo)\n")
cat("H1: Coeficiente ≠ 0 (significativo)\n")
cat("Nivel de significancia:", nivel_significancia, "\n\n")

coeficientes_significativos <- tabla_coeficientes$p_valor < nivel_significancia
for(i in 1:nrow(tabla_coeficientes)) {
  if(coeficientes_significativos[i]) {
    cat(tabla_coeficientes$Coeficiente[i], ": Significativo (p =", 
        round(tabla_coeficientes$p_valor[i], 4), ")\n")
  } else {
    cat(tabla_coeficientes$Coeficiente[i], ": NO significativo (p =", 
        round(tabla_coeficientes$p_valor[i], 4), ")\n")
  }
}

# Guardar tabla de coeficientes
write.csv(tabla_coeficientes, 
          file.path(ruta_resultados, "Tabla_Coeficientes.csv"), 
          row.names = FALSE)
cat("\nTabla guardada: Tabla_Coeficientes.csv\n")

# ------------------------------------------------------------
# 2.2 CRITERIOS DE INFORMACIÓN Y BONDAD DE AJUSTE
# ------------------------------------------------------------

cat("\n--- Paso 2.2: Criterios de información y bondad de ajuste ---\n")

# Extraer criterios de información del modelo
aic_modelo <- AIC(modelo_arima)
bic_modelo <- BIC(modelo_arima)
#aicc_modelo <- AICc(modelo_arima)
log_likelihood <- modelo_arima$loglik

cat("\n=== CRITERIOS DE INFORMACIÓN ===\n")
cat("AIC (Akaike Information Criterion):", round(aic_modelo, 2), "\n")
#cat("AICc (AIC corregido):", round(aicc_modelo, 2), "\n")
cat("BIC (Bayesian Information Criterion):", round(bic_modelo, 2), "\n")
cat("Log-verosimilitud:", round(log_likelihood, 2), "\n\n")

cat("INTERPRETACIÓN:\n")
cat("- Menores valores de AIC/BIC indican mejor ajuste\n")
cat("- AIC penaliza menos la complejidad que BIC\n")
cat("- BIC es más conservador y prefiere modelos más simples\n")

# Calcular medidas de bondad de ajuste
residuos_modelo <- residuals(modelo_arima)
mse <- mean(residuos_modelo^2)  # Mean Squared Error
rmse <- sqrt(mse)                # Root Mean Squared Error
mae <- mean(abs(residuos_modelo)) # Mean Absolute Error
mape <- mean(abs(residuos_modelo / serie_precios)) * 100 # Mean Absolute Percentage Error

cat("\n=== MEDIDAS DE ERROR ===\n")
cat("MSE (Mean Squared Error):", round(mse, 4), "\n")
cat("RMSE (Root Mean Squared Error):", round(rmse, 4), "\n")
cat("MAE (Mean Absolute Error):", round(mae, 4), "\n")
cat("MAPE (Mean Absolute Percentage Error):", round(mape, 2), "%\n")

# Guardar medidas de bondad de ajuste
medidas_ajuste <- data.frame(
  Metrica = c("AIC", "BIC", "Log-Likelihood", "MSE", "RMSE", "MAE", "MAPE"),
  Valor = c(aic_modelo, bic_modelo, log_likelihood, mse, rmse, mae, mape)
)
write.csv(medidas_ajuste, 
          file.path(ruta_resultados, "Medidas_Bondad_Ajuste.csv"), 
          row.names = FALSE)
cat("\nMedidas guardadas: Medidas_Bondad_Ajuste.csv\n")

# ===================================================================
# ETAPA 3: DIAGNÓSTICO DEL MODELO
# ===================================================================
# En esta etapa se verifica que el modelo estimado cumple con
# los supuestos estadísticos requeridos, principalmente:
# 1. Los residuos deben ser ruido blanco (no correlacionados)
# 2. Los residuos deben tener distribución normal
# 3. Los residuos deben tener varianza constante (homocedasticidad)
# ===================================================================

cat("\n=== ETAPA 3: DIAGNÓSTICO ===\n")

# ------------------------------------------------------------
# 3.1 ANÁLISIS DE RESIDUOS: PRUEBA DE CORRELACIÓN
# ------------------------------------------------------------

cat("\n--- Paso 3.1: Análisis de correlación de residuos ---\n")

# PRUEBA DE LJUNG-BOX
# H0: Los residuos no están correlacionados (ruido blanco)
# H1: Los residuos están correlacionados
#
# Si p-valor < nivel_significancia: Rechazamos H0, hay correlación (modelo inadecuado)
# Si p-valor >= nivel_significancia: No rechazamos H0, no hay correlación (modelo adecuado)

cat("\n=== PRUEBA DE LJUNG-BOX ===\n")
cat("Hipótesis nula (H0): Los residuos no están correlacionados (ruido blanco)\n")
cat("Hipótesis alternativa (H1): Los residuos están correlacionados\n")
cat("Nivel de significancia:", nivel_significancia, "\n\n")

# Realizar prueba de Ljung-Box en los residuos
# Se prueba con diferentes números de rezagos
lags_prueba <- c(10, 15, 20, 25, 30)
resultados_ljung <- data.frame(
  Lags = lags_prueba,
  Estadistico = numeric(length(lags_prueba)),
  p_valor = numeric(length(lags_prueba)),
  Significativo = logical(length(lags_prueba))
)

for(i in 1:length(lags_prueba)) {
  prueba_ljung <- Box.test(residuos_modelo, lag = lags_prueba[i], type = "Ljung-Box")
  resultados_ljung$Estadistico[i] <- prueba_ljung$statistic
  resultados_ljung$p_valor[i] <- prueba_ljung$p.value
  resultados_ljung$Significativo[i] <- prueba_ljung$p.value < nivel_significancia
}

cat("Resultados de la prueba de Ljung-Box:\n")
print(resultados_ljung)

# Interpretación
cat("\n=== INTERPRETACIÓN ===\n")
if(all(resultados_ljung$p_valor >= nivel_significancia)) {
  cat("Todos los p-valores >=", nivel_significancia, 
      "→ No rechazamos H0 en ningún lag\n")
  cat("CONCLUSIÓN: Los residuos NO están correlacionados → Modelo ADECUADO\n")
} else {
  cat("Algunos p-valores <", nivel_significancia, 
      "→ Rechazamos H0 en algunos lags\n")
  cat("CONCLUSIÓN: Los residuos SÍ están correlacionados → Modelo puede ser INADECUADO\n")
  cat("RECOMENDACIÓN: Considerar ajustar el modelo o aumentar órdenes (p,q)\n")
}

# Guardar resultados
write.csv(resultados_ljung, 
          file.path(ruta_resultados, "Prueba_Ljung_Box.csv"), 
          row.names = FALSE)
cat("\nResultados guardados: Prueba_Ljung_Box.csv\n")

# ------------------------------------------------------------
# 3.2 ANÁLISIS DE RESIDUOS: PRUEBA DE NORMALIDAD
# ------------------------------------------------------------

cat("\n--- Paso 3.2: Análisis de normalidad de residuos ---\n")

# PRUEBA DE SHAPIRO-WILK
# H0: Los residuos tienen distribución normal
# H1: Los residuos no tienen distribución normal
#
# Si p-valor < nivel_significancia: Rechazamos H0, no son normales
# Si p-valor >= nivel_significancia: No rechazamos H0, son normales

cat("\n=== PRUEBA DE SHAPIRO-WILK ===\n")
cat("Hipótesis nula (H0): Los residuos tienen distribución normal\n")
cat("Hipótesis alternativa (H1): Los residuos no tienen distribución normal\n")
cat("Nivel de significancia:", nivel_significancia, "\n\n")

# Realizar prueba de Shapiro-Wilk
# Nota: La prueba tiene límite de 5000 observaciones
n_muestra_norm <- min(5000, length(residuos_modelo))
muestra_residuos <- sample(residuos_modelo, n_muestra_norm)

prueba_shapiro <- shapiro.test(muestra_residuos)

cat("Resultados de la prueba de Shapiro-Wilk:\n")
cat("Estadístico W:", prueba_shapiro$statistic, "\n")
cat("P-valor:", prueba_shapiro$p.value, "\n")

# Interpretación
if(prueba_shapiro$p.value >= nivel_significancia) {
  cat("\nINTERPRETACIÓN: P-valor >=", nivel_significancia, 
      "→ No rechazamos H0\n")
  cat("CONCLUSIÓN: Los residuos tienen distribución NORMAL\n")
} else {
  cat("\nINTERPRETACIÓN: P-valor <", nivel_significancia, 
      "→ Rechazamos H0\n")
  cat("CONCLUSIÓN: Los residuos NO tienen distribución normal\n")
  cat("NOTA: Esto puede afectar intervalos de confianza pero no necesariamente\n")
  cat("      invalida el modelo si los residuos son ruido blanco\n")
}

# Gráficos de diagnóstico de residuos
# Convertir residuos a data frame
df_residuos <- data.frame(
  Tiempo = 1:length(residuos_modelo),
  Residuos = as.numeric(residuos_modelo),
  Residuos2 = as.numeric(residuos_modelo^2)
)

# 1. Residuos vs Tiempo
p_diag1 <- ggplot(df_residuos, aes(x = Tiempo, y = Residuos)) +
  geom_line(color = "darkblue", linewidth = 0.8) +
  geom_hline(yintercept = 0, color = "red", linetype = "dashed", linewidth = 1.5) +
  labs(title = "Residuos vs Tiempo",
       x = "Tiempo",
       y = "Residuos") +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5, size = 11, face = "bold"),
        panel.grid.minor = element_blank())

# 2. Histograma de residuos
p_diag2 <- ggplot(df_residuos, aes(x = Residuos)) +
  geom_histogram(aes(y = after_stat(density)), bins = 50, fill = "lightblue", 
                 color = "darkblue", alpha = 0.7) +
  stat_function(fun = dnorm, 
                args = list(mean = mean(residuos_modelo), sd = sd(residuos_modelo)),
                color = "red", linewidth = 1.5) +
  labs(title = "Distribución de Residuos",
       x = "Residuos",
       y = "Densidad") +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5, size = 11, face = "bold"),
        panel.grid.minor = element_blank())

# 3. Q-Q Plot (quantile-quantile plot para normalidad)
qq_data <- data.frame(
  Teorico = qqnorm(residuos_modelo, plot.it = FALSE)$x,
  Observado = qqnorm(residuos_modelo, plot.it = FALSE)$y
)

p_diag3 <- ggplot(qq_data, aes(x = Teorico, y = Observado)) +
  geom_point(color = "darkblue", alpha = 0.6) +
  geom_abline(slope = 1, intercept = 0, color = "red", linewidth = 1.5) +
  labs(title = "Q-Q Plot (Normalidad)",
       x = "Cuantiles Teóricos",
       y = "Cuantiles Observados") +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5, size = 11, face = "bold"),
        panel.grid.minor = element_blank())

# 4. ACF de residuos
p_diag4 <- ggAcf(residuos_modelo, lag.max = 30) +
  labs(title = "ACF de Residuos",
       y = "ACF") +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5, size = 11, face = "bold"),
        panel.grid.minor = element_blank())

# 5. PACF de residuos
p_diag5 <- ggPacf(residuos_modelo, lag.max = 30) +
  labs(title = "PACF de Residuos",
       y = "PACF") +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5, size = 11, face = "bold"),
        panel.grid.minor = element_blank())

# 6. Residuos al cuadrado (para detectar heterocedasticidad)
p_diag6 <- ggplot(df_residuos, aes(x = Tiempo, y = Residuos2)) +
  geom_line(color = "darkorange", linewidth = 0.8) +
  labs(title = "Residuos al Cuadrado (Heterocedasticidad)",
       x = "Tiempo",
       y = "Residuos²") +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5, size = 11, face = "bold"),
        panel.grid.minor = element_blank())

# Combinar todos los gráficos
p5 <- grid.arrange(p_diag1, p_diag2, p_diag3, p_diag4, p_diag5, p_diag6, nrow = 3, ncol = 2)

# Mostrar gráfico
print(p5)

# Guardar gráfico
ggsave(file.path(ruta_resultados, "05_Diagnostico_Residuos.png"), 
       plot = p5, 
       width = 14, height = 10, dpi = 150)
cat("\nGráfico guardado: 05_Diagnostico_Residuos.png\n")

# ------------------------------------------------------------
# 3.3 PRUEBA DE HETEROCEDASTICIDAD
# ------------------------------------------------------------

cat("\n--- Paso 3.3: Prueba de heterocedasticidad ---\n")

# PRUEBA ARCH (Autoregressive Conditional Heteroskedasticity)
# H0: No hay heterocedasticidad (varianza constante)
# H1: Hay heterocedasticidad (varianza no constante)
#
# Si p-valor < nivel_significancia: Rechazamos H0, hay heterocedasticidad
# Si p-valor >= nivel_significancia: No rechazamos H0, varianza constante

cat("\n=== PRUEBA ARCH ===\n")
cat("Hipótesis nula (H0): No hay heterocedasticidad (varianza constante)\n")
cat("Hipótesis alternativa (H1): Hay heterocedasticidad\n")
cat("Nivel de significancia:", nivel_significancia, "\n\n")

# Realizar prueba ARCH
#prueba_arch <- arch.test(modelo_arima, output = FALSE)

#cat("Resultados de la prueba ARCH:\n")
#print(prueba_arch)

# Interpretación
# p_valor_arch <- prueba_arch$p.value
# if(p_valor_arch >= nivel_significancia) {
#   cat("\nINTERPRETACIÓN: P-valor >=", nivel_significancia, 
#       "→ No rechazamos H0\n")
#   cat("CONCLUSIÓN: No hay heterocedasticidad → Varianza CONSTANTE\n")
# } else {
#   cat("\nINTERPRETACIÓN: P-valor <", nivel_significancia, 
#       "→ Rechazamos H0\n")
#   cat("CONCLUSIÓN: Hay heterocedasticidad → Varianza NO CONSTANTE\n")
#   cat("RECOMENDACIÓN: Considerar modelo GARCH para modelar la volatilidad\n")
# }

# ------------------------------------------------------------
# 3.4 RESUMEN DEL DIAGNÓSTICO
# ------------------------------------------------------------

cat("\n=== RESUMEN DEL DIAGNÓSTICO ===\n")
cat("1. Correlación de residuos (Ljung-Box):\n")
if(all(resultados_ljung$p_valor >= nivel_significancia)) {
  cat("   ✓ Residuos no correlacionados (ruido blanco)\n")
} else {
  cat("   ✗ Residuos correlacionados (problema detectado)\n")
}

cat("2. Normalidad de residuos (Shapiro-Wilk):\n")
if(prueba_shapiro$p.value >= nivel_significancia) {
  cat("   ✓ Residuos normalmente distribuidos\n")
} else {
  cat("   ✗ Residuos no normalmente distribuidos\n")
}

# cat("3. Homocedasticidad (ARCH):\n")
# if(p_valor_arch >= nivel_significancia) {
#   cat("   ✓ Varianza constante (homocedasticidad)\n")
# } else {
#   cat("   ✗ Varianza no constante (heterocedasticidad)\n")
# }

# ===================================================================
# PRONÓSTICO
# ===================================================================
# Una vez validado el modelo, se pueden realizar pronósticos
# para períodos futuros.
# ===================================================================

cat("\n=== PRONÓSTICO ===\n")

# Realizar pronóstico
pronostico <- forecast(modelo_arima, h = periodo_pronostico, level = c(80, 95))

cat("\n=== PRONÓSTICO GENERADO ===\n")
cat("Períodos pronosticados:", periodo_pronostico, "\n")
cat("Niveles de confianza: 80% y 95%\n\n")

# Mostrar pronóstico
print(pronostico)

# Gráfico del pronóstico usando autoplot de forecast
p6 <- autoplot(pronostico) +
  labs(title = paste("Pronóstico ARIMA(", orden_p, ",", orden_diferencia, ",", orden_q, ")"),
       x = "Tiempo",
       y = "Precio") +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
        panel.grid.minor = element_blank(),
        legend.position = "bottom")

# Mostrar gráfico
print(p6)

# Guardar gráfico
ggsave(file.path(ruta_resultados, "06_Pronostico.png"), 
       plot = p6, 
       width = 14, height = 7, dpi = 150)
cat("\nGráfico guardado: 06_Pronostico.png\n")

# Guardar pronóstico
pronostico_df <- data.frame(
  Periodo = 1:periodo_pronostico,
  Pronostico = as.numeric(pronostico$mean),
  Limite_Inferior_80 = as.numeric(pronostico$lower[,1]),
  Limite_Superior_80 = as.numeric(pronostico$upper[,1]),
  Limite_Inferior_95 = as.numeric(pronostico$lower[,2]),
  Limite_Superior_95 = as.numeric(pronostico$upper[,2])
)
write.csv(pronostico_df, 
          file.path(ruta_resultados, "Pronostico.csv"), 
          row.names = FALSE)
cat("Pronóstico guardado: Pronostico.csv\n")

# ===================================================================
# RESUMEN FINAL
# ===================================================================

cat("\n\n=== RESUMEN FINAL DEL ANÁLISIS ===\n")
cat("=====================================\n")
cat("MODELO ESTIMADO: ARIMA(", orden_p, ",", orden_diferencia, ",", orden_q, ")\n\n")

cat("CRITERIOS DE INFORMACIÓN:\n")
cat("  AIC:", round(aic_modelo, 2), "\n")
cat("  BIC:", round(bic_modelo, 2), "\n")
#cat("  AICc:", round(aicc_modelo, 2), "\n\n")

cat("MEDIDAS DE ERROR:\n")
cat("  RMSE:", round(rmse, 4), "\n")
cat("  MAE:", round(mae, 4), "\n")
cat("  MAPE:", round(mape, 2), "%\n\n")

cat("DIAGNÓSTICO:\n")
cat("  Ljung-Box: ", ifelse(all(resultados_ljung$p_valor >= nivel_significancia), 
                            "✓ Aprobado", "✗ Rechazado"), "\n")
cat("  Normalidad: ", ifelse(prueba_shapiro$p.value >= nivel_significancia, 
                            "✓ Aprobado", "✗ Rechazado"), "\n")
# cat("  Homocedasticidad: ", ifelse(p_valor_arch >= nivel_significancia, 
#                                   "✓ Aprobado", "✗ Rechazado"), "\n\n")

cat("RESULTADOS GUARDADOS EN:", ruta_resultados, "\n")
cat("=====================================\n")
cat("\n=== ANÁLISIS COMPLETADO ===\n")

