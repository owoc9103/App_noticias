# ---------------------------------------------
# 1. Cargar librerías
# ---------------------------------------------
library(dplyr)
library(lubridate)
library(digest)

data<-read.csv("C:/Users/owoc9/Documents/U Javeriana/Laboratorio Analítica/Mercadeo/Modelo RFM/Insumos/Transacciones.csv",sep=";")
colnames(data)
# ---------------------------------------------
# 2. Seleccionar únicamente variables útiles
# ---------------------------------------------
data_clean <- data %>%
  select(
    id_tiempo,
    hora,
    vlr_transaccion,
    cant_formularios,
    vlr_flete,
    cliente_documento,
    cliente_nombres,
    cliente_apellido1,
    cliente_fechanacimiento,
    cliente_genero,
    cliente_tipo_sangre,
    territorio_cod_municipio,
    territorio_nomb_municipio,
    producto_nomb_producto,
    tiempo_dia_semana,
    vendedor_documento,
    vendedor_fechanacimiento
  )



# ---------------------------------------------
# 3. Anonimizar IDs de cliente y vendedor
#    (HASH SHA-256 irreversibles)
# ---------------------------------------------
data_clean <- data_clean %>%
  mutate(
    cliente_documento = sapply(cliente_documento, digest, algo = "sha256"),
    vendedor_documento = sapply(vendedor_documento, digest, algo = "sha256")
  )


#----------------------------------------------
# 4. Exportar base de datos
#----------------------------------------------
write.csv(data_clean, "C:/Users/owoc9/Documents/U Javeriana/Laboratorio Analítica/Mercadeo/Modelo RFM/Resultado_R_Limpieza_Base/Transacciones.csv")


#### nUEVA bASE 
# Librerías
library(dplyr)

# 1️⃣ Crear particiones por ID único (clientes)
ids_particiones <- data %>%
  distinct(cliente_documento) %>%      # IDs únicos
  arrange(cliente_documento) %>%       # orden estable
  mutate(
    particion = ntile(row_number(), 3) # 3 particiones equitativas
  )

# 2️⃣ Unir las particiones a la base completa
data_particionada <- data %>%
  select(
    id_tiempo,
    hora,
    vlr_transaccion,
    cant_formularios,
    vlr_flete,
    cliente_documento,
    cliente_nombres,
    cliente_apellido1,
    cliente_fechanacimiento,
    cliente_genero,
    cliente_tipo_sangre,
    territorio_cod_municipio,
    territorio_nomb_municipio,
    producto_nomb_producto,
    tiempo_dia_semana,
    vendedor_documento,
    vendedor_fechanacimiento
  ) %>%
  left_join(ids_particiones, by = "cliente_documento")

# 3️⃣ (Opcional) Separar en 3 data frames
data_p1 <- data_particionada %>% filter(particion == 1)
data_p2 <- data_particionada %>% filter(particion == 2)
data_p3 <- data_particionada %>% filter(particion == 3)

data_p1=data_p1[,-dim(data_p1)[2]]
data_p2=data_p2[,-dim(data_p2)[2]]
data_p3=data_p3[,-dim(data_p3)[2]]



colnames(data_p3)

set.seed(123)  # opcional, para reproducibilidad

productos <- c("CHANCE", "LOTERIA", "GIROS","RECARGAS","BALOTO","RECAUDOS")



data_p1$producto_nomb_producto <- sample(productos, nrow(data_p1), replace = TRUE)
data_p2$producto_nomb_producto <- sample(productos, nrow(data_p2), replace = TRUE)
data_p3$producto_nomb_producto <- sample(productos, nrow(data_p3), replace = TRUE)

table(data_p3[,14])


write.csv(data_p1, "C:/Users/owoc9/Documents/U Javeriana/Laboratorio Analítica/Mercadeo/Modelo RFM/Resultado_R_Limpieza_Base/Transacciones_Empresa_1.csv")
write.csv(data_p2, "C:/Users/owoc9/Documents/U Javeriana/Laboratorio Analítica/Mercadeo/Modelo RFM/Resultado_R_Limpieza_Base/Transacciones_Empresa_2.csv")
write.csv(data_p3, "C:/Users/owoc9/Documents/U Javeriana/Laboratorio Analítica/Mercadeo/Modelo RFM/Resultado_R_Limpieza_Base/Transacciones_Empresa_3.csv")

# 4️⃣ Validaciones
# Filas por partición
table(data_particionada$particion)

# Clientes únicos por partición
data_particionada %>%
  distinct(cliente_documento, particion) %>%
  count(particion)


data_p1<-data_p1[,-dim(data_p1)[2]]
data_p2<-data_p2[,-dim(data_p2)[2]]
data_p3<-data_p3[,-dim(data_p3)[2]]





# Definir los productos
productos <- c("CHANCE", "LOTERIA", "ENVIO GIROS", "PAGO GIROS",
               "RECARGAS", "BALOTO", "RECAUDOS")

# Tamaño del vector
n <- 136743

# Generar el vector aleatorio
set.seed(123)  # opcional
vector_productos <- sample(productos, size = n, replace = TRUE)

# Convertir a data.frame
df_productos <- data.frame(producto = vector_productos)

# Exportar a CSV
write.csv(df_productos,
          file = "C:/Users/owoc9/Documents/U Javeriana/Laboratorio Analítica/Mercadeo/Modelo RFM/Resultado_R_Limpieza_Base/productos_136743.csv",
          row.names = FALSE)
