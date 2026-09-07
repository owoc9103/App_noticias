# =============================================================================
# Cotización Multi-fuente — Laboratorio Data Lab PUJ
# Mismos ítems cotizados en varios portales de tecnología y mobiliario.
# =============================================================================

# --- Inicialización de rutas y dependencias -----------------------------------
`%||%` <- function(a, b) {
  if (!is.null(a) && length(a) && !is.na(a[1]) && nzchar(as.character(a[1]))) a else b
}

resolver_dir_script <- function() {
  if (exists("DIR_SCRIPT", inherits = TRUE)) {
    ds <- get("DIR_SCRIPT", inherits = TRUE)
    if (length(ds) && nzchar(ds[1])) {
      return(normalizePath(ds[1], winslash = "/", mustWork = FALSE))
    }
  }
  if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
    p <- tryCatch(
      rstudioapi::getActiveDocumentContext()$path,
      error = function(e) ""
    )
    if (length(p) && nzchar(p)) {
      return(dirname(normalizePath(p, winslash = "/", mustWork = FALSE)))
    }
  }
  args_run <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args_run, value = TRUE)
  if (length(file_arg)) {
    return(dirname(normalizePath(
      sub("^--file=", "", file_arg[1]),
      winslash = "/",
      mustWork = FALSE
    )))
  }
  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}

inicializar_config_multifuente <- function(dir_proyecto = NULL) {
  dir <- dir_proyecto %||% resolver_dir_script()
  assign("DIR_SCRIPT", dir, envir = .GlobalEnv)
  assign("DIR_BASE", dir, envir = .GlobalEnv)

  if (!exists("FECHA_COTIZACION", inherits = TRUE)) {
    assign("FECHA_COTIZACION", Sys.Date(), envir = .GlobalEnv)
  }
  fecha <- get("FECHA_COTIZACION", envir = .GlobalEnv)

  assign(
    "ARCHIVO_ENTRADA",
    file.path(dir, "cotizacion_laboratorio_datos_fisico.xlsx"),
    envir = .GlobalEnv
  )
  assign(
    "ARCHIVO_SALIDA",
    file.path(
      dir,
      sprintf("cotizacion_multifuente_datalab_%s.xlsx", format(fecha, "%Y%m%d"))
    ),
    envir = .GlobalEnv
  )

  ruta_utilidades <- file.path(dir, "cotizacion_datalab_puj.R")
  if (!file.exists(ruta_utilidades)) {
    stop(
      "No se encuentra cotizacion_datalab_puj.R en:\n  ", dir,
      call. = FALSE
    )
  }
  if (!exists("leer_cotizacion_base", mode = "function", inherits = TRUE)) {
    source(ruta_utilidades, local = FALSE)
    assign("DIR_BASE", dir, envir = .GlobalEnv)
    assign("ARCHIVO_ENTRADA", file.path(dir, "cotizacion_laboratorio_datos_fisico.xlsx"), envir = .GlobalEnv)
  }

  if (!exists("USAR_SCRAPING", inherits = TRUE)) assign("USAR_SCRAPING", TRUE, envir = .GlobalEnv)
  if (!exists("MAX_ITEMS_SCRAPE", inherits = TRUE)) assign("MAX_ITEMS_SCRAPE", Inf, envir = .GlobalEnv)
  if (!exists("DELAY_PORTAL", inherits = TRUE)) assign("DELAY_PORTAL", 1.2, envir = .GlobalEnv)

  invisible(list(
    dir = dir,
    entrada = get("ARCHIVO_ENTRADA", envir = .GlobalEnv),
    salida = get("ARCHIVO_SALIDA", envir = .GlobalEnv)
  ))
}

# Cargar utilidades al hacer source() del archivo completo
inicializar_config_multifuente()

DELAY_PORTAL       <- 0.35   # segundos entre consultas (0 si hay caché)
DELAY_PORTAL_MISS  <- 0.55
HTTP_TIMEOUT       <- 12
HTTP_MAX_TRIES     <- 1
USAR_DDG           <- FALSE  # solo Bing (más rápido)
VALIDAR_CONTENIDO  <- TRUE
MIN_PALABRAS_CLAVE <- 1L     # mínimo de términos del ítem en página/enlace

# Caché de HTTP en la sesión (evita repetir la misma URL)
.cache_http <- new.env(parent = emptyenv())

# --- Catálogo de portales -----------------------------------------------------
PORTALES_TECNOLOGIA <- list(
  list(
    id = "mercadolibre", nombre = "Mercado Libre", dominio = "mercadolibre.com.co",
    tipo = "Tecnología",     buscar_url = function(q) {
      slug <- str_replace_all(tolower(q), "[^a-z0-9]+", "-")
      slug <- str_replace_all(slug, "(^-+|-+$)", "")
      paste0("https://listado.mercadolibre.com.co/", slug)
    }
  ),
  list(id = "falabella", nombre = "Falabella", dominio = "falabella.com.co", tipo = "Tecnología"),
  list(id = "alkosto", nombre = "Alkosto", dominio = "alkosto.com", tipo = "Tecnología",
       buscar_url = function(q) {
         paste0("https://www.alkosto.com/search?text=", URLencode(q, reserved = TRUE))
       }),
  list(id = "ktronix", nombre = "Ktronix", dominio = "ktronix.com", tipo = "Tecnología",
       buscar_url = function(q) {
         paste0("https://www.ktronix.com/search?query=", URLencode(q, reserved = TRUE))
       }),
  list(id = "exito", nombre = "Éxito", dominio = "exito.com", tipo = "Tecnología",
       buscar_url = function(q) {
         paste0("https://www.exito.com/s?q=", URLencode(q, reserved = TRUE))
       }),
  list(id = "alkomprar", nombre = "Alkomprar", dominio = "alkomprar.com", tipo = "Tecnología",
       buscar_url = function(q) {
         paste0("https://www.alkomprar.com/search?q=", URLencode(q, reserved = TRUE))
       }),
  list(id = "janus", nombre = "Janus", dominio = "janus.com.co", tipo = "Tecnología"),
  list(id = "linio", nombre = "Linio", dominio = "linio.com.co", tipo = "Tecnología")
)

PORTALES_MOBILIARIO <- list(
  list(id = "mercadolibre", nombre = "Mercado Libre", dominio = "mercadolibre.com.co",
       tipo = "Mobiliario", buscar_url = PORTALES_TECNOLOGIA[[1]]$buscar_url),
  list(id = "falabella", nombre = "Falabella", dominio = "falabella.com.co", tipo = "Mobiliario"),
  list(id = "homecenter", nombre = "Homecenter", dominio = "homecenter.com.co", tipo = "Mobiliario",
       buscar_url = function(q) {
         paste0("https://www.homecenter.com.co/homecenter-co/search?q=", URLencode(q, reserved = TRUE))
       }),
  list(id = "officedepot", nombre = "Office Depot", dominio = "officedepot.com.co", tipo = "Mobiliario",
       buscar_url = function(q) {
         paste0("https://www.officedepot.com.co/officedepot-co/search?q=", URLencode(q, reserved = TRUE))
       }),
  list(id = "exito", nombre = "Éxito", dominio = "exito.com", tipo = "Mobiliario",
       buscar_url = PORTALES_TECNOLOGIA[[5]]$buscar_url),
  list(id = "alkosto", nombre = "Alkosto", dominio = "alkosto.com", tipo = "Mobiliario",
       buscar_url = PORTALES_TECNOLOGIA[[3]]$buscar_url)
)

PORTALES_GENERAL <- list(
  list(id = "mercadolibre", nombre = "Mercado Libre", dominio = "mercadolibre.com.co", tipo = "General",
       canal = "Retail", buscar_url = PORTALES_TECNOLOGIA[[1]]$buscar_url),
  list(id = "falabella", nombre = "Falabella", dominio = "falabella.com.co", tipo = "General", canal = "Retail"),
  list(id = "alkosto", nombre = "Alkosto", dominio = "alkosto.com", tipo = "General", canal = "Retail",
       buscar_url = PORTALES_TECNOLOGIA[[3]]$buscar_url),
  list(id = "exito", nombre = "Éxito", dominio = "exito.com", tipo = "General", canal = "Retail",
       buscar_url = PORTALES_TECNOLOGIA[[5]]$buscar_url)
)

