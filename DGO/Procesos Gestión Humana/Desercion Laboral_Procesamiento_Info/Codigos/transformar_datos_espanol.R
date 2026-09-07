# ============================================================
# Script para transformar datos a español (sin ñ ni tildes)
# ============================================================

# Cargar librerias necesarias
library(dplyr)

# ============================================================
# Funcion para remover acentos y ñ
# ============================================================
remover_acentos_ny <- function(texto) {
  if (is.na(texto) || is.null(texto)) {
    return(texto)
  }
  
  # Convertir a caracter si no lo es
  texto <- as.character(texto)
  
  # Reemplazar ñ por n primero
  texto <- gsub("ñ", "n", texto, ignore.case = TRUE)
  texto <- gsub("Ñ", "N", texto)
  
  # Mapeo manual de caracteres con acento a sin acento
  texto <- gsub("á", "a", texto, ignore.case = TRUE)
  texto <- gsub("é", "e", texto, ignore.case = TRUE)
  texto <- gsub("í", "i", texto, ignore.case = TRUE)
  texto <- gsub("ó", "o", texto, ignore.case = TRUE)
  texto <- gsub("ú", "u", texto, ignore.case = TRUE)
  texto <- gsub("Á", "A", texto)
  texto <- gsub("É", "E", texto)
  texto <- gsub("Í", "I", texto)
  texto <- gsub("Ó", "O", texto)
  texto <- gsub("Ú", "U", texto)
  
  return(texto)
}

# ============================================================
# Cargar datos originales
# ============================================================
ruta_entrada <- "Insumos/attrition_data.csv"
df <- read.csv(ruta_entrada, sep = ",", stringsAsFactors = FALSE)

# ============================================================
# Traducir nombres de columnas a español (sin ñ ni tildes)
# ============================================================
nombres_originales <- names(df)
nombres_espanol <- c(
  "EMP_ID" = "ID_EMPLEADO",
  "ANNUAL_RATE" = "SALARIO_ANUAL",
  "HRLY_RATE" = "SALARIO_POR_HORA",
  "JOBCODE" = "CODIGO_TRABAJO",
  "ETHNICITY" = "ETNIA",
  "SEX" = "SEXO",
  "MARITAL_STATUS" = "ESTADO_CIVIL",
  "JOB_SATISFACTION" = "SATISFACCION_LABORAL",
  "AGE" = "EDAD",
  "NUMBER_OF_TEAM_CHANGED" = "NUMERO_CAMBIOS_EQUIPO",
  "REFERRAL_SOURCE" = "FUENTE_REFERENCIA",
  "HIRE_MONTH" = "MES_CONTRATACION",
  "REHIRE" = "RECONTRATADO",
  "TERMINATION_YEAR" = "ANIO_TERMINACION",
  "IS_FIRST_JOB" = "ES_PRIMER_EMPLEO",
  "TRAVELLED_REQUIRED" = "VIAJES_REQUERIDOS",
  "PERFORMANCE_RATING" = "EVALUACION_DESEMPENO",
  "DISABLED_EMP" = "EMPLEADO_DISCAPACITADO",
  "DISABLED_VET" = "VETERANO_DISCAPACITADO",
  "EDUCATION_LEVEL" = "NIVEL_EDUCACION",
  "STATUS" = "ESTADO",
  "JOB_GROUP" = "GRUPO_TRABAJO",
  "PREVYR_1" = "DESEMPENO_ANIO_1",
  "PREVYR_2" = "DESEMPENO_ANIO_2",
  "PREVYR_3" = "DESEMPENO_ANIO_3",
  "PREVYR_4" = "DESEMPENO_ANIO_4",
  "PREVYR_5" = "DESEMPENO_ANIO_5"
)

# Aplicar traduccion de nombres de columnas
names(df) <- nombres_espanol[nombres_originales]

# ============================================================
# Traducir valores categoricos a español (sin ñ ni tildes)
# ============================================================

# SEXO
df$SEXO <- ifelse(df$SEXO == "M", "MASCULINO", 
                  ifelse(df$SEXO == "F", "FEMENINO", df$SEXO))

# ESTADO_CIVIL
df$ESTADO_CIVIL <- ifelse(df$ESTADO_CIVIL == "Single", "SOLTERO",
                         ifelse(df$ESTADO_CIVIL == "Married", "CASADO",
                               ifelse(df$ESTADO_CIVIL == "Divorced", "DIVORCIADO", df$ESTADO_CIVIL)))

