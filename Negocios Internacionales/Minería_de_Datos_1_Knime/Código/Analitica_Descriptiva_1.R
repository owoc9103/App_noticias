####Punto 1####
library(readxl)
df <- read_excel("C:/Users/owoc9/Documents/U Javeriana/2025-II/Analítica de Datos para la toma de Decisiones/Taller 1/taller1-indicadores_economicos.xlsx")
View(df)

dim(df)

#R/ La tabla tiene un total de 220 filas y 10 columnas

####Punto 2####
class(df$`PIB (miles de millones USD)`)
class(df$Año)

table(df$Año,useNA = "ifany")

# & "y" 
# | "o"
colnames(df)
df$`PIB (miles de millones USD)`
df_2<-subset(df, Año == 2024 & `PIB (miles de millones USD)`>5000)

unique(df_2$`Nombre y Continente`)

####Punto 3:####

df$Ind_BalCom_PIB<-(df$`Balanza Comercial (miles de millones USD)`/ df$`PIB (miles de millones USD)`)


table(df$Ind_BalCom_PIB,useNA = "ifany")

which(is.na(df$Ind_BalCom_PIB)==TRUE)

df$Ind_BalCom_PIB[which(is.na(df$Ind_BalCom_PIB)==TRUE)]<-0

df_ordenado<-df[order(df$Ind_BalCom_PIB,decreasing = TRUE),]

df_ordenado$`Nombre y Continente`[1:3]

####Punto 4####
colnames(df)
table(df$`Riesgo País`,useNA = "ifany")


ifelse(1:10 <= 3,"verdadero", "Falso")

df$Riesgo_Pais_v2<-ifelse(df$`Riesgo País`=="Alto",4,
                          ifelse(df$`Riesgo País`=="Bajo",2,
                                 ifelse(df$`Riesgo País`=="Moderado",3,
                                        ifelse(df$`Riesgo País`=="Muy Alto",5,
                                               ifelse(df$`Riesgo País`=="Muy Bajo",1,NA)))))

table(df$`Riesgo País`,df$Riesgo_Pais_v2)

