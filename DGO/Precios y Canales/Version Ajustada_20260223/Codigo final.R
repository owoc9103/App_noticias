# ------------------------------------------------------------
# ANÁLISIS DESCRIPTIVO Y ESTIMACIÓN DE ELASTICIDAD PRECIO-DEMANDA
# ------------------------------------------------------------

# Librerías necesarias
library(dplyr)
library(ggplot2)
library(readr)
library(broom)
library(tidyr)


# ------------------------------------------------------------
# 1. CONFIGURACIÓN DE RUTAS
# ------------------------------------------------------------
input_path <- "C:/Users/owoc9/Documents/U Javeriana/Laboratorio Analítica/DGO/Precios y Canales/Version Ajustada_20260223/supermarket_sales_nuevo.csv"
output_path <- "C:/Users/owoc9/Documents/U Javeriana/Laboratorio Analítica/DGO/Precios y Canales/Version Ajustada_20260223/"

if(!dir.exists(output_path)) dir.create(output_path, recursive = TRUE)

# ------------------------------------------------------------
# 2. LECTURA Y RENOMBRADO DE VARIABLES
# ------------------------------------------------------------
data <- read.csv(input_path, sep = ",")

# Mostrar primeras filas
cat("\n--- Vista preliminar de los datos ---\n")
print(head(data))

# ------------------------------------------------------------
# 3. ANÁLISIS DESCRIPTIVO UNIVARIADO
# ------------------------------------------------------------

cat("\n--- Resumen general de variables numéricas ---\n")
print(summary(select(data, unit_price, quantity, total, cogs, gross_income, rating)))

cat("\n--- Distribución de variables categóricas ---\n")
categorical_vars <- c("branch", "city", "customer_type", "gender", "product_line", "payment")
for (var in categorical_vars) {
  cat(paste0("\nFrecuencias de ", var, ":\n"))
  print(table(data[[var]]))
}

# Gráficos univariados
ggplot(data, aes(x = unit_price)) + 
  geom_histogram(binwidth = 5, fill = "steelblue", color = "white") +
  labs(title = "Distribución del Precio Unitario", x = "Precio Unitario", y = "Frecuencia")

ggplot(data, aes(x = quantity)) + 
  geom_histogram(binwidth = 1, fill = "orange", color = "red") +
  labs(title = "Distribución de Cantidad", x = "Cantidad", y = "Frecuencia")

# ------------------------------------------------------------
# 4. ANÁLISIS BIVARIADO: PRECIO vs CANTIDAD
# ------------------------------------------------------------

cat("\n--- Correlación entre precio y cantidad ---\n")
print(cor(data$unit_price, data$quantity))

ggplot(data, aes(x = quantity, y = unit_price)) +
  geom_point(alpha = 0.6) +
  #geom_smooth(method = "lm", se = FALSE, color = "red") +
  labs(title = "Relación Precio - Cantidad", x = "Precio Unitario", y = "Cantidad Vendida")

# ------------------------------------------------------------
# 5. MODELO DE ELASTICIDAD PRECIO - DEMANDA POR CANAL (BRANCH)
# ------------------------------------------------------------

cat("\n--- Estimación de elasticidad precio-demanda por sucursal ---\n")




# Transformaciones logarítmicas
data <- data %>%
  mutate(
    log_price = log(unit_price),
    log_quantity = log(quantity)
  )

# Regla de decisión para clasificar la elasticidad (se imprimirá después de cada resumen)
regla_decision_elasticidad <- "
--- Regla de decisión (según |E_p|) ---
|E_p| = 0           → Perfectamente inelástica
0 < |E_p| < 1       → Inelástica
|E_p| = 1           → Unitaria
|E_p| > 1           → Elástica
E_p ≥ 0             → No negativa o inusual
"

# Estimación por canal (branch)
elasticity_models <- data %>%
  group_by(branch) %>%
  do({
    m <- lm(log_quantity ~ log_price, data = .)
    tidy_m <- tidy(m)
    glance_m <- glance(m)
    tidy_m$r.squared <- glance_m$r.squared
    tidy_m
  }) %>%
  filter(term == "log_price") %>%
  rename(
    elasticity = estimate,
    r_squared = r.squared
  ) %>%
  mutate(
    tipo_elasticidad = dplyr::case_when(
      elasticity >= 0 ~ "No negativa o inusual",
      abs(elasticity) == 0 ~ "Perfectamente inelástica",
      abs(elasticity) > 0 & abs(elasticity) < 1 ~ "Inelástica",
      abs(elasticity) == 1 ~ "Unitaria",
      TRUE ~ "Elástica"
    )
  )

