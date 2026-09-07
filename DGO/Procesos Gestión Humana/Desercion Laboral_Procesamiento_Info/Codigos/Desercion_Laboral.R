# ============================================================
# 1. Cargar librerías
# ============================================================
library(dplyr)
library(ggplot2)
library(readr)

# ============================================================
# 2. Cargar información
# ============================================================
df <- read.csv("C:/Users/owoc9/Documents/U Javeriana/Laboratorio Analítica/DGO/Procesos Gestión Humana/Desercion Laboral_Procesamiento_Info/Insumos/attrition_data.csv",sep=",")
df$STATUS <- as.factor(df$STATUS)

# ============================================================
# 3. Análisis univariado POR STATUS (variables ampliadas)
# ============================================================

# Distribución general del STATUS
table(df$STATUS)
prop.table(table(df$STATUS))

# ---- Edad ----
df %>% group_by(STATUS) %>%
  summarise(
    media_edad = mean(AGE, na.rm = TRUE),
    mediana_edad = median(AGE, na.rm = TRUE),
    sd_edad = sd(AGE, na.rm = TRUE)
  )

# ---- Salario Anual ----
df %>% group_by(STATUS) %>%
  summarise(
    media_salario = mean(ANNUAL_RATE, na.rm = TRUE),
    mediana_salario = median(ANNUAL_RATE, na.rm = TRUE)
  )

# ---- Salario por hora ----
df %>% group_by(STATUS) %>%
  summarise(
    media_hrly = mean(HRLY_RATE, na.rm = TRUE),
    mediana_hrly = median(HRLY_RATE, na.rm = TRUE)
  )

# ---- Satisfacción laboral ----
df %>% group_by(STATUS, JOB_SATISFACTION) %>%
  summarise(n = n()) %>% mutate(prop = n / sum(n))

# ---- Estado civil ----
df %>% group_by(STATUS, MARITAL_STATUS) %>%
  summarise(n = n()) %>% mutate(prop = n / sum(n))

# ---- Código de trabajo / rol ----
df %>% group_by(STATUS, JOBCODE) %>%
  summarise(n = n()) %>% mutate(prop = n / sum(n))

# ---- Grupo de trabajo ----
df %>% group_by(STATUS, JOB_GROUP) %>%
  summarise(n = n()) %>% mutate(prop = n / sum(n))

# ---- Desempeño (Performance Rating) ----
df %>% group_by(STATUS, PERFORMANCE_RATING) %>%
  summarise(n = n()) %>% mutate(prop = n / sum(n))

# ---- Viajes requeridos ----
df %>% group_by(STATUS, TRAVELLED_REQUIRED) %>%
  summarise(n = n()) %>% mutate(prop = n / sum(n))

# ---- Personas con discapacidad ----
df %>% group_by(STATUS, DISABLED_EMP) %>%
  summarise(n = n()) %>% mutate(prop = n / sum(n))

df %>% group_by(STATUS, DISABLED_VET) %>%
  summarise(n = n()) %>% mutate(prop = n / sum(n))

# ---- Mes de contratación ----
df %>% group_by(STATUS, HIRE_MONTH) %>%
  summarise(n = n()) %>% mutate(prop = n / sum(n))

# ---- ¿Fue recontratado? ----
df %>% group_by(STATUS, REHIRE) %>%
  summarise(n = n()) %>% mutate(prop = n / sum(n))

# ---- ¿Primer empleo? ----
df %>% group_by(STATUS, IS_FIRST_JOB) %>%
  summarise(n = n()) %>% mutate(prop = n / sum(n))

# ---- Cambios de equipo ----
df %>% group_by(STATUS) %>%
  summarise(
    promedio_cambios = mean(NUMBER_OF_TEAM_CHANGED, na.rm = TRUE),
    mediana_cambios = median(NUMBER_OF_TEAM_CHANGED, na.rm = TRUE)
  )

# ---- Historicos PREVYR_1 a 5 ----
df %>% group_by(STATUS) %>%
  summarise(
    prev1 = mean(PREVYR_1, na.rm = TRUE),
    prev2 = mean(PREVYR_2, na.rm = TRUE),
    prev3 = mean(PREVYR_3, na.rm = TRUE),
    prev4 = mean(PREVYR_4, na.rm = TRUE),
    prev5 = mean(PREVYR_5, na.rm = TRUE)
  )

# ============================================================
# 4. Gráficos UNIVARIADOS
# ============================================================

ggplot(df, aes(x = AGE, fill = STATUS)) +
  geom_histogram(alpha = 0.5, bins = 20, position = "identity") +
  labs(title = "Distribución de la Edad por Estado Laboral")

ggplot(df, aes(x = STATUS, y = ANNUAL_RATE, fill = STATUS)) +
  geom_boxplot() + labs(title = "Distribución del Salario Anual")

ggplot(df, aes(x = JOB_SATISFACTION, fill = STATUS)) +
  geom_bar(position = "dodge") +
  labs(title = "Satisfacción Laboral por Estado Laboral")

ggplot(df, aes(x = MARITAL_STATUS, fill = STATUS)) +
  geom_bar(position = "dodge") +
  labs(title = "Estado Civil por Estado Laboral")

ggplot(df, aes(x = JOB_GROUP, fill = STATUS)) +
  geom_bar(position = "dodge") +
  labs(title = "Distribución por Grupo de Trabajo")

ggplot(df, aes(x = TRAVELLED_REQUIRED, fill = STATUS)) +
  geom_bar(position = "dodge") +
  labs(title = "Viajes Requeridos por Estado Laboral")

ggplot(df, aes(x = PERFORMANCE_RATING, fill = STATUS)) +
  geom_bar(position = "dodge") +
  labs(title = "Evaluación de Desempeño por Estado Laboral")

# ============================================================
# 5. Gráficos BIVARIADOS (ampliados)
# ============================================================

# Edad vs Salario
ggplot(df, aes(x = AGE, y = ANNUAL_RATE, color = STATUS)) +
  geom_point(alpha = 0.6) +
  labs(title = "Edad vs Salario por Estado Laboral")

# Salario vs Satisfacción laboral
ggplot(df, aes(x = JOB_SATISFACTION, y = ANNUAL_RATE, color = STATUS)) +
  geom_jitter(width = 0.2, alpha = 0.6) +
  labs(title = "Salario según Satisfacción Laboral por Estado Laboral")

# Cambios de equipo vs satisfacción
ggplot(df, aes(x = NUMBER_OF_TEAM_CHANGED, y = JOB_SATISFACTION, color = STATUS)) +
  geom_point(alpha = 0.6) +
  labs(title = "Cambios de Equipo vs Satisfacción Laboral por Estado Laboral")

# PREVYR histórico vs Status
ggplot(df, aes(x = PREVYR_1, y = PREVYR_5, color = STATUS)) +
  geom_point(alpha = 0.6) +
  labs(title = "Desempeño Histórico vs Estado Laboral")

# ============================================================
# 6. Perfil descriptivo consolidado por STATUS
# ============================================================

df %>%
  group_by(STATUS) %>%
  summarise(
    edad_prom = mean(AGE, na.rm = TRUE),
    salario_prom = mean(ANNUAL_RATE, na.rm = TRUE),
    satsf_prom = mean(JOB_SATISFACTION, na.rm = TRUE),
    viajes_prop = mean(TRAVELLED_REQUIRED == "YES", na.rm = TRUE),
    primer_empleo_prop = mean(IS_FIRST_JOB == "YES", na.rm = TRUE),
    recontratado_prop = mean(REHIRE == "YES", na.rm = TRUE)
  )