# ETNIA
df$ETNIA <- ifelse(df$ETNIA == "WHITE", "BLANCO",
                  ifelse(df$ETNIA == "BLACK", "AFRO",
                        ifelse(df$ETNIA == "ASIAN", "ASIATICO",
                              ifelse(df$ETNIA == "HISPA", "HISPANO",
                                    ifelse(df$ETNIA == "PACIF", "AFRO", df$ETNIA)))))

# ESTADO (STATUS)
df$ESTADO <- ifelse(df$ESTADO == "A", "ACTIVO",
                   ifelse(df$ESTADO == "T", "TERMINADO", df$ESTADO))

# RECONTRATADO
df$RECONTRATADO <- ifelse(df$RECONTRATADO == "TRUE", "SI",
                         ifelse(df$RECONTRATADO == "FALSE", "NO", df$RECONTRATADO))

# ES_PRIMER_EMPLEO
df$ES_PRIMER_EMPLEO <- ifelse(df$ES_PRIMER_EMPLEO == "Y", "SI",
                             ifelse(df$ES_PRIMER_EMPLEO == "N", "NO", df$ES_PRIMER_EMPLEO))

# VIAJES_REQUERIDOS
df$VIAJES_REQUERIDOS <- ifelse(df$VIAJES_REQUERIDOS == "YES", "SI",
                              ifelse(df$VIAJES_REQUERIDOS == "NO", "NO", df$VIAJES_REQUERIDOS))

# EMPLEADO_DISCAPACITADO
df$EMPLEADO_DISCAPACITADO <- ifelse(df$EMPLEADO_DISCAPACITADO == "Y", "SI",
                                    ifelse(df$EMPLEADO_DISCAPACITADO == "N", "NO", df$EMPLEADO_DISCAPACITADO))

# VETERANO_DISCAPACITADO
df$VETERANO_DISCAPACITADO <- ifelse(df$VETERANO_DISCAPACITADO == "Y", "SI",
                                    ifelse(df$VETERANO_DISCAPACITADO == "N", "NO", df$VETERANO_DISCAPACITADO))

# MES_CONTRATACION (traducir meses)
meses_ingles <- c("January", "February", "March", "April", "May", "June",
                  "July", "August", "September", "October", "November", "December")
meses_espanol <- c("ENERO", "FEBRERO", "MARZO", "ABRIL", "MAYO", "JUNIO",
                   "JULIO", "AGOSTO", "SEPTIEMBRE", "OCTUBRE", "NOVIEMBRE", "DICIEMBRE")
names(meses_espanol) <- meses_ingles

df$MES_CONTRATACION <- ifelse(df$MES_CONTRATACION %in% meses_ingles,
                              meses_espanol[df$MES_CONTRATACION],
                              df$MES_CONTRATACION)

# FUENTE_REFERENCIA (traducir fuentes comunes)
df$FUENTE_REFERENCIA <- ifelse(df$FUENTE_REFERENCIA == "Client Referral", "REFERENCIA_CLIENTE",
                              ifelse(df$FUENTE_REFERENCIA == "Executive Referral", "REFERENCIA_EJECUTIVO",
                                    ifelse(df$FUENTE_REFERENCIA == "Former Employee/Intern", "EX_EMPLEADO_INTERNO",
                                          ifelse(df$FUENTE_REFERENCIA == "Direct Sourcing", "CONTRATACION_DIRECTA",
                                                ifelse(df$FUENTE_REFERENCIA == "Inroads", "INROADS",
                                                      ifelse(df$FUENTE_REFERENCIA == "Unknown", "DESCONOCIDO",
                                                            ifelse(df$FUENTE_REFERENCIA == "Job Fair", "FERIA_EMPLEO",
                                                                  ifelse(df$FUENTE_REFERENCIA == "Print Advertisement", "ANUNCIO_IMPRESO",
                                                                        ifelse(df$FUENTE_REFERENCIA == "Corporate Career Site", "SITIO_CARRERAS_CORPORATIVO",
                                                                              ifelse(df$FUENTE_REFERENCIA == "Agency", "AGENCIA",
                                                                                    ifelse(df$FUENTE_REFERENCIA == "College Recommendation", "RECOMENDACION_UNIVERSITARIA",
                                                                                          ifelse(df$FUENTE_REFERENCIA == "Job Posting", "PUBLICACION_EMPLEO",
                                                                                                ifelse(df$FUENTE_REFERENCIA == "Job Boards/Online Advertising", "TABLERO_EMPLEO_ANUNCIO_ONLINE",
                                                                                                      ifelse(df$FUENTE_REFERENCIA == "Open House", "CASA_ABIERTA",
                                                                                                            ifelse(df$FUENTE_REFERENCIA == "College Recruiting(UnderGrad)", "RECLUTAMIENTO_UNIVERSITARIO_PREGRADO",
                                                                                                                  ifelse(df$FUENTE_REFERENCIA == "Unsolicited", "NO_SOLICITADO",
                                                                                                                        ifelse(df$FUENTE_REFERENCIA == "Staffing Agency", "AGENCIA_PERSONAL",
                                                                                                                              ifelse(df$FUENTE_REFERENCIA == "E-Strat", "E_STRAT", df$FUENTE_REFERENCIA))))))))))))))))))

