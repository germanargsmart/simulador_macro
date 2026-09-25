# Pobreza por partido del GBA: qué datos hacen falta y qué tan confiable puede ser

Nota de trabajo para llevar el tablero de pobreza (EPH, 1S 2026) desde el aglomerado
"Partidos del GBA" hasta cada uno de sus 24 partidos.

## 1. El problema

La EPH trata a los 24 partidos como un solo aglomerado (código 33). En el 1S 2026 ese
aglomerado tiene 36,9% de personas pobres, con un CV de 4,7%. **La base de microdatos pública
no identifica el partido, la fracción ni el radio del hogar.** Por eso no hay forma de calcular
una tasa directa por partido con datos abiertos, ni siquiera juntando varios semestres.

Hay tres caminos, del más confiable al menos confiable:

| Ruta | Qué produce | ¿Se puede hacer hoy con datos abiertos? |
|---|---|---|
| **A. Procesamiento especial de INDEC + Fay-Herriot** | Tasa por partido con error acotado (RMSE de alrededor de 3 pp en la simulación) | No. Hay que pedírselo formalmente a INDEC |
| **B. Estimador sintético (EPH pública + Censo 2022)** | Tasa modelada por partido. El ranking sale bien, pero los extremos quedan achatados | Sí |
| **C. Indicadores sin ingreso (NBI, AUH, RENABAP)** | Mide carencias, no pobreza por ingresos | Sí. Sirve para validar, no para reemplazar |

## 2. Datos necesarios

### Núcleo (sin esto no hay estimación)

| Insumo | Fuente | Nivel | Para qué |
|---|---|---|---|
| Microdatos EPH `usu_hogar` y `usu_individual`, los dos trimestres del semestre | INDEC | Hogar y persona, `AGLOMERADO == 33` | Ajustar P(pobre \| X). Variables: `ITF`, `IX_TOT`, `IX_MEN10`, `IV2`, `IV3`, `IV4`, `CH03`, `CH08`, `NIVEL_ED`, `ESTADO`, `PONDIH` |
| Canasta básica total del GBA y tabla de adultos equivalentes | INDEC | Mensual | Clasificar a cada hogar EPH como pobre o no pobre |
| Censo 2022, tabulados de REDATAM | INDEC | Partido (y radio, para ir más fino) | Cantidad de hogares en cada celda de covariables, por partido |
| Límites de los partidos | IGN / INDEC | Polígono | Mapa. Ya están en `data/geo/partidos_gba_24.geojson` |

El cruce que hay que pedirle a REDATAM, **por partido**, tiene 6 variables del hogar o de su
jefe o jefa, dicotomizadas de la misma forma que en la EPH (64 celdas × 24 partidos):

1. Jefe o jefa sin secundario completo.
2. Hacinamiento: más de 2 personas por cuarto.
3. Jefe o jefa sin obra social, prepaga ni PAMI.
4. Vivienda deficitaria: piso o techo de materiales precarios.
5. Tres o más menores en el hogar.
6. Jefe o jefa sin ocupación (desocupado o inactivo no jubilado).

Para pasar de hogares a personas hace falta además la cantidad de personas por celda.

> **Condición que decide todo:** cada variable tiene que medirse igual en la EPH y en el censo:
> las mismas categorías, la misma pregunta y la misma unidad. Si una variable no se puede armonizar,
> se saca del modelo. Una covariable mal armonizada mete un sesgo que después no se puede
> corregir.

### Covariables de área (para Fay-Herriot) y validación

| Insumo | Fuente | Nivel | Uso |
|---|---|---|---|
| Titulares y niños con AUH/AUE | ANSES | Partido | Covariable FH / validación |
| Prestaciones alimentarias (Tarjeta Alimentar o la que la reemplace) | Min. Capital Humano | Partido | Covariable FH / validación |
| Barrios populares: polígonos y familias estimadas | RENABAP | Barrio | Proporción de hogares en barrios populares |
| NBI Censo 2022 | INDEC | Partido / radio | Validación (correlación esperada alta, no 1) |
| Empleo asalariado registrado | SIPA / OEDE | Departamento | Cuidado: suele ir por localización del empleador, no por residencia |
| Tarifa social de energía / consumo residencial | ENRE / distribuidoras | Partido | Proxy de ingreso actualizado |
| Luces nocturnas VIIRS | NOAA / EOG | Grilla ~500 m | Proxy de actividad, útil a nivel de radio |
| Pobreza por cordón del conurbano | UCA-ODSA (EDSA) | Cordón | Validación externa de los agregados |

### Lo que conviene pedirle a INDEC (ruta A)

Un **procesamiento especial** de la EPH con el identificador de partido que tiene el marco
muestral:

- Tasa de pobreza e indigencia (hogares y personas) por partido, o por grupos de partidos si
  alguno queda con muy pocos casos.
- Tamaño de muestra y **coeficiente de variación** de cada estimación.
- Si es posible, 4 semestres acumulados para bajar el CV.

Con eso se ajusta un Fay-Herriot que usa el estimador sintético de la ruta B y las variables
administrativas como covariables. Es el estándar para mapas de pobreza oficiales (SAIPE de EE.UU.,
CONEVAL en México).

## 3. Simulación: cuánto error esperar