# Helper para portales corporativos / institucionales (Oscar — fuentes formales)
crear_portal_corp <- function(id, nombre, dominio, segmentos, url_catalogo,
                              tipo = "Corporativo", cotizacion_formal = TRUE,
                              notas = NA_character_) {
  list(
    id = id,
    nombre = nombre,
    dominio = dominio,
    tipo = tipo,
    canal = "Corporativo / fabricante",
    segmentos = segmentos,
    url_catalogo = url_catalogo,
    cotizacion_formal = cotizacion_formal,
    notas = notas
  )
}

PORTALES_CORPORATIVOS <- list(
  # --- Computadores -----------------------------------------------------------
  crear_portal_corp(
    "dell_co", "Dell Colombia", "dell.com",
    c("computadores", "servidores", "mayorista"),
    "https://www.dell.com/es-co/lp"
  ),
  crear_portal_corp(
    "microhome_dell", "Microhome — Dell Colombia", "microhome.com.co",
    c("computadores", "mayorista"),
    "https://microhome.com.co/computadores-dell-colombia/"
  ),
  crear_portal_corp(
    "lenovo_co", "Lenovo Colombia", "lenovo.com",
    c("computadores", "workstations", "servidores", "mayorista"),
    "https://www.lenovo.com/co/es/"
  ),
  # --- Workstations -----------------------------------------------------------
  crear_portal_corp(
    "lenovo_ws", "Lenovo Workstations Colombia", "lenovo.com",
    c("workstations"),
    "https://www.lenovo.com/co/es/workstations/"
  ),
  crear_portal_corp(
    "microhome_lenovo_ws", "Microhome — Lenovo Workstations", "microhome.com.co",
    c("workstations"),
    "https://microhome.com.co/lenovo-workstations/"
  ),
  crear_portal_corp(
    "hp_z_ws", "HP Z Workstations Colombia", "hp.com",
    c("workstations"),
    "https://www.hp.com/co-es/workstations/workstation-pcs.html"
  ),
  crear_portal_corp(
    "hp_estaciones", "HP Colombia — estaciones de trabajo", "hp.com",
    c("workstations"),
    "https://www.hp.com/co-es/shop/tech-takes/estaciones-trabajo-hp"
  ),
  # --- Servidores -------------------------------------------------------------
  crear_portal_corp(
    "hpe_productos", "HPE — productos Latinoamérica", "hpe.com",
    c("servidores", "red_switch"),
    "https://www.hpe.com/lamerica/es/products.html"
  ),
  crear_portal_corp(
    "hpe_contacto_co", "HPE — contacto Colombia", "hpe.com",
    c("servidores"),
    "https://www.hpe.com/lamerica/es/contact-hpe-colombia.html",
    notas = "Cotización formal vía contacto comercial"
  ),
  crear_portal_corp(
    "lenovo_servers", "Lenovo Servers Colombia", "lenovo.com",
    c("servidores", "nas"),
    "https://www.lenovo.com/co/es/servers-storage/servers/"
  ),
  crear_portal_corp(
    "elenst_dell", "Elenst — Dell / infraestructura", "elenst.com",
    c("servidores", "computadores", "mayorista"),
    "https://www.elenst.com/dell-colombia/"
  ),
  # --- NAS --------------------------------------------------------------------
  crear_portal_corp(
    "synology_wtb", "Synology — dónde comprar", "synology.com",
    c("nas"),
    "https://www.synology.com/es-es/wheretobuy"
  ),
  crear_portal_corp(
    "qnap_dist", "QNAP — distribuidores Colombia", "qnap.com",
    c("nas"),
    "https://www.qnap.com/en/where-to-buy/latin-america-caribbean/colombia/nas-distributor"
  ),
  crear_portal_corp(
    "lasus_qnap", "Lasus — QNAP Colombia", "lasus.com.co",
    c("nas", "mayorista"),
    "https://lasus.com.co/es/brand/227-qnap"
  ),
  crear_portal_corp(
    "lasus_nas", "Lasus — NAS Synology / QNAP / HP", "lasus.com.co",
    c("nas"),
    "https://lasus.com.co/es/content/servidor-nas-synology-Qnap-HP"
  ),
  # --- Red --------------------------------------------------------------------
  crear_portal_corp(
    "cisco_switches", "Cisco — switches", "cisco.com",
    c("red_switch"),
    "https://www.cisco.com/site/mx/es/products/networking/switches/index.html"
  ),
  crear_portal_corp(
    "cisco_contacto_co", "Cisco — contacto Colombia", "cisco.com",
    c("red_switch", "red_wifi"),
    "https://www.cisco.com/site/co/es/about/contact-cisco/index.html"
  ),
  crear_portal_corp(
    "elenst_cisco", "Elenst — Cisco Colombia", "elenst.com",
    c("red_switch"),
    "https://www.elenst.com/donde-comprar-cisco-en-colombia/"
  ),
  crear_portal_corp(
    "hpe_aruba", "HPE Aruba — switches", "hpe.com",
    c("red_switch"),
    "https://www.hpe.com/lamerica/es/aruba-cx-switches.html"
  ),
  crear_portal_corp(
    "ubiquiti_dist", "Ubiquiti — distribuidores oficiales", "ui.com",
    c("red_wifi"),
    "https://www.ui.com/distributors/"
  ),
  crear_portal_corp(
    "elenst_ubiquiti", "Elenst — Ubiquiti Colombia", "elenst.com",
    c("red_wifi"),
    "https://www.elenst.com/ubiquiti-colombia-donde-comprar/"
  ),
  crear_portal_corp(
    "lasus_ubiquiti", "Lasus — Ubiquiti Colombia", "lasus.com.co",
    c("red_wifi", "mayorista"),
    "https://lasus.com.co/es/brand/1203-ubiquiti"
  ),
  # --- Firewall ---------------------------------------------------------------
  crear_portal_corp(
    "fortinet_quote", "Fortinet — solicitar cotización", "fortinet.com",
    c("firewall"),
    "https://www.fortinet.com/lat/corporate/about-us/request-a-quote",
    notas = "Formulario de cotización; sin precio público"
  ),
  crear_portal_corp(
    "fortinet_contact", "Fortinet — contacto / reseller", "fortinet.com",
    c("firewall"),
    "https://www.fortinet.com/support/contact"
  ),
  # --- UPS --------------------------------------------------------------------
  crear_portal_corp(
    "apc_schneider", "APC / Schneider Electric Colombia", "se.com",
    c("ups"),
    "https://www.se.com/co/es/brands/apc/"
  ),
  crear_portal_corp(
    "apc_easyups", "APC Easy UPS Colombia", "se.com",
    c("ups"),
    "https://www.se.com/co/es/product-range/65934-apc-easyups/"
  ),
  crear_portal_corp(
    "schneider_ups_online", "Schneider Easy UPS Online", "se.com",
    c("ups_online"),
    "https://www.se.com/co/es/product-range/65883-easy-ups-online/"
  ),
  # --- Proyectores ------------------------------------------------------------
  crear_portal_corp(
    "epson_edu", "Epson — proyectores educación", "epson.com.co",
    c("proyector"),
    "https://epson.com.co/proyectores-educacion"
  ),
  crear_portal_corp(
    "epson_edu_pro", "Epson — educación profesional", "epson.com.co",
    c("proyector"),
    "https://epson.com.co/proyectores-educacion-profesional"
  ),
  crear_portal_corp(
    "epson_shop", "Epson — tienda oficial proyectores", "shop.epson.com.co",
    c("proyector"),
    "https://shop.epson.com.co/proyectores"
  ),
  # --- Pantallas / monitores --------------------------------------------------
  crear_portal_corp(
    "samsung_displays", "Samsung Business Displays Colombia", "samsung.com",
    c("pantallas"),
    "https://www.samsung.com/co/business/displays/"
  ),
  crear_portal_corp(
    "samsung_monitores", "Samsung — monitores empresariales", "samsung.com",
    c("pantallas", "monitores"),
    "https://www.samsung.com/co/monitors/business/"
  ),
  crear_portal_corp(
    "lg_business", "LG Business Colombia", "lg.com",
    c("pantallas"),
    "https://www.lg.com/co/business/"
  ),
  crear_portal_corp(
    "lg_info_display", "LG Information Display Colombia", "lg.com",
    c("pantallas"),
    "https://www.lg.com/co/business/information-display/acerca-de-lg-information-display/"
  ),
  # --- Videoconferencia / audio -----------------------------------------------
  crear_portal_corp(
    "logitech_group", "Logitech GROUP", "logitech.com",
    c("videoconf"),
    "https://www.logitech.com/es-mx/products/video-conferencing/conference-cameras/group-conferencecam.html"
  ),
  crear_portal_corp(
    "oficomputo_logitech", "Oficomputo — Logitech GROUP Colombia", "oficomputo.co",
    c("videoconf"),
    "https://oficomputo.co/producto/logitech-group-videoconferencia/"
  ),
  # --- Mayoristas / compras institucionales -----------------------------------
  crear_portal_corp(
    "colombia_compra", "Colombia Compra Eficiente — computadores", "colombiacompra.gov.co",
    c("mayorista", "computadores"),
    "https://www.colombiacompra.gov.co/archivos/portfolio-item/compra-y-alquiler-de-computadores-y-perifericos-etp-iii",
    tipo = "Institucional",
    notas = "Acuerdo marco ETP; cotización vía proceso institucional"
  ),
  crear_portal_corp(
    "nexsys", "Nexsys Colombia", "nexsysla.com",
    c("mayorista"),
    "https://www.nexsysla.com/co/"
  ),
  crear_portal_corp(
    "intcomex", "Intcomex Colombia", "intcomex.com",
    c("mayorista"),
    "https://store.intcomex.com/es-XEC/Products/Category/cpt"
  ),
  crear_portal_corp(
    "td_synnex_dell", "TD SYNNEX — Dell", "holatdsynnex.com",
    c("mayorista", "computadores", "servidores"),
    "https://www.holatdsynnex.com/fabricante-dell.html"
  )
)

