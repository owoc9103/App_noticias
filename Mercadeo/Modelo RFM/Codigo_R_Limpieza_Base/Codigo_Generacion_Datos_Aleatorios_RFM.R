# ---------------------------------------------
# Código para Generar 3 Bases de Datos Aleatorias
# Basado en la estructura de Transacciones.csv
# Productos: CHANCE, LOTERIA, RECARGAS, RECAUDOS, BALOTO
# ---------------------------------------------

# ---------------------------------------------
# 1. Cargar librerías
# ---------------------------------------------
library(dplyr)
library(lubridate)

# ---------------------------------------------
# 2. Leer estructura de datos fuente
# ---------------------------------------------
data_source <- read.csv("C:/Users/owoc9/Documents/U Javeriana/Laboratorio Analítica/Mercadeo/Modelo RFM/Insumos/Transacciones.csv", sep=";")

# Obtener número de filas para generar datos similares
n_filas <- nrow(data_source)

# Extraer los documentos de cliente y vendedor del archivo fuente
cliente_docs <- data_source$cliente_documento
vendedor_docs <- data_source$vendedor_documento

# ---------------------------------------------
# 3. Función para generar datos aleatorios
# ---------------------------------------------
generar_base_datos <- function(n_filas, seed, nombre_base) {
  set.seed(seed)
  
  # Productos disponibles
  productos <- c("CHANCE", "LOTERIA", "RECARGAS", "RECAUDOS", "BALOTO")
  
  # Generar datos aleatorios basados en la estructura original
  data_generada <- data.frame(
    id_tiempo = sample(20210101:20211231, n_filas, replace = TRUE),
    hora = sample(6:22, n_filas, replace = TRUE),
    vlr_transaccion = round(runif(n_filas, min = 1000, max = 50000), 0),
    cant_formularios = sample(1:5, n_filas, replace = TRUE),
    vlr_flete = round(runif(n_filas, min = 0, max = 5000), 0),
    cliente_documento = sample(cliente_docs, n_filas, replace = TRUE),
    cliente_nombres = paste(sample(c("JUAN", "MARIA", "CARLOS", "ANA", "LUIS", "PATRICIA", 
                                      "JOSE", "LAURA", "PEDRO", "SANDRA", "ANDRES", "DIANA",
                                      "RICARDO", "CLAUDIA", "FERNANDO", "MONICA", "ROBERTO", 
                                      "MARTHA", "ALBERTO", "GLORIA"), n_filas, replace = TRUE),
                            sample(c("CARLOS", "ALEJANDRO", "ANDRES", "FERNANDO", "RODRIGO",
                                     "PATRICIA", "ELENA", "SOFIA", "VALENTINA", "CAMILA",
                                     "NICOLAS", "SEBASTIAN", "DANIEL", "DAVID", "MIGUEL",
                                     "ANDREA", "NATALIA", "PAULA", "JULIANA", "MARIANA"), 
                                   n_filas, replace = TRUE)),
    cliente_apellido1 = sample(c("GARCIA", "RODRIGUEZ", "LOPEZ", "MARTINEZ", "GONZALEZ",
                                  "PEREZ", "SANCHEZ", "RAMIREZ", "TORRES", "FLORES",
                                  "RIVERA", "GOMEZ", "DIAZ", "CRUZ", "MORALES",
                                  "ORTEGA", "RAMOS", "REYES", "JIMENEZ", "HERRERA"), 
                                n_filas, replace = TRUE),
    cliente_fechanacimiento = paste0(
      sample(1:28, n_filas, replace = TRUE), "/",
      sample(1:12, n_filas, replace = TRUE), "/",
      sample(1950:2000, n_filas, replace = TRUE)
    ),
    cliente_genero = sample(c("M", "F"), n_filas, replace = TRUE, prob = c(0.5, 0.5)),
    cliente_tipo_sangre = sample(c("O+", "A+", "B+", "AB+", "O-", "A-", "B-", "AB-"), 
                                  n_filas, replace = TRUE, 
                                  prob = c(0.35, 0.25, 0.15, 0.05, 0.08, 0.06, 0.04, 0.02)),
    territorio_cod_municipio = sample(c(1, 219, 568, 755, 760, 86001, 86219, 86568, 86569, 86755, 86760), 
                                       n_filas, replace = TRUE),
    territorio_nomb_municipio = sample(c("MOCOA", "COLON", "PUERTO ASIS", "SAN FRANCISCO", 
                                          "SANTIAGO", "LA HORMIGA", "PUERTO CAICEDO", 
                                          "VILLA GARZON", "SIBUNDOY", "VALLE DEL GUAMUEZ"), 
                                        n_filas, replace = TRUE),
    producto_nomb_producto = sample(productos, n_filas, replace = TRUE, 
                                    prob = c(0.25, 0.20, 0.25, 0.15, 0.15)),
    tiempo_dia_semana = sample(1:7, n_filas, replace = TRUE),
    vendedor_documento = sample(vendedor_docs, n_filas, replace = TRUE),
    vendedor_fechanacimiento = paste0(
      sample(1:28, n_filas, replace = TRUE), "/",
      sample(1:12, n_filas, replace = TRUE), "/",
      sample(1980:1995, n_filas, replace = TRUE)
    ),
    stringsAsFactors = FALSE
  )
  
  # Los documentos de cliente y vendedor se mantienen tal cual como vienen del archivo fuente
  # (sin anonimización)
  
  # Guardar base de datos
  ruta_guardado <- paste0("C:/Users/owoc9/Documents/U Javeriana/Laboratorio Analítica/Mercadeo/Modelo RFM/Resultado_R_Limpieza_Base/", nombre_base)
  write.csv(data_generada, ruta_guardado, row.names = FALSE)
  
  cat("Base de datos generada:", nombre_base, "\n")
  cat("Número de filas:", nrow(data_generada), "\n")
  cat("Distribución de productos:\n")
  print(table(data_generada$producto_nomb_producto))
  cat("\n")
  
  return(data_generada)
}

# ---------------------------------------------
# 4. Generar las 3 bases de datos
# ---------------------------------------------
cat("==========================================\n")
cat("Generando 3 bases de datos aleatorias\n")
cat("==========================================\n\n")

# Base de datos 1
data_1 <- generar_base_datos(n_filas, seed = 123, "Transacciones_Aleatorias_1.csv")

# Base de datos 2
data_2 <- generar_base_datos(n_filas, seed = 456, "Transacciones_Aleatorias_2.csv")

# Base de datos 3
data_3 <- generar_base_datos(n_filas, seed = 789, "Transacciones_Aleatorias_3.csv")

# ---------------------------------------------
# 5. Resumen final
# ---------------------------------------------
cat("==========================================\n")
cat("Resumen de generación\n")
cat("==========================================\n")
cat("Total de bases generadas: 3\n")
cat("Filas por base:", n_filas, "\n")
cat("Productos utilizados: CHANCE, LOTERIA, RECARGAS, RECAUDOS, BALOTO\n")
cat("\nBases de datos guardadas en:\n")
cat("  - Transacciones_Aleatorias_1.csv\n")
cat("  - Transacciones_Aleatorias_2.csv\n")
cat("  - Transacciones_Aleatorias_3.csv\n")
