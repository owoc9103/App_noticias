# Ejecutar desde RStudio: abra este archivo y source()
# Desde consola:
#   Rscript ejecutar_cotizacion.R              # cotización simple (1 fuente)
#   Rscript ejecutar_cotizacion.R --multifuente           # todas las fuentes
#   Rscript ejecutar_cotizacion.R --relevantes            # fuentes priorizadas (recomendado)
#   Rscript ejecutar_cotizacion.R --relevantes --test     # prueba 2 ítems
#   Rscript cotizacion_multifuente_datalab_puj.R --solo-enlaces

args_cli <- commandArgs(trailingOnly = TRUE)
MULTIFUENTE <- "--multifuente" %in% args_cli || "--relevantes" %in% args_cli
RELEVANTES  <- "--relevantes" %in% args_cli

if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
  DIR_SCRIPT <- dirname(rstudioapi::getActiveDocumentContext()$path)
} else {
  DIR_SCRIPT <- getwd()
}

if (!exists("MAX_ITEMS_SCRAPE", inherits = FALSE)) MAX_ITEMS_SCRAPE <- Inf
if (!exists("USAR_SCRAPING", inherits = FALSE)) USAR_SCRAPING <- TRUE

setwd(DIR_SCRIPT)

if (MULTIFUENTE) {
  source(file.path(DIR_SCRIPT, "cotizacion_multifuente_datalab_puj.R"), local = FALSE)
  if ("--test" %in% args_cli) assign("MAX_ITEMS_SCRAPE", 2, envir = .GlobalEnv)
  resultado <- if (RELEVANTES) main_cotizacion_relevantes() else main_multifuente()
} else {
  source(file.path(DIR_SCRIPT, "cotizacion_datalab_puj.R"), local = FALSE)
  resultado <- main()
}