# Añadir canal Retail a portales existentes si falta
anadir_canal_retail <- function(lst) {
  lapply(lst, function(p) {
    if (is.null(p$canal)) p$canal <- "Retail"
    p
  })
}
PORTALES_TECNOLOGIA <- anadir_canal_retail(PORTALES_TECNOLOGIA)
PORTALES_MOBILIARIO <- anadir_canal_retail(PORTALES_MOBILIARIO)
PORTALES_GENERAL <- anadir_canal_retail(PORTALES_GENERAL)

segmentos_de_item <- function(categoria, subcategoria, elemento) {
  elem <- tolower(paste(elemento, subcategoria, categoria))
  segs <- character()

  if (categoria == "Puestos de trabajo") {
    if (str_detect(subcategoria, "Equipos estudiantes|Equipo docente")) segs <- c(segs, "computadores")
    if (str_detect(subcategoria, "Monitor|Visualización")) segs <- c(segs, "monitores", "pantallas")
    if (str_detect(subcategoria, "Perif")) segs <- c(segs, "mayorista")
  }
  if (categoria == "Cómputo avanzado") segs <- c(segs, "workstations", "mayorista")
  if (categoria == "Servidores") segs <- c(segs, "servidores", "mayorista")
  if (categoria == "Almacenamiento") {
    if (str_detect(elem, "nas")) segs <- c(segs, "nas")
    segs <- c(segs, "mayorista")
  }
  if (categoria == "Red") {
    if (str_detect(elem, "switch|10gbe|gigabit")) segs <- c(segs, "red_switch")
    if (str_detect(elem, "wi.?fi|access point")) segs <- c(segs, "red_wifi")
    if (str_detect(elem, "firewall")) segs <- c(segs, "firewall")
    if (str_detect(elem, "cableado")) segs <- c(segs, "mayorista")
  }
  if (categoria == "Energía y protección") {
    if (str_detect(elem, "ups")) {
      segs <- c(segs, "ups")
      if (str_detect(elem, "online")) segs <- c(segs, "ups_online")
    }
    if (str_detect(elem, "aire acondicionado")) segs <- c(segs, "mayorista")
  }
  if (categoria %in% c("Rack y montaje", "Seguridad física")) segs <- c(segs, "mayorista")
  if (categoria == "Visualización") segs <- c(segs, "pantallas")
  if (categoria == "Audiovisuales") {
    if (str_detect(elem, "proyector")) segs <- c(segs, "proyector")
    if (str_detect(elem, "cámara|ptz|micr|sonido|audio")) segs <- c(segs, "videoconf")
  }
  if (categoria == "Implementación") segs <- c(segs, "mayorista", "servicios")
  if (categoria == "Mobiliario") segs <- c(segs, "mobiliario")

  unique(segs)
}

portales_corporativos_para_item <- function(categoria, subcategoria, elemento) {
  segs <- segmentos_de_item(categoria, subcategoria, elemento)
  if (!length(segs)) return(list())

  Filter(function(p) {
    any(p$segmentos %in% segs)
  }, PORTALES_CORPORATIVOS)
}

combinar_portales <- function(...) {
  lst <- unlist(list(...), recursive = FALSE)
  if (!length(lst)) return(list())
  ids <- vapply(lst, `[[`, "", "id")
  lst[!duplicated(ids)]
}

portales_retail_para_item <- function(categoria, subcategoria) {
  if (categoria == "Mobiliario") return(PORTALES_MOBILIARIO)
  if (categoria == "Implementación") {
    return(list(
      list(
        id = "integrador", nombre = "Integrador / proveedor local", dominio = "colombia.co",
        tipo = "Servicios", canal = "Servicios"
      ),
      list(
        id = "mercadolibre", nombre = "Mercado Libre (referencia)", dominio = "mercadolibre.com.co",
        tipo = "General", canal = "Retail", buscar_url = PORTALES_TECNOLOGIA[[1]]$buscar_url
      )
    ))
  }
  if (categoria %in% c(
    "Puestos de trabajo", "Cómputo avanzado", "Servidores", "Almacenamiento",
    "Red", "Energía y protección", "Rack y montaje", "Visualización",
    "Audiovisuales", "Seguridad física"
  )) {
    return(PORTALES_TECNOLOGIA)
  }
  PORTALES_GENERAL
}

# IDs de fuentes priorizadas (retail con precio + corporativas institucionales clave)
IDS_RETAIL_RELEVANTE <- c(
  "mercadolibre", "falabella", "alkosto", "ktronix", "exito"
)
IDS_RETAIL_MOBILIARIO_RELEVANTE <- c(
  "mercadolibre", "falabella", "homecenter", "officedepot"
)

IDS_CORP_POR_SEGMENTO <- list(
  computadores   = c("dell_co", "lenovo_co", "colombia_compra", "intcomex"),
  workstations   = c("lenovo_ws", "hp_z_ws", "microhome_lenovo_ws", "elenst_dell"),
  servidores     = c("hpe_productos", "hpe_contacto_co", "lenovo_servers", "elenst_dell", "nexsys"),
  nas            = c("lasus_nas", "synology_wtb", "qnap_dist"),
  red_switch     = c("elenst_cisco", "hpe_aruba"),
  red_wifi       = c("lasus_ubiquiti", "elenst_ubiquiti"),
  firewall       = c("fortinet_quote", "fortinet_contact"),
  ups            = c("apc_schneider", "apc_easyups"),
  ups_online     = c("schneider_ups_online"),
  proyector      = c("epson_shop", "epson_edu"),
  pantallas      = c("samsung_displays", "lg_business"),
  monitores      = c("samsung_monitores"),
  videoconf      = c("oficomputo_logitech", "logitech_group"),
  mayorista      = c("nexsys", "intcomex", "td_synnex_dell"),
  servicios      = c("colombia_compra", "nexsys")
)

