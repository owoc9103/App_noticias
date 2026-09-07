############################################################
# ANÁLISIS PRECIO - DEMANDA SIN TRANSFORMACIONES LOGARÍTMICAS
# Versión basada en `Codigo final.R` pero en niveles
# (quantity y unit_price sin logaritmos)
############################################################

# Librerías necesarias
library(dplyr)
library(ggplot2)
library(readr)
library(broom)
library(tidyr)

############################################################
# 1. CONFIGURACIÓN DE RUTAS
############################################################

input_path <- "C:/Users/owoc9/Documents/U Javeriana/Laboratorio Analítica/DGO/Precios y Canales/Version Ajustada_20260223/supermarket_sales_nuevo.csv"
output_path <- "C:/Users/owoc9/Documents/U Javeriana/Laboratorio Analítica/DGO/Precios y Canales/Version Ajustada_20260223/"

if (!dir.exists(output_path)) dir.create(output_path, recursive = TRUE)

############################################################
# 2. LECTURA Y VISTA PRELIMINAR
############################################################

data <- read.csv(input_path, sep = ",")

cat("\n--- Vista preliminar de los datos ---\n")
print(head(data))

############################################################
# 3. ANÁLISIS DESCRIPTIVO UNIVARIADO
############################################################

cat("\n--- Resumen general de variables numéricas ---\n")
print(summary(select(data, unit_price, quantity, total, cogs, gross_income, rating)))

cat("\n--- Distribución de variables categóricas ---\n")
categorical_vars <- c("branch", "city", "customer_type", "gender", "product_line", "payment")
for (var in categorical_vars) {
  cat(paste0("\nFrecuencias de ", var, ":\n"))
  print(table(data[[var]]))
}

# Histogramas
ggplot(data, aes(x = unit_price)) +
  geom_histogram(binwidth = 5, fill = "steelblue", color = "white") +
  labs(title = "Distribución del Precio Unitario", x = "Precio Unitario", y = "Frecuencia")

ggplot(data, aes(x = quantity)) +
  geom_histogram(binwidth = 1, fill = "orange", color = "red") +
  labs(title = "Distribución de Cantidad", x = "Cantidad", y = "Frecuencia")

############################################################
# 4. ANÁLISIS BIVARIADO: PRECIO vs CANTIDAD (EN NIVELES)
############################################################

cat("\n--- Correlación entre precio y cantidad (niveles) ---\n")
print(cor(data$unit_price, data$quantity))

ggplot(data, aes(x = unit_price, y = quantity)) +
  geom_point(alpha = 0.6) +
  geom_smooth(method = "lm", se = FALSE, color = "red") +
  labs(title = "Relación Precio - Cantidad (niveles)",
       x = "Precio Unitario",
       y = "Cantidad Vendida")

############################################################
# 5. MODELO PRECIO - DEMANDA POR CANAL (BRANCH) SIN LOGS
############################################################

cat("\n--- Estimación de relación precio-demanda por sucursal (sin logaritmos) ---\n")

# Modelo en niveles: quantity ~ unit_price
# Incluye R^2 y R^2 ajustado en la tabla de resultados
elasticity_models_nl <- data %>%
  group_by(branch) %>%
  do({
    m <- lm(quantity ~ unit_price, data = .)
    tidy_m <- tidy(m)
    glance_m <- glance(m)
    tidy_m$r.squared <- glance_m$r.squared
    tidy_m$adj.r.squared <- glance_m$adj.r.squared
    tidy_m
  }) %>%
  filter(term == "unit_price") %>%
  rename(
    coef_price = estimate,
    r_squared = r.squared,
    adj_r_squared = adj.r.squared
  )

cat("\n--- Resultados de coeficientes precio-cantidad por canal (niveles) ---\n")
print(elasticity_models_nl)

# Exportar resultados
write.csv(elasticity_models_nl,
          file.path(output_path, "coef_precio_por_branch_sin_log.csv"),
          row.names = FALSE)

############################################################
# 6. INTERPRETACIÓN AUTOMÁTICA BÁSICA (NIVELES)
############################################################

cat("\n--- Interpretación básica (niveles) ---\n")
cat("Coeficiente precio (unit_price): variación esperada en la cantidad ante\n")
cat("un aumento de 1 unidad monetaria en el precio, manteniendo lo demás constante.\n\n")

for (i in seq_len(nrow(elasticity_models_nl))) {
  b <- elasticity_models_nl$branch[i]
  e <- elasticity_models_nl$coef_price[i]
  msg <- ifelse(e < 0,
                "Relación negativa: a mayor precio, menor cantidad (ley de la demanda).",
                "Relación no negativa o inusual: a mayor precio, la cantidad no disminuye.")
  cat(paste0("Sucursal ", b, ": Coeficiente precio = ", round(e, 4), " → ", msg, "\n"))
}

cat("\n--- Proceso principal (por branch) finalizado. Resultados exportados. ---\n")

############################################################
# 7. COMPARACIÓN POR SEGMENTOS (SIN LOGS)
############################################################

cat("\n--- Comparación coeficientes precio-cantidad por canal y tipo de cliente ---\n")
elasticity_branch_customer_nl <- data %>%
  group_by(branch, customer_type) %>%
  do({
    m <- lm(quantity ~ unit_price, data = .)
    tidy_m <- tidy(m)
    glance_m <- glance(m)
    tidy_m$r.squared <- glance_m$r.squared
    tidy_m$adj.r.squared <- glance_m$adj.r.squared
    tidy_m
  }) %>%
  filter(term == "unit_price") %>%
  rename(
    coef_price = estimate,
    r_squared = r.squared,
    adj_r_squared = adj.r.squared
  )
print(elasticity_branch_customer_nl)