cat("\n--- Resultados de elasticidad por canal ---\n")
print(elasticity_models)




# Exportar resultados
write.csv(elasticity_models, file.path(output_path, "elasticidad_por_branch.csv"), row.names = FALSE)

# ------------------------------------------------------------
# 6. INTERPRETACIÓN AUTOMÁTICA BÁSICA
# ------------------------------------------------------------
cat("\n--- Interpretación básica ---\n")
for (i in 1:nrow(elasticity_models)) {
  b <- elasticity_models$branch[i]
  e <- elasticity_models$elasticity[i]
  abs_e <- abs(e)
  msg <- ifelse(e >= 0,
                "Relación no negativa o inusual: precio y cantidad se mueven en la misma dirección.",
                ifelse(abs_e == 0,
                       "Demanda perfectamente inelástica: la cantidad no varía ante cambios en el precio.",
                       ifelse(abs_e > 0 & abs_e < 1,
                              "Demanda inelástica: la cantidad varía menos que proporcional al cambio en el precio.",
                              ifelse(abs_e == 1,
                                     "Demanda unitaria: la cantidad varía en la misma proporción que el precio.",
                                     "Demanda elástica: la cantidad varía más que proporcional al cambio en el precio."
                              ))))
  cat(paste0("Sucursal ", b, ": Elasticidad = ", round(e, 3), " → ", msg, "\n"))
}

cat("\n--- Proceso finalizado. Resultados exportados y mostrados en consola. ---\n")


# ------------------------------------------------------------
# 7. Comparación de elasticidades entre canales
# ------------------------------------------------------------

#Comparación de elasticidades de canales segmentados por fidelidad 
elasticity_branch_customer <- data %>%
  group_by(branch, customer_type) %>%
  do({
    m <- lm(log_quantity ~ log_price, data = .)
    tidy_m <- tidy(m)
    glance_m <- glance(m)
    tidy_m$r.squared <- glance_m$r.squared
    tidy_m
  }) %>%
  filter(term == "log_price") %>%
  rename(
    elasticity = estimate,
    r_squared = r.squared
  ) %>%
  mutate(
    tipo_elasticidad = dplyr::case_when(
      elasticity >= 0 ~ "No negativa o inusual",
      abs(elasticity) == 0 ~ "Perfectamente inelástica",
      abs(elasticity) > 0 & abs(elasticity) < 1 ~ "Inelástica",
      abs(elasticity) == 1 ~ "Unitaria",
      TRUE ~ "Elástica"
    )
  )
cat("\n--- Resultados de elasticidad por canal segmentados por tipo de cliente  ---\n")
print(elasticity_branch_customer)
cat(regla_decision_elasticidad)

#Comparación de elasticidades de canales segmentados por ciudad
elasticity_branch_city <- data %>%
  group_by(branch, city) %>%
  do({
    m <- lm(log_quantity ~ log_price, data = .)
    tidy_m <- tidy(m)
    glance_m <- glance(m)
    tidy_m$r.squared <- glance_m$r.squared
    tidy_m
  }) %>%
  filter(term == "log_price") %>%
  rename(
    elasticity = estimate,
    r_squared = r.squared
  ) %>%
  mutate(
    tipo_elasticidad = dplyr::case_when(
      elasticity >= 0 ~ "No negativa o inusual",
      abs(elasticity) == 0 ~ "Perfectamente inelástica",
      abs(elasticity) > 0 & abs(elasticity) < 1 ~ "Inelástica",
      abs(elasticity) == 1 ~ "Unitaria",
      TRUE ~ "Elástica"
    )
  )
cat("\n--- Resultados de elasticidad por canal segmentados por ciudad  ---\n")
print(elasticity_branch_city)
cat(regla_decision_elasticidad)