filtrar_portales_por_id <- function(portales, ids) {
  if (!length(portales) || !length(ids)) return(list())
  portales[vapply(portales, function(p) p$id %in% ids, logical(1))]
}

portales_relevantes_para_item <- function(categoria, subcategoria, elemento) {
  segs <- segmentos_de_item(categoria, subcategoria, elemento)

  if (categoria == "Mobiliario") {
    return(filtrar_portales_por_id(PORTALES_MOBILIARIO, IDS_RETAIL_MOBILIARIO_RELEVANTE))
  }

  if (categoria == "Implementación") {
    return(combinar_portales(
      list(
        list(
          id = "integrador", nombre = "Integrador / proveedor local",
          dominio = "colombia.co", tipo = "Servicios", canal = "Servicios"
        )
      ),
      filtrar_portales_por_id(PORTALES_CORPORATIVOS, c("colombia_compra", "nexsys"))
    ))
  }

  corp_ids <- unique(unlist(
    IDS_CORP_POR_SEGMENTO[intersect(names(IDS_CORP_POR_SEGMENTO), segs)],
    use.names = FALSE
  ))
  if ("mayorista" %in% segs) {
    corp_ids <- unique(c(corp_ids, IDS_CORP_POR_SEGMENTO$mayorista))
  }

  retail <- filtrar_portales_por_id(
    portales_retail_para_item(categoria, subcategoria),
    IDS_RETAIL_RELEVANTE
  )
  corp <- filtrar_portales_por_id(PORTALES_CORPORATIVOS, corp_ids)
  combinar_portales(retail, corp)
}

catalogo_fuentes_relevantes <- function() {
  tibble(
    Segmento = names(IDS_CORP_POR_SEGMENTO),
    `Portales corporativos (IDs)` = vapply(
      IDS_CORP_POR_SEGMENTO,
      function(x) paste(x, collapse = ", "),
      character(1)
    )
  ) |>
    bind_rows(tibble(
      Segmento = "Retail tecnología",
      `Portales corporativos (IDs)` = paste(IDS_RETAIL_RELEVANTE, collapse = ", ")
    )) |>
    bind_rows(tibble(
      Segmento = "Retail mobiliario",
      `Portales corporativos (IDs)` = paste(IDS_RETAIL_MOBILIARIO_RELEVANTE, collapse = ", ")
    ))
}

portales_para_item <- function(categoria, subcategoria, elemento = NA_character_) {
  if (exists("MODO_FUENTES", inherits = TRUE) &&
      get("MODO_FUENTES", inherits = TRUE) == "relevantes") {
    return(portales_relevantes_para_item(categoria, subcategoria, elemento))
  }
  retail <- portales_retail_para_item(categoria, subcategoria)
  corp <- portales_corporativos_para_item(categoria, subcategoria, elemento)
  combinar_portales(retail, corp)
}

catalogo_fuentes_corporativas <- function() {
  bind_rows(lapply(PORTALES_CORPORATIVOS, function(p) {
    tibble(
      ID_portal = p$id,
      Portal = p$nombre,
      Dominio = p$dominio,
      Tipo = p$tipo,
      Canal = p$canal,
      Segmentos = paste(p$segmentos, collapse = ", "),
      `Enlace cotización` = p$url_catalogo,
      `Cotización formal` = if (isTRUE(p$cotizacion_formal)) "Sí" else "No",
      Notas = coalesce(p$notas, "")
    )
  }))
}

enlaces_corporativos_por_item <- function(df) {
  filas <- vector("list", 0)
  for (i in seq_len(nrow(df))) {
    item <- df[i, ]
    corp <- portales_corporativos_para_item(
      item$categoria, item$subcategoria, item$elemento
    )
    for (j in seq_along(corp)) {
      p <- corp[[j]]
      filas[[length(filas) + 1]] <- tibble(
        ID = item$id,
        Categoría = item$categoria,
        Subcategoría = item$subcategoria,
        Elemento = item$elemento,
        Portal = p$nombre,
        Segmentos = paste(p$segmentos, collapse = ", "),
        `Enlace cotización` = p$url_catalogo,
        `Cotización formal` = if (isTRUE(p$cotizacion_formal)) "Sí" else "No",
        Notas = coalesce(p$notas, "")
      )
    }
  }
  bind_rows(filas)
}

consulta_para_item <- function(elemento, subcategoria, portal) {
  q <- elemento
  if (str_detect(subcategoria, "Monitor|Visualización") && !str_detect(tolower(elemento), "monitor|pantalla|proyector|tv")) {
    q <- paste(elemento, "monitor pantalla")
  }
  if (str_detect(subcategoria, "Equipos estudiantes|docente|Workstation|GPU|Servidor")) {
    q <- str_trunc(q, 80)
  }
  q
}

# --- Validación de relevancia del enlace / página -----------------------------
STOPWORDS_ES <- c(
  "para", "con", "del", "las", "los", "una", "tipo", "mas", "por", "como",
  "este", "esta", "todo", "todos", "base", "apps", "apps", "sala", "docente",
  "estudiante", "estudiantes", "institucional", "modular", "basico", "básico"
)

PALABRAS_SEGMENTO <- list(
  computadores = c("computador", "computer", "desktop", "portatil", "portátil", "all in one", "aio", "pc"),
  workstations = c("workstation", "thinkstation", "precision", "estacion", "estación", "threadripper", "xeon"),
  servidores   = c("servidor", "server", "proliant", "poweredge", "rack", "xeon", "epyc"),
  nas          = c("nas", "almacenamiento", "storage", "synology", "qnap", "raid"),
  red_switch   = c("switch", "gigabit", "10gbe", "sfp", "cisco", "aruba", "red"),
  red_wifi     = c("wifi", "wi-fi", "access point", "ubiquiti", "inalambrico", "inalámbrico"),
  firewall     = c("firewall", "fortinet", "utm", "seguridad perimetral"),
  ups          = c("ups", "apc", "schneider", "solar", "regulador", "kva"),
  proyector    = c("proyector", "projector", "lumens", "lúmenes", "epson"),
  pantallas    = c("pantalla", "display", "monitor", "pulgadas", "4k", "uhd", "led"),
  videoconf    = c("camara", "cámara", "ptz", "videoconferencia", "microfono", "micrófono", "logitech"),
  mobiliario   = c("mesa", "silla", "ergonomica", "ergonómica", "mobiliario", "escritorio")
)

palabras_clave_item <- function(elemento, subcategoria, categoria) {
  texto <- tolower(paste(elemento, subcategoria, categoria))
  tokens <- unlist(str_split(texto, "[^a-záéíóúñ0-9]+"))
  tokens <- tokens[nchar(tokens) >= 4 & !tokens %in% STOPWORDS_ES]

  segs <- segmentos_de_item(categoria, subcategoria, elemento)
  extra <- unlist(PALABRAS_SEGMENTO[intersect(names(PALABRAS_SEGMENTO), segs)], use.names = FALSE)

  nums <- str_extract_all(texto, "\\d+")[[1]]
  nums <- nums[nchar(nums) >= 2]

  unique(c(tokens, extra, nums))
}

es_pagina_bloqueada <- function(texto) {
  if (is.na(texto) || !nzchar(texto)) return(TRUE)
  if (nchar(texto) < 2500) return(TRUE)
  str_detect(texto, regex(
    "micro-landing|are you a robot|captcha|access denied|enable javascript|cf-browser-verification",
    ignore_case = TRUE
  ))
}

