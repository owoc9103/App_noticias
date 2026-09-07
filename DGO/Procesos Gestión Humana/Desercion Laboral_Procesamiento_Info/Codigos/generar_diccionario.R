# Script para generar diccionario de datos
library(dplyr)

# Leer el archivo
df <- read.csv("Insumos/datos_contratacion.csv", sep = ";", stringsAsFactors = FALSE)

# Crear diccionario
diccionario <- data.frame(
  Variable = character(),
  Tipo = character(),
  Descripcion = character(),
  Valores_Posibles = character(),
  stringsAsFactors = FALSE
)

# Analizar cada columna
for (col in names(df)) {
  tipo <- class(df[[col]])
  valores_unicos <- unique(df[[col]])
  valores_unicos <- valores_unicos[!is.na(valores_unicos)]
  valores_unicos <- valores_unicos[valores_unicos != ""]
  
  # Limitar valores únicos si son muchos
  if (length(valores_unicos) > 20) {
    valores_texto <- paste(head(valores_unicos, 20), collapse = ", ")
    valores_texto <- paste0(valores_texto, " ... (", length(valores_unicos), " valores unicos)")
  } else {
    valores_texto <- paste(valores_unicos, collapse = ", ")
  }
  
  # Descripciones
  descripciones <- list(
    "ID_EMPLEADO" = "Identificador unico del empleado",
    "SALARIO_ANUAL" = "Salario anual del empleado en dolares",
    "SALARIO_POR_HORA" = "Salario por hora del empleado en dolares",
    "CODIGO_TRABAJO" = "Codigo numerico que identifica el tipo de trabajo",
    "ETNIA" = "Grupo etnico del empleado",
    "SEXO" = "Sexo del empleado",
    "ESTADO_CIVIL" = "Estado civil del empleado",
    "SATISFACCION_LABORAL" = "Nivel de satisfaccion laboral (escala numerica)",
    "EDAD" = "Edad del empleado en anos",
    "NUMERO_CAMBIOS_EQUIPO" = "Numero de cambios de equipo realizados",
    "FUENTE_REFERENCIA" = "Fuente mediante la cual el empleado fue referido",
    "MES_CONTRATACION" = "Mes en que fue contratado el empleado",
    "RECONTRATADO" = "Indica si el empleado fue recontratado",
    "ANIO_TERMINACION" = "Anio en que se termino la relacion laboral (si aplica)",
    "ES_PRIMER_EMPLEO" = "Indica si este fue el primer empleo del trabajador",
    "VIAJES_REQUERIDOS" = "Indica si se requieren viajes para el puesto",
    "EVALUACION_DESEMPENO" = "Calificacion del desempeno del empleado",
    "EMPLEADO_DISCAPACITADO" = "Indica si el empleado tiene alguna discapacidad",
    "VETERANO_DISCAPACITADO" = "Indica si el empleado es un veterano con discapacidad",
    "NIVEL_EDUCACION" = "Nivel educativo del empleado",
    "ESTADO" = "Estado actual del empleado (activo o terminado)",
    "GRUPO_TRABAJO" = "Grupo o departamento de trabajo al que pertenece",
    "DESEMPENO_ANIO_1" = "Desempeno del empleado en el anio 1",
    "DESEMPENO_ANIO_2" = "Desempeno del empleado en el anio 2",
    "DESEMPENO_ANIO_3" = "Desempeno del empleado en el anio 3",
    "DESEMPENO_ANIO_4" = "Desempeno del empleado en el anio 4",
    "DESEMPENO_ANIO_5" = "Desempeno del empleado en el anio 5"
  )
  
  descripcion <- ifelse(col %in% names(descripciones), descripciones[[col]], "Variable sin descripcion")
  
  diccionario <- rbind(diccionario, data.frame(
    Variable = col,
    Tipo = tipo,
    Descripcion = descripcion,
    Valores_Posibles = valores_texto,
    stringsAsFactors = FALSE
  ))
}

# Guardar diccionario
write.csv(diccionario, "Resultado/diccionario_datos.csv", row.names = FALSE)

# Mostrar diccionario
print(diccionario)