#Comparación de elasticidades de canales segmentados por genero
elasticity_branch_gender <- data %>%
  group_by(branch, gender) %>%
  do({
    m <- lm(log_quantity ~ log_price, data = .)
    tidy_m <- tidy(m)
    glance_m <- glance(m)
    tidy_m$r.squared <- glance_m$r.squared
    tidy_m
  }) %>%
  filter(term == "log_price") %>%
  rename(
    elasticity = estimate,
    r_squared = r.squared
  ) %>%
  mutate(
    tipo_elasticidad = dplyr::case_when(
      elasticity >= 0 ~ "No negativa o inusual",
      abs(elasticity) == 0 ~ "Perfectamente inelástica",
      abs(elasticity) > 0 & abs(elasticity) < 1 ~ "Inelástica",
      abs(elasticity) == 1 ~ "Unitaria",
      TRUE ~ "Elástica"
    )
  )
cat("\n--- Resultados de elasticidad por canal segmentados por genero  ---\n")
print(elasticity_branch_gender)
cat(regla_decision_elasticidad)

# ------------------------------------------------------------
# 8. Visualización de resultados 
# ---------------------------

#Grafico de las relaciones log(Quantity) y log(Unit.price) con líneas de tendencia ajustadas.
ggplot(data, aes(x = log_price, y = log_quantity)) +
  geom_point(alpha = 0.4) +
  geom_smooth(method = "lm", se = TRUE) +
  labs(title = "Relación entre log(Quantity) y log(Price)", x = "log(Unit Price)", y = "log(Quantity)") +
  theme_minimal()

#Comparación de elasticidades por sucursal
ggplot(elasticity_models, aes(x = branch, y = elasticity)) +
  geom_col() +
  coord_cartesian(ylim = c(-2.5, 0)) +
  geom_hline(yintercept = -1, linetype = "dashed", color = "red") +
  labs(title = "Comparación elasticidad por sucursal",
       x = "Sucursal",
       y = "Elasticidad Precio de la Demanda") +
  theme_minimal()

# ------------------------------------------------------------
# 9. Cambio del 10% en el precio impacte en las ventas de cada sucursal. 
# ---------------------------
val_promedio <-data %>%
    group_by(branch) %>%
    summarise(avgerage_quantity = mean(quantity), average_price = mean(unit_price))

simulacion_0.10 <- elasticity_models %>%
  left_join(val_promedio, by = "branch") %>% #Une la información de avg_values a elasticity_models usando la variable branch.
  mutate(price_change = 0.10, quantity_change_0.10 = elasticity * price_change,
         new_quantity = avgerage_quantity *(1 + quantity_change_0.10),
         new_price = average_price * (1 + price_change),
         revenue_initial = average_price * new_quantity,
         revenue_new = new_price * new_quantity,
         revenue_change = revenue_new - revenue_initial
  )

ggplot(simulacion_0.10, aes(x = reorder(branch, revenue_initial), y = revenue_initial)) +
  geom_col(fill= "blue") + 
  labs(title= "ventas por sucursal antes del aumento del 10%", x = "sucursal", y = "ventas")
theme_minimal()

ggplot(simulacion_0.10, aes(x = reorder(branch, revenue_new),y = revenue_new)) +
  geom_col(fill="red") +
  labs(title = "Ventas por Sucursal después del aumento del 10%",x = "Sucursal",y = "Ventas") +
  theme_minimal()
print(simulacion_0.10)
# ------------------------------------------------------------
# 10. Identificación del producto inelastico
# ------------------------------------------------------------


elasticity_products <- data %>%
  group_by(product_line) %>%
  do({
    m <- lm(log_quantity ~ log_price, data = .)
    tidy_m <- broom::tidy(m)
    glance_m <- broom::glance(m)
    tidy_m$r.squared <- glance_m$r.squared
    tidy_m
  }) %>%
  filter(term == "log_price") %>%
  rename(
    elasticity = estimate,
    r_squared = r.squared
  ) %>%
  mutate(
    tipo_elasticidad = dplyr::case_when(
      elasticity >= 0 ~ "No negativa o inusual",
      abs(elasticity) == 0 ~ "Perfectamente inelástica",
      abs(elasticity) > 0 & abs(elasticity) < 1 ~ "Inelástica",
      abs(elasticity) == 1 ~ "Unitaria",
      TRUE ~ "Elástica"
    )
  )

cat("\n--- Resultados de elasticidad por canal ---\n")
print(elasticity_products)
cat(regla_decision_elasticidad)