validar_relevancia <- function(texto, url, keywords, es_catalogo_institucional = FALSE) {
  if (!VALIDAR_CONTENIDO) {
    return(list(valido = TRUE, score = 1, motivo = "Validación desactivada"))
  }
  if (!length(keywords)) {
    return(list(valido = TRUE, score = 0.5, motivo = "Sin palabras clave definidas"))
  }

  if (es_pagina_bloqueada(texto)) {
    return(list(valido = FALSE, score = 0, motivo = "Página bloqueada o sin contenido útil"))
  }

  blob <- tolower(paste(
    substr(texto, 1, min(nchar(texto), 120000L)),
    url %||% ""
  ))

  hits <- vapply(keywords, function(k) {
    str_detect(blob, fixed(k))
  }, logical(1))
  n_hits <- sum(hits)
  score <- n_hits / length(keywords)

  min_req <- if (es_catalogo_institucional) 1L else max(MIN_PALABRAS_CLAVE, 1L)

  if (n_hits >= min_req) {
    return(list(
      valido = TRUE,
      score = round(score, 3),
      motivo = sprintf("Coinciden %d/%d términos del ítem", n_hits, length(keywords))
    ))
  }

  if (es_catalogo_institucional && !is.na(url) && nzchar(url)) {
    return(list(
      valido = TRUE,
      score = 0.25,
      motivo = "Catálogo institucional (cotización formal en portal)"
    ))
  }

  list(
    valido = FALSE,
    score = round(score, 3),
    motivo = sprintf("Enlace no relacionado (%d/%d términos)", n_hits, length(keywords))
  )
}

http_get_texto_cached <- function(url, timeout = HTTP_TIMEOUT) {
  if (is.na(url) || !nzchar(url)) {
    return(list(ok = FALSE, texto = "", status = NA_integer_, error = "URL vacía", cache = FALSE))
  }
  if (exists(url, envir = .cache_http, inherits = FALSE)) {
    out <- get(url, envir = .cache_http)
    out$cache <- TRUE
    return(out)
  }
  out <- http_get_texto(url, timeout = timeout)
  out$cache <- FALSE
  assign(url, out, envir = .cache_http)
  out
}

# --- Búsqueda por portal ------------------------------------------------------
extraer_enlace_portal <- function(html, dominio) {
  if (is.na(html) || !nzchar(html)) return(NA_character_)
  pat <- sprintf("https?://[^\"'\\s<>]*%s[^\"'\\s<>]*", str_replace_all(dominio, "\\.", "\\\\."))
  links <- str_match_all(html, pat)[[1]][, 1]
  links <- unique(links[!is.na(links)])
  links <- links[!str_detect(links, regex("logo|icon|css|js|png|jpg|svg", ignore_case = TRUE))]
  if (length(links)) links[1] else NA_character_
}

buscar_precio_site_bing <- function(consulta, dominio, referencia = NA_real_) {
  q <- paste(consulta, "site:", dominio, "precio COP Colombia")
  tryCatch({
    resp <- request("https://www.bing.com/search") |>
      req_url_query(q = q) |>
      req_headers(`User-Agent` = UA, `Accept-Language` = "es-CO,es;q=0.9") |>
      req_timeout(25) |>
      req_perform()
    html <- resp_body_string(resp)
    precios <- extraer_precios_texto(html)
    list(
      precio = elegir_precio(precios, referencia),
      metodo = paste("Bing site:", dominio),
      detalle = sprintf("%d candidatos", length(precios)),
      enlace = extraer_enlace_portal(html, dominio)
    )
  }, error = function(e) {
    list(precio = NA_real_, metodo = "Bing", detalle = conditionMessage(e), enlace = NA_character_)
  })
}

buscar_precio_site_ddg <- function(consulta, dominio, referencia = NA_real_) {
  q <- paste(consulta, "site:", dominio, "precio COP Colombia")
  tryCatch({
    resp <- request("https://html.duckduckgo.com/html/") |>
      req_method("POST") |>
      req_headers(`User-Agent` = UA, `Accept-Language` = "es-CO,es;q=0.9") |>
      req_body_form(q = q) |>
      req_timeout(25) |>
      req_perform()
    html <- resp_body_string(resp)
    precios <- extraer_precios_texto(html)
    list(
      precio = elegir_precio(precios, referencia),
      metodo = paste("DDG site:", dominio),
      detalle = sprintf("%d candidatos", length(precios)),
      enlace = extraer_enlace_portal(html, dominio)
    )
  }, error = function(e) {
    list(precio = NA_real_, metodo = "DDG", detalle = conditionMessage(e), enlace = NA_character_)
  })
}

buscar_precio_en_portal <- function(consulta, portal_info, referencia, keywords) {
  out <- buscar_precio_site_bing(consulta, portal_info$dominio, referencia)
  if (!is.na(out$precio) && !is.na(out$enlace) && nzchar(out$enlace)) {
    pg <- http_get_texto_cached(out$enlace)
    val <- validar_relevancia(pg$texto, out$enlace, keywords, FALSE)
    if (val$valido) {
      out$enlace_valido <- TRUE
      out$score_relevancia <- val$score
      out$motivo_validacion <- val$motivo
      return(out)
    }
    out$precio <- NA_real_
    out$detalle <- paste(out$detalle, "| enlace no validado:", val$motivo)
  }
  if (USAR_DDG) {
    out2 <- buscar_precio_site_ddg(consulta, portal_info$dominio, referencia)
    if (!is.na(out2$precio) && !is.na(out2$enlace) && nzchar(out2$enlace)) {
      pg <- http_get_texto_cached(out2$enlace)
      val <- validar_relevancia(pg$texto, out2$enlace, keywords, FALSE)
      if (val$valido) {
        out2$enlace_valido <- TRUE
        out2$score_relevancia <- val$score
        out2$motivo_validacion <- val$motivo
        return(out2)
      }
    }
  }
  list(
    precio = NA_real_, metodo = "Sin resultado",
    detalle = "Sin precio con enlace validado",
    enlace = NA_character_,
    enlace_valido = FALSE, score_relevancia = 0, motivo_validacion = "Sin coincidencia"
  )
}

empaquetar_resultado_scrape <- function(
    precio, metodo, detalle, enlace, texto_pagina, url,
    keywords, es_catalogo_institucional = FALSE
) {
  val <- validar_relevancia(texto_pagina, url, keywords, es_catalogo_institucional)
  list(
    precio = precio,
    metodo = metodo,
    detalle = paste(detalle, val$motivo, sep = " | "),
    enlace = enlace,
    enlace_valido = val$valido,
    score_relevancia = val$score,
    motivo_validacion = val$motivo
  )
}

scrape_portal_catalogo <- function(portal_info, referencia, keywords) {
  url <- portal_info$url_catalogo
  res <- http_get_texto_cached(url)
  es_inst <- isTRUE(portal_info$cotizacion_formal)

  if (!res$ok) {
    return(empaquetar_resultado_scrape(
      NA_real_, "Enlace institucional",
      res$error %||% "No se pudo abrir catálogo",
      url, "", url, keywords, es_inst
    ))
  }

  precios <- extraer_precios_texto(res$texto)
  precio <- elegir_precio(precios, referencia)

  if (!is.na(precio)) {
    return(empaquetar_resultado_scrape(
      precio, paste("Catálogo", portal_info$nombre),
      sprintf("Precio en catálogo | %d candidatos", length(precios)),
      url, res$texto, url, keywords, es_inst
    ))
  }

  empaquetar_resultado_scrape(
    NA_real_, "Enlace institucional",
    if (es_inst) "Sin precio público; cotización formal" else "Catálogo sin precio",
    url, res$texto, url, keywords, es_inst
  )
}