cat("\n--- Comparación coeficientes precio-cantidad por canal y ciudad ---\n")
elasticity_branch_city_nl <- data %>%
  group_by(branch, city) %>%
  do({
    m <- lm(quantity ~ unit_price, data = .)
    tidy_m <- tidy(m)
    glance_m <- glance(m)
    tidy_m$r.squared <- glance_m$r.squared
    tidy_m$adj.r.squared <- glance_m$adj.r.squared
    tidy_m
  }) %>%
  filter(term == "unit_price") %>%
  rename(
    coef_price = estimate,
    r_squared = r.squared,
    adj_r_squared = adj.r.squared
  )
print(elasticity_branch_city_nl)

cat("\n--- Comparación coeficientes precio-cantidad por canal y género ---\n")
elasticity_branch_gender_nl <- data %>%
  group_by(branch, gender) %>%
  do({
    m <- lm(quantity ~ unit_price, data = .)
    tidy_m <- tidy(m)
    glance_m <- glance(m)
    tidy_m$r.squared <- glance_m$r.squared
    tidy_m$adj.r.squared <- glance_m$adj.r.squared
    tidy_m
  }) %>%
  filter(term == "unit_price") %>%
  rename(
    coef_price = estimate,
    r_squared = r.squared,
    adj_r_squared = adj.r.squared
  )
print(elasticity_branch_gender_nl)

############################################################
# 8. VISUALIZACIÓN DE RESULTADOS (SIN LOGS)
############################################################

# Relación quantity vs unit_price con línea de regresión
ggplot(data, aes(x = unit_price, y = quantity)) +
  geom_point(alpha = 0.4) +
  geom_smooth(method = "lm", se = TRUE) +
  labs(title = "Relación entre Quantity y Unit Price (niveles)",
       x = "Unit Price",
       y = "Quantity") +
  theme_minimal()

# Comparación de coeficientes por sucursal
ggplot(elasticity_models_nl, aes(x = branch, y = coef_price)) +
  geom_col() +
  labs(title = "Coeficiente precio-cantidad por sucursal (niveles)",
       x = "Sucursal",
       y = "Coeficiente de unit_price en quantity") +
  theme_minimal()

############################################################
# 9. SIMULACIÓN CAMBIO DE PRECIO (10%) EN NIVELES
############################################################

cat("\n--- Simulación: impacto de un aumento del 10% en el precio (niveles) ---\n")

val_promedio_nl <- data %>%
  group_by(branch) %>%
  summarise(
    average_quantity = mean(quantity),
    average_price = mean(unit_price),
    .groups = "drop"
  )

price_change <- 0.10

simulacion_0.10_nl <- elasticity_models_nl %>%
  left_join(val_promedio_nl, by = "branch") %>%
  mutate(
    quantity_change_abs = coef_price * (average_price * price_change),
    new_quantity = average_quantity + quantity_change_abs,
    new_price = average_price * (1 + price_change),
    revenue_initial = average_price * average_quantity,
    revenue_new = new_price * new_quantity,
    revenue_change = revenue_new - revenue_initial
  )

ggplot(simulacion_0.10_nl, aes(x = reorder(branch, revenue_initial), y = revenue_initial)) +
  geom_col(fill = "blue") +
  labs(title = "Ventas por sucursal antes del aumento del 10% (niveles)",
       x = "Sucursal",
       y = "Ventas") +
  theme_minimal()

ggplot(simulacion_0.10_nl, aes(x = reorder(branch, revenue_new), y = revenue_new)) +
  geom_col(fill = "red") +
  labs(title = "Ventas por sucursal después del aumento del 10% (niveles)",
       x = "Sucursal",
       y = "Ventas") +
  theme_minimal()

print(simulacion_0.10_nl)

############################################################
# 10. DIFERENCIAS POR LÍNEA DE PRODUCTO (SIN LOGS)
############################################################

cat("\n--- Coeficientes precio-cantidad por línea de producto (niveles) ---\n")

elasticity_products_nl <- data %>%
  group_by(product_line) %>%
  do({
    m <- lm(quantity ~ unit_price, data = .)
    tidy_m <- broom::tidy(m)
    glance_m <- broom::glance(m)
    tidy_m$r.squared <- glance_m$r.squared
    tidy_m$adj.r.squared <- glance_m$adj.r.squared
    tidy_m
  }) %>%
  filter(term == "unit_price") %>%
  rename(
    coef_price = estimate,
    r_squared = r.squared,
    adj_r_squared = adj.r.squared
  )

print(elasticity_products_nl)

cat("\n--- Interpretación por productos (niveles) ---\n")
for (i in seq_len(nrow(elasticity_products_nl))) {
  b <- elasticity_products_nl$product_line[i]
  e <- elasticity_products_nl$coef_price[i]
  msg <- ifelse(e < 0,
                "Relación negativa precio-cantidad (comportamiento esperable de demanda).",
                "Relación no negativa o inusual (posible bien de lujo o datos atípicos).")
  cat(paste0("Línea de producto ", b, ": Coeficiente precio = ",
             round(e, 4), " → ", msg, "\n"))
}

############################################################
# 11. EJEMPLO EXTRA: DIFERENCIAS ENTRE TIPOS DE CLIENTE
############################################################

cat("\n--- Diferencias en cantidad y ventas promedio por tipo de cliente ---\n")

data %>%
  group_by(customer_type) %>%
  summarise(
    avg_quantity = mean(quantity),
    avg_sales = mean(total),
    .groups = "drop"
  )

ggplot(data, aes(x = customer_type, y = quantity)) +
  geom_boxplot() +
  theme_minimal() +
  labs(title = "Distribución de Cantidad por Tipo de Cliente",
       x = "Tipo de Cliente",
       y = "Cantidad")

cat("\n--- Proceso sin logaritmos finalizado. ---\n")