cat("\n--- Interpretación por productos ---\n")
for (i in 1:nrow(elasticity_products)) {
  b <- elasticity_products$product_line[i]
  e <- elasticity_products$elasticity[i]
  abs_e <- abs(e)
  msg <- ifelse(e >= 0,
                "Relación no negativa o inusual: precio y cantidad se mueven en la misma dirección.",
                ifelse(abs_e == 0,
                       "Demanda perfectamente inelástica: la cantidad no varía ante cambios en el precio.",
                       ifelse(abs_e > 0 & abs_e < 1,
                              "Demanda inelástica: la cantidad varía menos que proporcional al cambio en el precio.",
                              ifelse(abs_e == 1,
                                     "Demanda unitaria: la cantidad varía en la misma proporción que el precio.",
                                     "Demanda elástica: la cantidad varía más que proporcional al cambio en el precio."
                              ))))
  cat(paste0("Linea de producto ", b, ": Elasticidad = ", round(e, 3), " → ", msg, "\n"))
}

elasticity_products <- elasticity_products %>% #valor absoluto 
  mutate(abs_elasticity = abs(elasticity))
elasticity_products %>%
  arrange(abs_elasticity) %>% #Ordenar de mayor a menor 
  slice(1)

cat("efectivamente la linea de Home and lifestyle es la mas inelastica")

# ------------------------------------------------------------
# Comentario interpretativo detallado por línea de producto
# (ejemplo basado en resultados típicos del ejercicio)
# ------------------------------------------------------------
#
# Electronic accessories
# Elasticidad = −1.5
# Un aumento del 1% en el precio reduce la cantidad demandada en 1.5%.
# |E| > 1 → Demanda elástica.
# Alta sensibilidad al precio.
# Subir precios reduce ingresos si se mantiene la estructura actual.
#
#⃣ Fashion accessories
# Elasticidad = −2.0
# Un aumento del 1% en el precio reduce la cantidad en 2%.
# Muy elástica.
# Es la categoría más sensible al precio.
# Riesgo alto de pérdida de volumen ante aumentos.
#
# Food and beverages
# Elasticidad = −0.30
# Un aumento del 1% en el precio reduce la cantidad en solo 0.3%.
# |E| < 1 → Inelástica.
# Productos con demanda relativamente estable.
# Permite mayor margen para incrementos de precio.
#
# Health and beauty
# Elasticidad = −0.50
# Un aumento del 1% en el precio reduce la cantidad en 0.5%.
# Inelástica.
# Sensibilidad moderada pero menor que proporcional.
#
# Home and lifestyle
# Elasticidad = −0.10
# Un aumento del 1% en el precio reduce la cantidad en 0.1%.
# Muy inelástica.
# El precio tiene bajo impacto en el volumen.
#
# Sports and travel
# Elasticidad = −1.2
# Un aumento del 1% en el precio reduce la cantidad en 1.2%.
# Elástica.
# Sensible al precio, aunque menos que moda.

# ------------------------------------------------------------
# 11. Ejemplo extra
# ¿Existe una diferencia significativa en la cantidad comprada entre clientes Member y Normal?
# ------------------------------------------------------------

data %>%
  
  group_by(customer_type) %>%
  
  summarise(avg_quantity = mean(quantity),
            
            avg_sales = mean(total)
            
  )


ggplot(data, aes(x = customer_type, y = quantity)) +
  
  geom_boxplot() +
  
  theme_minimal() +
  
  labs(title = "Distribución de Cantidad por Tipo de Cliente",
       
       x = "Tipo de Cliente",
       
       y = "Cantidad")




# ------------------------------------------------------------
# 12. Ejercicio 1:
# ¿Calcule las elasticidades de por costumer_type y branch, interprete los resultados?
# ------------------------------------------------------------

elasticity_products <- data %>%
  group_by(customer_type, branch) %>%
  do({
    m <- lm(log_quantity ~ log_price, data = .)
    tidy_m <- broom::tidy(m)
    glance_m <- broom::glance(m)
    tidy_m$r.squared <- glance_m$r.squared
    tidy_m
  }) %>%
  filter(term == "log_price") %>%
  rename(
    elasticity = estimate,
    r_squared = r.squared
  ) %>%
  mutate(
    tipo_elasticidad = dplyr::case_when(
      elasticity >= 0 ~ "No negativa o inusual",
      abs(elasticity) == 0 ~ "Perfectamente inelástica",
      abs(elasticity) > 0 & abs(elasticity) < 1 ~ "Inelástica",
      abs(elasticity) == 1 ~ "Unitaria",
      TRUE ~ "Elástica"
    )
  )