scrape_portal_directo <- function(consulta, portal_info, referencia, keywords) {
  if (!is.null(portal_info$url_catalogo) && nzchar(portal_info$url_catalogo)) {
    out <- scrape_portal_catalogo(portal_info, referencia, keywords)
    if (!is.na(out$precio) && isTRUE(out$enlace_valido)) return(out)
    if (isTRUE(portal_info$cotizacion_formal) && isTRUE(out$enlace_valido)) return(out)
  }

  if (!is.null(portal_info$buscar_url)) {
    url <- portal_info$buscar_url(consulta)
    res <- http_get_texto_cached(url)
    if (res$ok && !es_pagina_bloqueada(res$texto)) {
      precios <- extraer_precios_texto(res$texto)
      precio <- elegir_precio(precios, referencia)
      if (!is.na(precio)) {
        out <- empaquetar_resultado_scrape(
          precio, paste("Búsqueda directa", portal_info$nombre),
          sprintf("URL portal | %d candidatos", length(precios)),
          url, res$texto, url, keywords, FALSE
        )
        if (isTRUE(out$enlace_valido)) return(out)
      }
    }
  }

  buscar_precio_en_portal(consulta, portal_info, referencia, keywords)
}

cotizar_item_portal <- function(fila, portal_info) {
  ref <- fila$costo_unitario_cop
  consulta <- consulta_para_item(fila$elemento, fila$subcategoria, portal_info)
  keywords <- palabras_clave_item(fila$elemento, fila$subcategoria, fila$categoria)

  res <- if (!USAR_SCRAPING) {
    list(
      precio = NA_real_, metodo = "Sin scraping", detalle = "Desactivado",
      enlace = NA_character_, enlace_valido = FALSE,
      score_relevancia = 0, motivo_validacion = "Scraping off"
    )
  } else if (!is.na(fila$enlace) && nzchar(fila$enlace) &&
             str_detect(fila$enlace, fixed(portal_info$dominio))) {
    pg <- http_get_texto_cached(fila$enlace)
    precios <- if (pg$ok) extraer_precios_texto(pg$texto) else numeric(0)
    precio <- elegir_precio(precios, ref)
    val <- validar_relevancia(pg$texto, fila$enlace, keywords, FALSE)
    out <- list(
      precio = precio,
      metodo = "Enlace base Excel",
      detalle = sprintf("Referencia original | %d candidatos", length(precios)),
      enlace = fila$enlace,
      enlace_valido = val$valido && !is.na(precio),
      score_relevancia = val$score,
      motivo_validacion = val$motivo
    )
    if (!val$valido) {
      out$precio <- NA_real_
      out$detalle <- paste(out$detalle, "| enlace no validado")
    }
    out
  } else {
    scrape_portal_directo(consulta, portal_info, ref, keywords)
  }

  if (is.null(res$enlace_valido)) res$enlace_valido <- FALSE
  if (is.null(res$score_relevancia)) res$score_relevancia <- 0
  if (is.null(res$motivo_validacion)) res$motivo_validacion <- ""

  scraped_ok <- !res$metodo %in% c("Referencia base", "Sin scraping", "Sin resultado")
  enlace_ok <- isTRUE(res$enlace_valido)
  aceptado <- scraped_ok && enlace_ok &&
    !is.na(res$precio) &&
    precio_scrape_aceptable(res$precio, ref, fila$estado_precio)

  enlace_cat <- portal_info$url_catalogo %||% NA_character_
  es_institucional <- identical(res$metodo, "Enlace institucional") &&
    enlace_ok && !is.na(enlace_cat) && nzchar(enlace_cat)

  estado_fila <- if (aceptado) {
    "Cotizado web"
  } else if (es_institucional) {
    "Referencia institucional"
  } else if (enlace_ok && !is.na(res$precio)) {
    "Precio rechazado (rango)"
  } else {
    "Sin cotización"
  }

  tibble(
    id = fila$id,
    categoria = fila$categoria,
    subcategoria = fila$subcategoria,
    elemento = fila$elemento,
    prioridad = fila$prioridad,
    cantidad = fila$cantidad,
    portal = portal_info$nombre,
    dominio = portal_info$dominio,
    canal = portal_info$canal %||% "Retail",
    tipo_portal = portal_info$tipo,
    precio_referencia = ref,
    costo_unitario_cop = if (aceptado) round(res$precio) else NA_real_,
    subtotal_cop = if (aceptado) round(res$precio) * fila$cantidad else NA_real_,
    enlace = coalesce(res$enlace, enlace_cat, fila$enlace),
    enlace_catalogo = enlace_cat,
    enlace_validado = enlace_ok,
    score_relevancia = res$score_relevancia,
    motivo_validacion = res$motivo_validacion,
    metodo = res$metodo,
    aceptado = aceptado,
    detalle = res$detalle,
    estado = estado_fila,
    fecha_consulta = as.character(FECHA_COTIZACION)
  )
}

cotizar_multifuente <- function(df) {
  filas <- vector("list", 0)
  n_items <- min(nrow(df), if (is.infinite(MAX_ITEMS_SCRAPE)) nrow(df) else MAX_ITEMS_SCRAPE)

  for (i in seq_len(nrow(df))) {
    item <- df[i, ]
    portales <- portales_para_item(item$categoria, item$subcategoria, item$elemento)
    message(sprintf(
      "[%02d/%02d] %s — %d portales",
      i, nrow(df), item$elemento, length(portales)
    ))

    if (i <= n_items) {
      for (j in seq_along(portales)) {
        filas[[length(filas) + 1]] <- cotizar_item_portal(item, portales[[j]])
        last <- filas[[length(filas)]]
        delay <- if (exists("DELAY_PORTAL", inherits = TRUE)) {
          get("DELAY_PORTAL", inherits = TRUE)
        } else {
          DELAY_PORTAL
        }
        if (!isTRUE(last$enlace_validado) && exists("DELAY_PORTAL_MISS")) {
          delay <- DELAY_PORTAL_MISS
        }
        Sys.sleep(delay)
      }
    } else {
      for (j in seq_along(portales)) {
        p <- portales[[j]]
        filas[[length(filas) + 1]] <- tibble(
          id = item$id, categoria = item$categoria, subcategoria = item$subcategoria,
          elemento = item$elemento, prioridad = item$prioridad, cantidad = item$cantidad,
          portal = p$nombre, dominio = p$dominio, canal = p$canal %||% "Retail",
          tipo_portal = p$tipo, precio_referencia = item$costo_unitario_cop,
          costo_unitario_cop = NA_real_, subtotal_cop = NA_real_,
          enlace = item$enlace, enlace_catalogo = p$url_catalogo %||% NA_character_,
          metodo = "No procesado", aceptado = FALSE,
          detalle = "MAX_ITEMS_SCRAPE", estado = "Sin cotización",
          fecha_consulta = as.character(FECHA_COTIZACION)
        )
      }
    }
  }

  bind_rows(filas)
}

resumen_por_item <- function(multi) {
  multi |>
    filter(aceptado, !is.na(costo_unitario_cop)) |>
    group_by(id, elemento, categoria, prioridad, cantidad, precio_referencia) |>
    summarise(
      n_fuentes = n(),
      precio_min = min(costo_unitario_cop),
      portal_min = portal[which.min(costo_unitario_cop)],
      precio_max = max(costo_unitario_cop),
      portal_max = portal[which.max(costo_unitario_cop)],
      precio_mediano = median(costo_unitario_cop),
      precio_promedio = mean(costo_unitario_cop),
      .groups = "drop"
    ) |>
    mutate(
      subtotal_mejor_precio = precio_min * cantidad,
      ahorro_vs_referencia_pct = round(100 * (precio_referencia - precio_min) / precio_referencia, 1)
    )
}

consolidar_mejor_precio <- function(df_base, resumen_items) {
  if (nrow(resumen_items) == 0) {
    return(df_base |>
      mutate(
        costo_unitario_original = costo_unitario_cop,
        portal_recomendado = NA_character_,
        n_fuentes_cotizadas = 0L,
        precio_aplicado = NA_real_
      ))
  }
  df_base |>
    left_join(
      resumen_items |>
        select(id, precio_aplicado = precio_min, portal_recomendado = portal_min, n_fuentes_cotizadas = n_fuentes),
      by = c("id" = "id")
    ) |>
    mutate(
      costo_unitario_original = costo_unitario_cop,
      costo_unitario_cop = coalesce(precio_aplicado, costo_unitario_cop),
      subtotal_cop = costo_unitario_cop * cantidad,
      estado_precio = if_else(
        !is.na(precio_aplicado),
        paste0("Mejor precio (", portal_recomendado, ", ", n_fuentes_cotizadas, " fuentes)"),
        estado_precio
      )
    )
}