# NIVEL_EDUCACION
df$NIVEL_EDUCACION <- ifelse(df$NIVEL_EDUCACION == "LEVEL 1", "NIVEL_1",
                            ifelse(df$NIVEL_EDUCACION == "LEVEL 2", "NIVEL_2",
                                  ifelse(df$NIVEL_EDUCACION == "LEVEL 3", "NIVEL_3",
                                        ifelse(df$NIVEL_EDUCACION == "LEVEL 4", "NIVEL_4",
                                              ifelse(df$NIVEL_EDUCACION == "LEVEL 5", "NIVEL_5", df$NIVEL_EDUCACION)))))

# GRUPO_TRABAJO (traducir grupos de trabajo comunes)
# Nota: Se traduciran los grupos mas comunes, otros se dejaran como estan
df$GRUPO_TRABAJO <- gsub("Plant & Facilities Maintenance", "MANTENIMIENTO_PLANTAS_INSTALACIONES", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Customer Care", "ATENCION_CLIENTE", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Finance", "FINANZAS", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Marketing - Direct", "MARKETING_DIRECTO", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Physical Flows", "FLUJOS_FISICOS", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Tax", "IMPUESTOS", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("General Administration", "ADMINISTRACION_GENERAL", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Production & Operations", "PRODUCCION_OPERACIONES", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("R&I Development/Pre-Develpmnt", "DESARROLLO_I_D_PREDESARROLLO", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Sourcing", "ADQUISICION", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("IT Business Applications", "APLICACIONES_NEGOCIO_TI", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Promotional Purchasing", "COMPRAS_PROMOCIONALES", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Creative Service/Copy", "SERVICIO_CREATIVO_COPIA", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Engineering", "INGENIERIA", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Supply Chain Finance", "FINANZAS_CADENA_SUMINISTRO", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Technical Packaging", "EMPAQUE_TECNICO", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Human Resources", "RECURSOS_HUMANOS", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Legal", "LEGAL", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Quality Assurance", "ASEGURAMIENTO_CALIDAD", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Accounting", "CONTABILIDAD", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Marketing Support/Services", "SOPORTE_SERVICIOS_MARKETING", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Manufacturing Supply Chain", "CADENA_SUMINISTRO_MANUFACTURA", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Market Supply Logistics", "LOGISTICA_SUMINISTRO_MERCADO", df$GRUPO_TRABAJO)
df$GRUPO_TRABAJO <- gsub("Market Research", "INVESTIGACION_MERCADO", df$GRUPO_TRABAJO)

# ============================================================
# Aplicar funcion para remover acentos y ñ a todas las columnas de texto
# ============================================================
columnas_texto <- sapply(df, is.character)
for (col in names(df)[columnas_texto]) {
  df[[col]] <- sapply(df[[col]], remover_acentos_ny)
}

# ============================================================
# Guardar archivo transformado
# ============================================================
ruta_salida <- "Insumos/datos_contratacion.csv"
write.csv(df, ruta_salida, row.names = FALSE, fileEncoding = "UTF-8")

# Mensaje de confirmacion
cat("Transformacion completada.\n")
cat("Archivo guardado en:", ruta_salida, "\n")
cat("Total de registros:", nrow(df), "\n")
cat("Total de columnas:", ncol(df), "\n")