cat("\n--- Resultados de elasticidad por canal ---\n")
print(elasticity_products)
cat(regla_decision_elasticidad)


cat("\n--- Interpretación por productos ---\n")
for (i in 1:nrow(elasticity_products)) {
  b <- elasticity_products$product_line[i]
  e <- elasticity_products$elasticity[i]
  abs_e <- abs(e)
  msg <- ifelse(e >= 0,
                "Relación no negativa o inusual: precio y cantidad se mueven en la misma dirección.",
                ifelse(abs_e == 0,
                       "Demanda perfectamente inelástica: la cantidad no varía ante cambios en el precio.",
                       ifelse(abs_e > 0 & abs_e < 1,
                              "Demanda inelástica: la cantidad varía menos que proporcional al cambio en el precio.",
                              ifelse(abs_e == 1,
                                     "Demanda unitaria: la cantidad varía en la misma proporción que el precio.",
                                     "Demanda elástica: la cantidad varía más que proporcional al cambio en el precio."
                              ))))
  cat(paste0("Linea de producto ", b, ": Elasticidad = ", round(e, 3), " → ", msg, "\n"))
}

elasticity_products <- elasticity_products %>% #valor absoluto 
  mutate(abs_elasticity = abs(elasticity))
elasticity_products %>%
  arrange(abs_elasticity) %>% #Ordenar de mayor a menor 
  slice(1)

cat("efectivamente la linea de Home and lifestyle es la mas inelastica")
# ------------------------------------------------------------
# 13. Ejercicio 2:
# ¿Calcule las elasticidades de por branch y el gender, interprete los resultados?
# ------------------------------------------------------------
elasticity_products <- data %>%
  group_by(branch, gender) %>%
  do({
    m <- lm(log_quantity ~ log_price, data = .)
    tidy_m <- broom::tidy(m)
    glance_m <- broom::glance(m)
    tidy_m$r.squared <- glance_m$r.squared
    tidy_m
  }) %>%
  filter(term == "log_price") %>%
  rename(
    elasticity = estimate,
    r_squared = r.squared
  ) %>%
  mutate(
    tipo_elasticidad = dplyr::case_when(
      elasticity >= 0 ~ "No negativa o inusual",
      abs(elasticity) == 0 ~ "Perfectamente inelástica",
      abs(elasticity) > 0 & abs(elasticity) < 1 ~ "Inelástica",
      abs(elasticity) == 1 ~ "Unitaria",
      TRUE ~ "Elástica"
    )
  )

cat("\n--- Resultados de elasticidad por canal ---\n")
print(elasticity_products)
cat(regla_decision_elasticidad)


cat("\n--- Interpretación por productos ---\n")
for (i in 1:nrow(elasticity_products)) {
  b <- elasticity_products$product_line[i]
  e <- elasticity_products$elasticity[i]
  abs_e <- abs(e)
  msg <- ifelse(e >= 0,
                "Relación no negativa o inusual: precio y cantidad se mueven en la misma dirección.",
                ifelse(abs_e == 0,
                       "Demanda perfectamente inelástica: la cantidad no varía ante cambios en el precio.",
                       ifelse(abs_e > 0 & abs_e < 1,
                              "Demanda inelástica: la cantidad varía menos que proporcional al cambio en el precio.",
                              ifelse(abs_e == 1,
                                     "Demanda unitaria: la cantidad varía en la misma proporción que el precio.",
                                     "Demanda elástica: la cantidad varía más que proporcional al cambio en el precio."
                              ))))
  cat(paste0("Linea de producto ", b, ": Elasticidad = ", round(e, 3), " → ", msg, "\n"))
}

elasticity_products <- elasticity_products %>% #valor absoluto 
  mutate(abs_elasticity = abs(elasticity))
elasticity_products %>%
  arrange(abs_elasticity) %>% #Ordenar de mayor a menor 
  slice(1)

cat("efectivamente la linea de Home and lifestyle es la mas inelastica")
# ------------------------------------------------------------
# 14. Ejercicio 3:
# ¿Calcule las elasticidades de por produc_line y el método de pago, interprete los resultados?
# ------------------------------------------------------------