matriz_comparativa <- function(multi) {
  if (!requireNamespace("tidyr", quietly = TRUE)) {
    install.packages("tidyr", repos = "https://cloud.r-project.org", lib = .libPaths()[1])
  }
  multi |>
    filter(aceptado, !is.na(costo_unitario_cop)) |>
    select(id, elemento, portal, costo_unitario_cop) |>
    tidyr::pivot_wider(
      id_cols = c(id, elemento),
      names_from = portal,
      values_from = costo_unitario_cop,
      values_fn = min
    )
}

supuestos_multifuente <- function() {
  n_corp <- length(PORTALES_CORPORATIVOS)
  tibble(
    campo = c(
      "Alcance",
      "Multi-fuente",
      "Portales retail",
      "Portales corporativos",
      "Fuentes institucionales",
      "Precios",
      "Selección",
      "Limitaciones",
      "Validación de enlaces",
      "Rendimiento"
    ),
    descripcion = c(
      "Comparativo de los 35 ítems del Data Lab PUJ en retail + fabricantes + mayoristas + canales institucionales.",
      "Cada ítem se consulta en portales retail y en fuentes corporativas según segmento (computadores, servidores, NAS, red, UPS, etc.).",
      paste(vapply(PORTALES_TECNOLOGIA, `[[`, "", "nombre"), collapse = ", "),
      sprintf("%d fuentes corporativas (Dell, Lenovo, HP, HPE, Cisco, Fortinet, APC, Epson, Samsung, LG, Logitech, mayoristas). Ver hoja 'Catálogo Corporativo'.", n_corp),
      "Estado 'Referencia institucional' = enlace válido para cotización formal sin precio público (servidores, firewall, algunos switches).",
      sprintf("Consulta automática al %s. Validar con cotización formal antes de compra.", FECHA_COTIZACION),
      "La hoja 'Cotización Consolidada' usa el menor precio válido con precio web; no sustituye cotización de fabricante.",
      "Fabricantes y mayoristas suelen requerir formulario o contacto comercial; usar columna Enlace catálogo.",
      "Precio solo si la página contiene términos del ítem (columnas Enlace validado, Motivo validación).",
      "Caché HTTP por URL, timeout 12 s, solo Bing (sin DDG), pausa reducida entre consultas."
    )
  )
}

limpiar_cache_http <- function() {
  rm(list = ls(envir = .cache_http), envir = .cache_http)
}

exportar_excel_multifuente <- function(multi, resumen_items, consolidada, resumen_cat, kpis, sup,
                                       catalogo_corp, enlaces_item, path_out,
                                       fuentes_relevantes = NULL) {
  matriz <- tryCatch(matriz_comparativa(multi), error = function(e) NULL)

  wb <- createWorkbook()

  addWorksheet(wb, "Catálogo Corporativo")
  writeData(wb, "Catálogo Corporativo", catalogo_corp)

  addWorksheet(wb, "Enlaces por Ítem")
  writeData(wb, "Enlaces por Ítem", enlaces_item)

  addWorksheet(wb, "Comparativo Multi-fuente")
  writeData(wb, "Comparativo Multi-fuente", multi |>
              transmute(
                ID = id, Categoría = categoria, Subcategoría = subcategoria,
                Elemento = elemento, Prioridad = prioridad, Cantidad = cantidad,
                Portal = portal, Canal = canal, Dominio = dominio, `Tipo portal` = tipo_portal,
                `Precio referencia COP` = precio_referencia,
                `Costo unitario COP` = costo_unitario_cop,
                `Subtotal COP` = subtotal_cop,
                `Enlace catálogo` = enlace_catalogo, Enlace = enlace,
                `Enlace validado` = enlace_validado,
                `Score relevancia` = score_relevancia,
                `Motivo validación` = motivo_validacion,
                Método = metodo, Aceptado = aceptado,
                Detalle = detalle, Estado = estado, `Fecha consulta` = fecha_consulta
              ))

  addWorksheet(wb, "Resumen por Ítem")
  writeData(wb, "Resumen por Ítem", resumen_items |>
              transmute(
                ID = id, Elemento = elemento, Categoría = categoria,
                Prioridad = prioridad, Cantidad = cantidad,
                `Precio referencia` = precio_referencia,
                `Precio mínimo` = precio_min, `Portal mínimo` = portal_min,
                `Precio máximo` = precio_max, `Portal máximo` = portal_max,
                `Precio mediano` = precio_mediano, `Precio promedio` = precio_promedio,
                `# Fuentes` = n_fuentes,
                `Subtotal mejor precio` = subtotal_mejor_precio,
                `Ahorro vs referencia %` = ahorro_vs_referencia_pct
              ))

  if (!is.null(matriz)) {
    addWorksheet(wb, "Matriz precios")
    writeData(wb, "Matriz precios", matriz)
  }

  cot_out <- consolidada |>
    transmute(
      ID = id, Categoría = categoria, Subcategoría = subcategoria,
      Elemento = elemento, Prioridad = prioridad, Cantidad = cantidad,
      `Costo unitario original` = costo_unitario_original,
      `Costo unitario COP` = costo_unitario_cop,
      `Subtotal COP` = subtotal_cop,
      `Portal recomendado` = portal_recomendado,
      `# Fuentes cotizadas` = n_fuentes_cotizadas,
      Especificaciones = especificaciones, Observación = observacion,
      `Enlace referencia` = enlace, `Estado precio` = estado_precio
    )

  addWorksheet(wb, "Cotización Consolidada")
  writeData(wb, "Cotización Consolidada", cot_out)

  addWorksheet(wb, "Resumen")
  writeData(wb, "Resumen", data.frame(
    Categoría = resumen_cat$categoria,
    `Total COP` = resumen_cat$total_cop,
    Participación = resumen_cat$participacion,
    check.names = FALSE
  ), startRow = 1)
  writeData(wb, "Resumen", kpis, startCol = 5, startRow = 1)

  addWorksheet(wb, "Supuestos y Fuentes")
  writeData(wb, "Supuestos y Fuentes", sup)

  if (!is.null(fuentes_relevantes) && nrow(fuentes_relevantes) > 0) {
    addWorksheet(wb, "Fuentes relevantes")
    writeData(wb, "Fuentes relevantes", fuentes_relevantes)
  }

  header_style <- createStyle(
    textDecoration = "bold", fgFill = "#D9E1F2",
    border = "Bottom", halign = "center", wrapText = TRUE
  )
  money_style <- createStyle(numFmt = "#,##0")
  pct_style <- createStyle(numFmt = "0.00%")

  hojas <- c(
    "Catálogo Corporativo", "Enlaces por Ítem", "Comparativo Multi-fuente",
    "Resumen por Ítem", "Cotización Consolidada", "Resumen", "Supuestos y Fuentes"
  )
  if (!is.null(fuentes_relevantes)) hojas <- c(hojas, "Fuentes relevantes")
  if (!is.null(matriz)) hojas <- c(hojas, "Matriz precios")

  for (ws in hojas) {
    addStyle(wb, ws, header_style, rows = 1, cols = 1:25, gridExpand = TRUE)
    setColWidths(wb, ws, cols = 1:20, widths = "auto")
  }

  saveWorkbook(wb, path_out, overwrite = TRUE)
  invisible(path_out)
}

