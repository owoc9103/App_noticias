# Diccionario de Datos - Base de Datos de Contratacion

## Tabla: datos_contratacion.csv

| Variable | Tipo | Descripcion | Valores Posibles / Rango |
|----------|------|-------------|-------------------------|
| **ID_EMPLEADO** | Numerico (Entero) | Identificador unico del empleado | Numeros enteros de 10 digitos (ej: 3285941608) |
| **SALARIO_ANUAL** | Numerico | Salario anual del empleado en dolares | Valores numericos (ej: 33615, 70675, 103199) |
| **SALARIO_POR_HORA** | Numerico | Salario por hora del empleado en dolares | Valores numericos (ej: 22, 40, 59) |
| **CODIGO_TRABAJO** | Numerico (Entero) | Codigo numerico que identifica el tipo de trabajo | Numeros enteros (ej: 71850, 59806, 60311) |
| **ETNIA** | Categorico | Grupo etnico del empleado | AFRO, ASIATICO, BLANCO, HISPANO, TWO |
| **SEXO** | Categorico | Sexo del empleado | MASCULINO, FEMENINO |
| **ESTADO_CIVIL** | Categorico | Estado civil del empleado | SOLTERO, CASADO, DIVORCIADO |
| **SATISFACCION_LABORAL** | Numerico (Entero) | Nivel de satisfaccion laboral (escala numerica) | 1, 2, 3, 4, 5 |
| **EDAD** | Numerico (Entero) | Edad del empleado en anos | Valores enteros (rango aproximado: 18-64) |
| **NUMERO_CAMBIOS_EQUIPO** | Categorico/Numerico | Numero de cambios de equipo realizados | 0, 1, 2, 3, 3+ |
| **FUENTE_REFERENCIA** | Categorico | Fuente mediante la cual el empleado fue referido | REFERENCIA_CLIENTE, REFERENCIA_EJECUTIVO, EX_EMPLEADO_INTERNO, CONTRATACION_DIRECTA, INROADS, DESCONOCIDO, FERIA_EMPLEO, ANUNCIO_IMPRESO, SITIO_CARRERAS_CORPORATIVO, AGENCIA, RECOMENDACION_UNIVERSITARIA, PUBLICACION_EMPLEO, TABLERO_EMPLEO_ANUNCIO_ONLINE, CASA_ABIERTA, RECLUTAMIENTO_UNIVERSITARIO_PREGRADO, NO_SOLICITADO, AGENCIA_PERSONAL, E_STRAT, Other Source, (valores vacios) |
| **MES_CONTRATACION** | Categorico | Mes en que fue contratado el empleado | ENERO, FEBRERO, MARZO, ABRIL, MAYO, JUNIO, JULIO, AGOSTO, SEPTIEMBRE, OCTUBRE, NOVIEMBRE, DICIEMBRE |
| **RECONTRATADO** | Categorico (Binario) | Indica si el empleado fue recontratado | SI, NO |
| **ANIO_TERMINACION** | Numerico/Categorico | Anio en que se termino la relacion laboral (si aplica) | Valores numericos (ej: 2005, 2006, 2007, 2008, 2009, 2010, 2011, 2012, 2014, 2015, 2016, 2017), NA (si no aplica) |
| **ES_PRIMER_EMPLEO** | Categorico (Binario) | Indica si este fue el primer empleo del trabajador | SI, NO |
| **VIAJES_REQUERIDOS** | Categorico (Binario) | Indica si se requieren viajes para el puesto | SI, NO, Y, N |
| **EVALUACION_DESEMPENO** | Numerico (Entero) | Calificacion del desempeno del empleado | 1, 2, 3, 4, 5 |
| **EMPLEADO_DISCAPACITADO** | Categorico (Binario) | Indica si el empleado tiene alguna discapacidad | SI, NO |
| **VETERANO_DISCAPACITADO** | Categorico (Binario) | Indica si el empleado es un veterano con discapacidad | SI, NO |
| **NIVEL_EDUCACION** | Categorico | Nivel educativo del empleado | NIVEL_1, NIVEL_2, NIVEL_3, NIVEL_4, NIVEL_5 |
| **ESTADO** | Categorico | Estado actual del empleado | ACTIVO, TERMINADO |
| **GRUPO_TRABAJO** | Categorico | Grupo o departamento de trabajo al que pertenece | MANTENIMIENTO_PLANTAS_INSTALACIONES, ATENCION_CLIENTE, FINANZAS, MARKETING_DIRECTO, FLUJOS_FISICOS, IMPUESTOS, ADMINISTRACION_GENERAL, PRODUCCION_OPERACIONES, DESARROLLO_I_D_PREDESARROLLO, ADQUISICION, APLICACIONES_NEGOCIO_TI, COMPRAS_PROMOCIONALES, SERVICIO_CREATIVO_COPIA, INGENIERIA, EMPAQUE_TECNICO, RECURSOS_HUMANOS, LEGAL, ASEGURAMIENTO_CALIDAD, CONTABILIDAD, SOPORTE_SERVICIOS_MARKETING, CADENA_SUMINISTRO_MANUFACTURA, LOGISTICA_SUMINISTRO_MERCADO, INVESTIGACION_MERCADO, Supply Chain FINANZAS, Supply Chain Administration, Industrial Quality, Package Development, IT Technologies and Infrstrctr, R&I Evaluation, Flows & Sub-Contracting, Digital, Corporate Supply Chain, IT Governance and Management, General Management, R&I General Management, Distribution/Administration, Logistics - Manufacturing |
| **DESEMPENO_ANIO_1** | Numerico | Desempeno del empleado en el anio 1 | Valores numericos (0-5, donde 0 puede indicar no aplica) |
| **DESEMPENO_ANIO_2** | Numerico | Desempeno del empleado en el anio 2 | Valores numericos (0-5, donde 0 puede indicar no aplica) |
| **DESEMPENO_ANIO_3** | Numerico | Desempeno del empleado en el anio 3 | Valores numericos (0-5, donde 0 puede indicar no aplica) |
| **DESEMPENO_ANIO_4** | Numerico | Desempeno del empleado en el anio 4 | Valores numericos (0-5, donde 0 puede indicar no aplica) |
| **DESEMPENO_ANIO_5** | Numerico | Desempeno del empleado en el anio 5 | Valores numericos (0-5, donde 0 puede indicar no aplica) |

## Notas Importantes

1. **Separador**: El archivo utiliza punto y coma (;) como separador de columnas.

2. **Valores Faltantes**: 
   - Algunas variables pueden contener valores vacios (""), especialmente en FUENTE_REFERENCIA
   - ANIO_TERMINACION contiene "NA" cuando el empleado no ha sido terminado

3. **Variables Binarias**: 
   - RECONTRATADO, ES_PRIMER_EMPLEO, EMPLEADO_DISCAPACITADO, VETERANO_DISCAPACITADO usan valores SI/NO
   - VIAJES_REQUERIDOS puede tener valores SI/NO o Y/N

4. **Escalas Numericas**:
   - SATISFACCION_LABORAL y EVALUACION_DESEMPENO usan escalas de 1 a 5
   - Las variables DESEMPENO_ANIO_X pueden tener valor 0, que probablemente indica que no hay registro de desempeno para ese anio

5. **Transformaciones Aplicadas**:
   - Todos los textos han sido traducidos al espanol
   - Se han removido las tildes y la letra "n" (reemplazada por "n")
