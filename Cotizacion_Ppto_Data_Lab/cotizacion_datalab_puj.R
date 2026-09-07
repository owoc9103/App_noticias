# =============================================================================
# Cotización Laboratorio Data Lab — PUJ
# Lee la matriz base, actualiza precios vía web scraping y exporta Excel.
# =============================================================================

suppressPackageStartupMessages({
  pkgs <- c("readxl", "openxlsx", "dplyr", "stringr", "httr2", "rvest",
            "lubridate", "purrr", "jsonlite", "tibble")
  inst <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(inst)) {
    .lib_user <- Sys.getenv(
      "R_LIBS_USER",
      unset = file.path(Sys.getenv("USERPROFILE"), "Documents", "R", "win-library", paste0(R.version$major, ".", R.version$minor))
    )
    dir.create(.lib_user, recursive = TRUE, showWarnings = FALSE)
    install.packages(inst, repos = "https://cloud.r-project.org", lib = .lib_user)
    .libPaths(c(.lib_user, .libPaths()))
  }
  invisible(lapply(pkgs, library, character.only = TRUE))
})

# --- Configuración ------------------------------------------------------------
FECHA_COTIZACION <- Sys.Date()
args_run <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args_run, value = TRUE)
DIR_BASE <- if (exists("DIR_SCRIPT") && nzchar(DIR_SCRIPT)) {
  DIR_SCRIPT
} else if (length(file_arg)) {
  dirname(normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/"))
} else {
  getwd()
}

ARCHIVO_ENTRADA  <- file.path(DIR_BASE, "cotizacion_laboratorio_datos_fisico.xlsx")
ARCHIVO_SALIDA   <- file.path(
  DIR_BASE,
  sprintf("cotizacion_laboratorio_datos_%s.xlsx", format(FECHA_COTIZACION, "%Y%m%d"))
)

USAR_SCRAPING    <- TRUE
DELAY_SEGUNDOS   <- 1.8
MAX_ITEMS_SCRAPE <- Inf   # Inf = todos; use un entero para pruebas rápidas
TRM_USD_COP      <- NA_real_  # opcional: si define TRM, convierte precios USD encontrados

UA <- paste(
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
  "AppleWebKit/537.36 (KHTML, like Gecko)",
  "Chrome/122.0.0.0 Safari/537.36"
)

# --- Utilidades de precio -----------------------------------------------------
limpiar_numero_cop <- function(x) {
  if (length(x) == 0 || all(is.na(x))) return(NA_real_)
  x <- as.character(x[1])
  x <- str_trim(x)
  if (!nzchar(x)) return(NA_real_)
  num <- str_remove_all(x, "[^0-9.,]")
  if (str_detect(num, ",") && str_detect(num, "\\.")) {
    num <- str_remove_all(num, ",")
  } else {
    num <- str_replace_all(num, ",", "")
    num <- str_replace_all(num, "\\.", "")
  }
  val <- suppressWarnings(as.numeric(num))
  if (is.na(val) || val < 5000 || val > 2e9) NA_real_ else val
}

extraer_precios_texto <- function(texto) {
  if (is.na(texto) || !nzchar(texto)) return(numeric(0))
  candidatos <- character(0)
  patrones <- c(
    "\\$\\s*([0-9]{1,3}(?:\\.[0-9]{3})+)",
    "([0-9]{1,3}(?:\\.[0-9]{3})+)\\s*COP",
    "\"price\"\\s*:\\s*\"?(\\d+)\"?",
    "\"amount\"\\s*:\\s*\"?(\\d+)\"?",
    "itemprop=\"price\"[^>]*content=\"([0-9.]+)\"",
    "product:price:amount\"[^>]*content=\"([0-9.]+)\""
  )
  for (p in patrones) {
    m <- str_match_all(texto, regex(p, ignore_case = TRUE))[[1]]
    if (nrow(m)) candidatos <- c(candidatos, m[, 2])
  }
  vals <- vapply(candidatos, limpiar_numero_cop, numeric(1))
  vals <- vals[!is.na(vals)]
  unique(vals)
}

filtrar_candidatos <- function(precios, referencia = NA_real_) {
  precios <- precios[precios >= 15000 & precios <= 1.5e9]
  if (!length(precios)) return(numeric(0))
  if (!is.na(referencia) && referencia > 0) {
    en_rango <- precios[precios >= referencia * 0.2 & precios <= referencia * 5]
    if (length(en_rango)) return(en_rango)
  }
  precios
}

elegir_precio <- function(precios, referencia = NA_real_) {
  precios <- filtrar_candidatos(precios, referencia)
  if (!length(precios)) return(NA_real_)
  as.numeric(stats::median(precios))
}

precio_scrape_aceptable <- function(nuevo, referencia, estado_actual = NA_character_) {
  if (is.na(nuevo) || nuevo <= 0) return(FALSE)
  if (is.na(referencia) || referencia <= 0) return(TRUE)
  ratio <- nuevo / referencia
  flexible <- any(str_detect(
    coalesce(estado_actual, ""),
    regex("estimado|cotizar", ignore_case = TRUE)
  ))
  limites <- if (flexible) c(0.15, 6) else c(0.55, 1.8)
  ratio >= limites[1] && ratio <= limites[2]
}

http_get_texto <- function(url, timeout = 25) {
  if (is.na(url) || !nzchar(url) || !str_detect(url, "^https?://")) {
    return(list(ok = FALSE, texto = "", status = NA_integer_, error = "URL vacía"))
  }
  tryCatch({
    resp <- request(url) |>
      req_headers(
        `User-Agent` = UA,
        Accept = "text/html,application/xhtml+xml,application/json",
        `Accept-Language` = "es-CO,es;q=0.9,en;q=0.8"
      ) |>
      req_timeout(timeout) |>
      req_retry(max_tries = 2) |>
      req_perform()
    list(
      ok = resp_status(resp) < 400,
      texto = resp_body_string(resp),
      status = resp_status(resp),
      error = NA_character_
    )
  }, error = function(e) {
    list(ok = FALSE, texto = "", status = NA_integer_, error = conditionMessage(e))
  })
}

# --- Scraping: Mercado Libre --------------------------------------------------
id_mercadolibre <- function(url) {
  m <- str_match(url, "(MCO[A-Z0-9]+)")
  if (is.na(m[1, 2])) NA_character_ else m[1, 2]
}

consulta_desde_url_ml <- function(url) {
  if (is.na(url)) return(NA_character_)
  if (str_detect(url, "listado\\.mercadolibre")) {
    slug <- str_match(url, "listado\\.mercadolibre\\.com\\.co/([^\n?#]+)")[, 2]
    return(str_replace_all(slug, "-", " "))
  }
  slug <- str_match(url, "mercadolibre\\.com\\.co/([^\n?#/]+)")[, 2]
  if (!is.na(slug) && !str_detect(slug, "^(p|up|MCO)")) {
    return(str_replace_all(slug, "-", " "))
  }
  NA_character_
}

scrape_mercadolibre_api <- function(item_id) {
  url <- sprintf("https://api.mercadolibre.com/items/%s", item_id)
  res <- http_get_texto(url)
  if (!res$ok) return(list(precio = NA_real_, metodo = "ML API", detalle = res$error %||% "HTTP error"))
  precios <- extraer_precios_texto(res$texto)
  list(
    precio = elegir_precio(precios),
    metodo = "ML API",
    detalle = if (is.na(elegir_precio(precios))) "Sin precio en JSON" else "OK"
  )
}

scrape_mercadolibre_html <- function(url, referencia) {
  res <- http_get_texto(url)
  if (!res$ok || nchar(res$texto) < 8000) {
    return(list(precio = NA_real_, metodo = "ML HTML", detalle = "Página bloqueada o vacía"))
  }
  precios <- extraer_precios_texto(res$texto)
  list(
    precio = elegir_precio(precios, referencia),
    metodo = "ML HTML",
    detalle = sprintf("%d candidatos", length(precios))
  )
}

# --- Scraping: búsqueda web (DuckDuckGo HTML) ---------------------------------
buscar_precio_motor <- function(consulta, referencia = NA_real_, motor = c("ddg", "bing")) {
  if (is.na(consulta) || !nzchar(consulta)) {
    return(list(precio = NA_real_, metodo = motor, detalle = "Consulta vacía"))
  }
  q <- paste(consulta, "precio COP Colombia")
  tryCatch({
    if (motor[1] == "bing") {
      resp <- request("https://www.bing.com/search") |>
        req_url_query(q = q) |>
        req_headers(`User-Agent` = UA, `Accept-Language` = "es-CO,es;q=0.9") |>
        req_timeout(25) |>
        req_perform()
      metodo <- "Búsqueda web (Bing)"
    } else {
      resp <- request("https://html.duckduckgo.com/html/") |>
        req_method("POST") |>
        req_headers(`User-Agent` = UA, `Accept-Language` = "es-CO,es;q=0.9") |>
        req_body_form(q = q) |>
        req_timeout(25) |>
        req_perform()
      metodo <- "Búsqueda web (DDG)"
    }
    precios <- extraer_precios_texto(resp_body_string(resp))
    list(
      precio = elegir_precio(precios, referencia),
      metodo = metodo,
      detalle = sprintf("%d candidatos | q=%s", length(precios), str_trunc(q, 60))
    )
  }, error = function(e) {
    list(precio = NA_real_, metodo = motor[1], detalle = conditionMessage(e))
  })
}

buscar_precio_ddg <- function(consulta, referencia = NA_real_) {
  buscar_precio_motor(consulta, referencia, "ddg")
}

buscar_precio_bing <- function(consulta, referencia = NA_real_) {
  buscar_precio_motor(consulta, referencia, "bing")
}

buscar_precio_web <- function(consulta, referencia = NA_real_) {
  for (fn in list(buscar_precio_ddg, buscar_precio_bing)) {
    out <- fn(consulta, referencia)
    if (!is.na(out$precio)) return(out)
  }
  list(precio = NA_real_, metodo = "Búsqueda web", detalle = "Sin resultados DDG/Bing")
}

# --- Scraping genérico por URL ------------------------------------------------
scrape_url_generica <- function(url, referencia) {
  res <- http_get_texto(url)
  if (!res$ok) {
    return(list(precio = NA_real_, metodo = "HTML directo", detalle = res$error %||% "fallo HTTP"))
  }
  precios <- extraer_precios_texto(res$texto)
  list(
    precio = elegir_precio(precios, referencia),
    metodo = "HTML directo",
    detalle = sprintf("status %s | %d candidatos", res$status, length(precios))
  )
}

`%||%` <- function(a, b) if (!is.null(a) && length(a) && !is.na(a[1])) a else b

# --- Orquestador de scraping por ítem -----------------------------------------
scrape_precio_item <- function(elemento, url, referencia, estado_actual) {
  if (!USAR_SCRAPING) {
    return(list(
      precio = referencia,
      metodo = "Sin scraping",
      detalle = "USAR_SCRAPING = FALSE",
      estado = estado_actual
    ))
  }

  if (is.na(url) || !nzchar(url) || str_detect(tolower(url), "por cotizar|proveedor")) {
    q <- elemento
    out <- buscar_precio_web(q, referencia)
    if (!is.na(out$precio)) {
      out$estado <- "Cotizado web"
      return(out)
    }
    return(list(
      precio = referencia,
      metodo = "Referencia base",
      detalle = "Sin URL comercial; búsqueda sin resultado",
      estado = estado_actual
    ))
  }

  if (str_detect(url, "mercadolibre")) {
    iid <- id_mercadolibre(url)
    if (!is.na(iid)) {
      out <- scrape_mercadolibre_api(iid)
      if (!is.na(out$precio)) {
        out$estado <- "Cotizado web"
        return(out)
      }
      out <- scrape_mercadolibre_html(url, referencia)
      if (!is.na(out$precio)) {
        out$estado <- "Cotizado web"
        return(out)
      }
    }
    q <- consulta_desde_url_ml(url)
    if (!is.na(q)) {
      out <- buscar_precio_web(q, referencia)
      if (!is.na(out$precio)) {
        out$estado <- "Cotizado web"
        return(out)
      }
    }
  }

  if (str_detect(url, "^(https?://)")) {
    out <- scrape_url_generica(url, referencia)
    if (!is.na(out$precio)) {
      out$estado <- "Cotizado web"
      return(out)
    }
  }

  out <- buscar_precio_web(elemento, referencia)
  if (!is.na(out$precio)) {
    out$estado <- "Cotizado web"
    return(out)
  }

  list(
    precio = referencia,
    metodo = "Referencia base",
    detalle = "Scraping sin precio válido; se conserva valor base",
    estado = estado_actual
  )
}

# --- Lectura y transformación -------------------------------------------------
leer_cotizacion_base <- function(path) {
  raw <- read_excel(path, sheet = "Cotización Base", col_names = FALSE)
  hdr <- as.character(unlist(raw[1, ]))
  datos <- raw[-1, ]
  names(datos) <- make.names(hdr, unique = TRUE)
  names(datos) <- c(
    "id", "categoria", "subcategoria", "elemento", "prioridad", "cantidad",
    "costo_unitario_cop", "subtotal_cop", "especificaciones", "observacion",
    "enlace", "estado_precio"
  )
  datos <- datos |>
    mutate(
      id = as.integer(id),
      cantidad = as.numeric(cantidad),
      costo_unitario_cop = as.numeric(costo_unitario_cop),
      subtotal_cop = as.numeric(subtotal_cop),
      across(
        c(categoria, subcategoria, elemento, prioridad, especificaciones,
          observacion, enlace, estado_precio),
        ~ as.character(.x)
      )
    )
  datos
}

actualizar_precios <- function(df) {
  log_rows <- vector("list", nrow(df))
  n_scrape <- min(nrow(df), if (is.infinite(MAX_ITEMS_SCRAPE)) nrow(df) else MAX_ITEMS_SCRAPE)

  for (i in seq_len(nrow(df))) {
    ref <- df$costo_unitario_cop[i]
    if (i <= n_scrape) {
      message(sprintf("[%02d/%02d] Cotizando: %s", i, nrow(df), df$elemento[i]))
      res <- scrape_precio_item(
        df$elemento[i],
        df$enlace[i],
        ref,
        df$estado_precio[i]
      )
      Sys.sleep(DELAY_SEGUNDOS)
    } else {
      res <- list(
        precio = ref,
        metodo = "No procesado",
        detalle = "MAX_ITEMS_SCRAPE",
        estado = df$estado_precio[i]
      )
    }

    nuevo <- res$precio
    scraped_ok <- !res$metodo %in% c("Referencia base", "No procesado", "Sin scraping")
    aceptado <- scraped_ok &&
      precio_scrape_aceptable(nuevo, ref, df$estado_precio[i])
    precio_final <- if (aceptado) nuevo else ref

    if (aceptado && !is.na(nuevo) && nuevo > 0) {
      df$costo_unitario_cop[i] <- round(nuevo)
      df$subtotal_cop[i] <- df$costo_unitario_cop[i] * df$cantidad[i]
      df$estado_precio[i] <- "Cotizado web"
    }

    log_rows[[i]] <- tibble(
      id = df$id[i],
      elemento = df$elemento[i],
      precio_base = ref,
      precio_obtenido = ifelse(is.na(nuevo), NA, nuevo),
      precio_aplicado = precio_final,
      aceptado = aceptado,
      variacion_pct = ifelse(
        is.na(ref) | ref == 0 | is.na(nuevo),
        NA_real_,
        round(100 * (nuevo - ref) / ref, 1)
      ),
      metodo = res$metodo,
      detalle = if (aceptado) res$detalle else paste(res$detalle, "| rechazado: fuera de rango"),
      enlace = df$enlace[i]
    )
  }

  list(cotizacion = df, log = bind_rows(log_rows))
}

resumen_por_categoria <- function(df) {
  total <- sum(df$subtotal_cop, na.rm = TRUE)
  df |>
    group_by(categoria) |>
    summarise(total_cop = sum(subtotal_cop, na.rm = TRUE), .groups = "drop") |>
    mutate(participacion = total_cop / total) |>
    arrange(desc(total_cop)) |>
    bind_rows(
      tibble(
        categoria = "TOTAL GENERAL",
        total_cop = total,
        participacion = 1
      )
    )
}

kpis_proyecto <- function(df) {
  tibble(
    indicador = c(
      "Fecha de elaboración",
      "Cantidad de ítems",
      "Puestos estudiantes",
      "Total obligatorio",
      "Total recomendado + opcional + avanzado",
      "Total general"
    ),
    valor = c(
      as.character(FECHA_COTIZACION),
      as.character(nrow(df)),
      as.character(sum(df$cantidad[df$subcategoria == "Equipos estudiantes"], na.rm = TRUE)),
      as.character(sum(
        df$subtotal_cop[df$prioridad == "Obligatorio"],
        na.rm = TRUE
      )),
      as.character(sum(
        df$subtotal_cop[df$prioridad %in% c("Recomendado", "Opcional", "Avanzado")],
        na.rm = TRUE
      )),
      as.character(sum(df$subtotal_cop, na.rm = TRUE))
    )
  )
}

supuestos_fuentes <- function() {
  tibble(
    campo = c(
      "Alcance",
      "Precios",
      "IVA",
      "Obligatorio",
      "Recomendado",
      "Opcional",
      "Avanzado",
      "Scraping",
      "Fuente técnica JupyterHub",
      "Fuente técnica NVIDIA",
      "Fuente técnica IBM Jupyter Notebook Server"
    ),
    descripcion = c(
      "Matriz para implementar un laboratorio físico de analítica de datos (Data Lab PUJ) con 30 puestos estudiante, docente, servidores, red, almacenamiento, energía, visualización e instalación.",
      sprintf(
        "Precios actualizados automáticamente vía web scraping el %s. Validar con proveedores antes de compra institucional.",
        FECHA_COTIZACION
      ),
      "Los valores pueden incluir o no IVA según proveedor. Agregar columna de IVA en etapa de compras.",
      "Elemento mínimo para operación del laboratorio.",
      "Fortalece continuidad, rendimiento e investigación aplicada.",
      "Puede moverse a fase posterior.",
      "IA, deep learning o investigación intensiva.",
      "Métodos: API/HTML Mercado Libre, HTML de enlace, búsqueda DuckDuckGo. Si un sitio bloquea bots, se conserva precio base.",
      "https://jupyterhub.readthedocs.io/en/latest/explanation/capacity-planning.html",
      "https://docs.nvidia.com/certification-programs/latest/nvidia-certified-configuration-guide.html",
      "https://www.ibm.com/docs/es/cognos-analytics/12.0.x?topic=server-hardware-requirements-jupyter-notebook"
    )
  )
}

exportar_excel <- function(cotizacion, resumen, kpis, supuestos, log_scrape, path_out) {
  wb <- createWorkbook()

  header_cot <- c(
    "ID", "Categoría", "Subcategoría", "Elemento", "Prioridad", "Cantidad",
    "Costo unitario COP", "Subtotal COP",
    "Características / especificaciones sugeridas",
    "Observación / razón de requerimiento",
    "Enlace producto / fuente", "Estado precio"
  )

  cot_out <- cotizacion |>
    transmute(
      ID = id,
      Categoría = categoria,
      Subcategoría = subcategoria,
      Elemento = elemento,
      Prioridad = prioridad,
      Cantidad = cantidad,
      `Costo unitario COP` = costo_unitario_cop,
      `Subtotal COP` = subtotal_cop,
      `Características / especificaciones sugeridas` = especificaciones,
      `Observación / razón de requerimiento` = observacion,
      `Enlace producto / fuente` = enlace,
      `Estado precio` = estado_precio
    )

  addWorksheet(wb, "Cotización Base")
  writeData(wb, "Cotización Base", t(header_cot), startRow = 1)
  writeData(wb, "Cotización Base", cot_out, startRow = 2)

  addWorksheet(wb, "Resumen")
  writeData(wb, "Resumen", data.frame(
    Categoría = resumen$categoria,
    `Total COP` = resumen$total_cop,
    Participación = resumen$participacion,
    check.names = FALSE
  ), startRow = 1)
  writeData(wb, "Resumen", kpis, startCol = 5, startRow = 1)

  addWorksheet(wb, "Supuestos y Fuentes")
  writeData(wb, "Supuestos y Fuentes", supuestos, startRow = 1)

  addWorksheet(wb, "Log scraping")
  writeData(wb, "Log scraping", log_scrape, startRow = 1)

  header_style <- createStyle(
    textDecoration = "bold",
    fgFill = "#D9E1F2",
    border = "Bottom",
    halign = "center",
    wrapText = TRUE
  )
  money_style <- createStyle(numFmt = "#,##0")
  pct_style <- createStyle(numFmt = "0.00%")

  for (ws in c("Cotización Base", "Resumen", "Supuestos y Fuentes", "Log scraping")) {
    addStyle(wb, ws, header_style, rows = 1, cols = 1:20, gridExpand = TRUE)
    setColWidths(wb, ws, cols = 1:12, widths = "auto")
  }

  addStyle(wb, "Cotización Base", money_style, rows = 2:(nrow(cot_out) + 1), cols = 7:8, gridExpand = TRUE)
  addStyle(wb, "Resumen", money_style, rows = 2:(nrow(resumen) + 1), cols = 2, gridExpand = TRUE)
  addStyle(wb, "Resumen", pct_style, rows = 2:(nrow(resumen) + 1), cols = 3, gridExpand = TRUE)

  saveWorkbook(wb, path_out, overwrite = TRUE)
  invisible(path_out)
}

# --- Ejecución ----------------------------------------------------------------
main <- function() {
  if (!file.exists(ARCHIVO_ENTRADA)) {
    stop("No se encuentra el archivo base: ", ARCHIVO_ENTRADA, call. = FALSE)
  }

  message("Leyendo: ", ARCHIVO_ENTRADA)
  base <- leer_cotizacion_base(ARCHIVO_ENTRADA)

  message("Iniciando cotización web (puede tardar varios minutos)...")
  actualizado <- actualizar_precios(base)

  cot <- actualizado$cotizacion
  resumen <- resumen_por_categoria(cot)
  kpis <- kpis_proyecto(cot)
  sup <- supuestos_fuentes()

  path_out <- exportar_excel(
    cot, resumen, kpis, sup, actualizado$log, ARCHIVO_SALIDA
  )

  message("\n=== Cotización Data Lab PUJ ===")
  message("Ítems: ", nrow(cot))
  message("Total COP: ", format(sum(cot$subtotal_cop), big.mark = "."))
  message("Archivo generado: ", path_out)
  invisible(list(
    cotizacion = cot,
    resumen = resumen,
    log = actualizado$log,
    archivo = path_out
  ))
}

if (sys.nframe() == 0) {
  args_cli <- commandArgs(trailingOnly = TRUE)
  if ("--test" %in% args_cli) MAX_ITEMS_SCRAPE <- 5
  if ("--sin-scraping" %in% args_cli) USAR_SCRAPING <- FALSE
  main()
}