main_multifuente <- function(dir_proyecto = NULL) {
  aplicar_args_cli()
  cfg <- inicializar_config_multifuente(dir_proyecto)
  limpiar_cache_http()
  archivo_entrada <- cfg$entrada
  archivo_salida <- cfg$salida

  if (!file.exists(archivo_entrada)) {
    stop("No se encuentra el archivo base: ", archivo_entrada, call. = FALSE)
  }

  message("=== Cotización MULTI-FUENTE Data Lab PUJ ===")
  message("Carpeta: ", cfg$dir)
  message("Leyendo: ", archivo_entrada)
  base <- leer_cotizacion_base(archivo_entrada)

  message("Consultando portales retail + corporativos. Puede tardar 30-60 min...")
  catalogo_corp <- catalogo_fuentes_corporativas()
  enlaces_item <- enlaces_corporativos_por_item(base)
  multi <- cotizar_multifuente(base)

  resumen_items <- resumen_por_item(multi)
  consolidada <- consolidar_mejor_precio(base, resumen_items)
  resumen_cat <- resumen_por_categoria(consolidada)
  kpis <- kpis_proyecto(consolidada)
  sup <- supuestos_multifuente()

  path_out <- exportar_excel_multifuente(
    multi, resumen_items, consolidada, resumen_cat, kpis, sup,
    catalogo_corp, enlaces_item, archivo_salida
  )

  n_inst <- sum(multi$estado == "Referencia institucional", na.rm = TRUE)

  n_cotizaciones <- sum(multi$aceptado, na.rm = TRUE)
  n_total <- nrow(multi)

  message("\nFilas comparativas: ", n_total)
  message("Cotizaciones exitosas: ", n_cotizaciones, " / ", n_total)
  message("Referencias institucionales (enlace sin precio): ", n_inst)
  message("Fuentes corporativas en catálogo: ", nrow(catalogo_corp))
  message("Ítems con al menos 1 fuente: ", nrow(resumen_items), " / ", nrow(base))
  message("Total consolidado (mejor precio): ",
          format(sum(consolidada$subtotal_cop), big.mark = ".", decimal.mark = ","), " COP")
  message("Archivo: ", path_out)

  invisible(list(
    comparativo = multi,
    resumen_items = resumen_items,
    consolidada = consolidada,
    archivo = path_out
  ))
}

aplicar_args_cli <- function() {
  args_cli <- commandArgs(trailingOnly = TRUE)
  if ("--test" %in% args_cli) assign("MAX_ITEMS_SCRAPE", 2L, envir = .GlobalEnv)
  if ("--sin-scraping" %in% args_cli) assign("USAR_SCRAPING", FALSE, envir = .GlobalEnv)
  invisible(args_cli)
}

main_cotizacion_relevantes <- function(dir_proyecto = NULL) {
  aplicar_args_cli()
  cfg <- inicializar_config_multifuente(dir_proyecto)
  limpiar_cache_http()
  fecha <- get("FECHA_COTIZACION", envir = .GlobalEnv)
  archivo_entrada <- cfg$entrada
  archivo_salida <- file.path(
    cfg$dir,
    sprintf("cotizacion_fuentes_relevantes_datalab_%s.xlsx", format(fecha, "%Y%m%d"))
  )

  assign("MODO_FUENTES", "relevantes", envir = .GlobalEnv)
  assign("DELAY_PORTAL", 1.0, envir = .GlobalEnv)

  if (!file.exists(archivo_entrada)) {
    stop("No se encuentra el archivo base: ", archivo_entrada, call. = FALSE)
  }

  message("=== Cotización FUENTES RELEVANTES — Data Lab PUJ ===")
  message("Retail: ", paste(IDS_RETAIL_RELEVANTE, collapse = ", "))
  message("Carpeta: ", cfg$dir)
  message("Leyendo: ", archivo_entrada)

  base <- leer_cotizacion_base(archivo_entrada)
  n_portales <- vapply(seq_len(nrow(base)), function(i) {
    length(portales_para_item(
      base$categoria[i], base$subcategoria[i], base$elemento[i]
    ))
  }, integer(1))
  message("Portales por ítem (promedio): ", round(mean(n_portales), 1))

  catalogo_corp <- catalogo_fuentes_corporativas()
  catalogo_rel <- catalogo_fuentes_relevantes()
  enlaces_item <- enlaces_corporativos_por_item(base)
  enlaces_rel <- bind_rows(lapply(seq_len(nrow(base)), function(i) {
    ports <- portales_para_item(
      base$categoria[i], base$subcategoria[i], base$elemento[i]
    )
    if (!length(ports)) return(NULL)
    bind_rows(lapply(seq_along(ports), function(j) {
      p <- ports[[j]]
      tibble(
        ID = base$id[i], Elemento = base$elemento[i],
        Portal = p$nombre, Canal = p$canal %||% "Retail",
        `Enlace cotización` = p$url_catalogo %||% NA_character_
      )
    }))
  }))

  multi <- cotizar_multifuente(base)
  resumen_items <- resumen_por_item(multi)
  consolidada <- consolidar_mejor_precio(base, resumen_items)
  resumen_cat <- resumen_por_categoria(consolidada)
  kpis <- kpis_proyecto(consolidada)

  sup <- supuestos_multifuente()
  sup <- bind_rows(sup, tibble(
    campo = "Modo fuentes relevantes",
    descripcion = paste(
      "Solo portales priorizados para compra institucional en Colombia.",
      "Retail:", paste(IDS_RETAIL_RELEVANTE, collapse = ", "),
      "| Corporativo por segmento según hoja 'Fuentes relevantes'."
    )
  ))

  path_out <- exportar_excel_multifuente(
    multi, resumen_items, consolidada, resumen_cat, kpis, sup,
    catalogo_corp, enlaces_rel, archivo_salida,
    fuentes_relevantes = catalogo_rel
  )

  assign("MODO_FUENTES", "completo", envir = .GlobalEnv)

  message("\nFilas comparativas: ", nrow(multi))
  message("Cotizaciones con precio: ", sum(multi$aceptado, na.rm = TRUE))
  message("Referencias institucionales: ",
          sum(multi$estado == "Referencia institucional", na.rm = TRUE))
  message("Ítems con precio web: ", nrow(resumen_items), " / ", nrow(base))
  message("Total consolidado: ",
          format(sum(consolidada$subtotal_cop), big.mark = ".", decimal.mark = ","), " COP")
  message("Archivo: ", path_out)

  invisible(list(
    comparativo = multi,
    resumen_items = resumen_items,
    consolidada = consolidada,
    archivo = path_out
  ))
}

main_solo_enlaces <- function(dir_proyecto = NULL) {
  cfg <- inicializar_config_multifuente(dir_proyecto)
  archivo_entrada <- cfg$entrada

  if (!file.exists(archivo_entrada)) {
    stop("No se encuentra el archivo base: ", archivo_entrada, call. = FALSE)
  }
  base <- leer_cotizacion_base(archivo_entrada)
  catalogo_corp <- catalogo_fuentes_corporativas()
  enlaces_item <- enlaces_corporativos_por_item(base)
  path_out <- file.path(
    cfg$dir,
    sprintf(
      "enlaces_corporativos_datalab_%s.xlsx",
      format(get("FECHA_COTIZACION", envir = .GlobalEnv), "%Y%m%d")
    )
  )
  wb <- createWorkbook()
  addWorksheet(wb, "Catálogo Corporativo")
  writeData(wb, "Catálogo Corporativo", catalogo_corp)
  addWorksheet(wb, "Enlaces por Ítem")
  writeData(wb, "Enlaces por Ítem", enlaces_item)
  saveWorkbook(wb, path_out, overwrite = TRUE)
  message("Enlaces exportados: ", path_out)
  message("Filas enlaces por ítem: ", nrow(enlaces_item))
  invisible(path_out)
}

if (sys.nframe() == 0) {
  args_cli <- aplicar_args_cli()
  if ("--solo-enlaces" %in% args_cli) {
    main_solo_enlaces()
  } else if ("--relevantes" %in% args_cli) {
    main_cotizacion_relevantes()
  } else {
    main_multifuente()
  }
}