`scripts/R/02_simulacion_sae_partidos.R` arma una población sintética de 24 partidos, calibrada a
29,7% de hogares pobres. Toma una muestra tipo EPH de 4.000 hogares sin identificar el partido y
compara tres estimadores en 200 réplicas por escenario. Los escenarios varían cuánto de la
diferencia entre partidos **no** explican las 6 variables censales:

- *Desvío partido*: un efecto propio de cada partido, sin relación con nada observado.
- *Efecto contextual*: un efecto que crece con la privación del partido, por ejemplo por el
  mercado de trabajo local. Es el caso más realista.

| Escenario (desvío, contextual) | Sintético RMSE | Sintético pendiente | Sintético Spearman | Directo RMSE | Fay-Herriot RMSE |
|---|---|---|---|---|---|
| 0 / 0 (el censo explica todo) | 0,7 pp | 1,00 | 0,998 | 4,1 pp | 0,9 pp |
| 0 / 0,4 | 5,1 pp | 0,67 | 0,999 | 3,9 pp | 1,0 pp |
| 0,25 / 0 | 3,9 pp | 0,86 | 0,91 | 4,1 pp | 3,1 pp |
| **0,25 / 0,4 (intermedio)** | **6,3 pp** | **0,64** | **0,97** | **3,9 pp** | **3,0 pp** |
| 0,5 / 0 | 7,8 pp | 0,59 | 0,74 | 4,2 pp | 3,8 pp |
| 0,5 / 0,4 | 9,1 pp | 0,54 | 0,88 | 3,8 pp | 3,7 pp |

La pendiente es la de regresar lo estimado sobre lo verdadero. Una pendiente de 0,64 quiere decir
que el estimador muestra solo el 64% de la distancia real entre partidos.

Lecturas:

1. **Con datos abiertos (sintético), el orden de los partidos es confiable** (Spearman entre 0,88
   y 0,97 en los escenarios razonables). **El nivel no lo es**: el estimador achata los extremos,
   así que sobreestima la pobreza de los partidos ricos y subestima la de los pobres, con errores
   de 5 a 9 pp. Conviene publicarlo como ranking o quintiles, no como tasa puntual.
2. **El directo por partido, solo, es ruidoso**: con unos 167 hogares por partido y semestre, el
   CV mediano ronda 20% y el máximo 42%. Muchos partidos quedarían en la zona "no confiable" de
   INDEC.
3. **Fay-Herriot es el que mejor anda en todos los escenarios**: combina directo y sintético y
   deja el error en unos 3 pp. Por eso la ruta A es la que da un trabajo "relativamente confiable".
4. El benchmarking (que los 24 partidos sumen el total de la EPH) garantiza la coherencia con la
   cifra oficial, pero no corrige el achatamiento.

Supuestos que conviene revisar con datos reales: el tamaño de muestra (4.000 hogares por
semestre), el efecto de diseño (1,5), la asignación proporcional de la muestra entre partidos y
que la EPH se trate como muestra aleatoria simple dentro del aglomerado. En la EPH real hay
conglomerados, así que el CV de los directos sería algo mayor.

## 4. Protocolo para que el resultado sea defendible

1. **Armonizar** las 6 variables entre EPH y censo y documentar cada recodificación.
2. **Ajustar** el logit en la EPH del aglomerado 33, con ponderador `PONDIH`, y revisar la
   calibración por deciles de probabilidad predicha.
3. **Predecir por celda** y agregar con los conteos censales de cada partido.
4. **Benchmarkear** al directo del aglomerado 33 del mismo semestre.
5. **Medir la incertidumbre** con bootstrap paramétrico: volver a muestrear la EPH, reajustar y
   volver a predecir. Hay que sumarle una cota del sesgo por efecto contextual, usando la tabla
   de arriba.
6. **Validar** contra NBI 2022, la tasa de AUH por partido y los agregados por cordón de UCA-ODSA.
   Si el ranking sintético no correlaciona fuerte con AUH y NBI, algo está mal armonizado.
7. **Publicar** con intervalos, marcando los partidos cuyo intervalo cruza el promedio del
   aglomerado, y aclarando que el censo es de 2022 y la EPH de 2026.

## 5. Archivos

| Archivo | Qué hace |
|---|---|
| `scripts/R/00_tema.R` | Paleta y tema gráfico compartidos |
| `scripts/R/01_geometria_partidos_gba.R` | Límites de los 24 partidos y plantilla de insumos |
| `scripts/R/02_simulacion_sae_partidos.R` | Monte Carlo sintético vs. directo vs. Fay-Herriot |
| `data/geo/partidos_gba_24.geojson` | Polígonos de los 24 partidos |
| `data/plantilla_insumos_partido.csv` | Una fila por partido con los insumos a completar |
| `scripts/R/_outputs/` | Figuras, tablas y objetos `.rds` |

Para correr: `LC_ALL=C.UTF-8 Rscript scripts/R/01_geometria_partidos_gba.R` y después el `02`,
desde la raíz del repositorio. Se necesitan los paquetes `sf`, `dplyr`, `tidyr`, `purrr`, `readr`
y `ggplot2`.

**Próximo paso cuando estén los datos:** `03_eph_modelo_hogar.R` (armonizar y ajustar con la EPH
real), `04_censo_celdas.R` (leer el cruce de REDATAM) y `05_prediccion_mapa.R` (estimar,
benchmarkear, calcular bootstrap y hacer el mapa).
