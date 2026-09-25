# ============================================================
# Geometría de los 24 partidos del GBA (aglomerado EPH 33)
# Author: simulador_macro
# Purpose: bajar los límites de los partidos de la provincia de Buenos Aires,
#          quedarse con los 24 que INDEC incluye en "Partidos del GBA" y dejar
#          una plantilla con las tabulaciones censales que alimentan el modelo.
# Inputs:  departamentos-buenos_aires.json (github.com/mgaitan/departamentos_argentina)
# Outputs: data/geo/partidos_gba_24.geojson
#          data/plantilla_insumos_partido.csv
#          scripts/R/_outputs/geo/mapa_partidos_gba.{pdf,png}
# ============================================================

# 0. Setup ----
library(sf)
library(dplyr)
library(readr)
library(ggplot2)

source(file.path("scripts", "R", "00_tema.R"))

url_geo <- paste0(
  "https://raw.githubusercontent.com/mgaitan/departamentos_argentina/",
  "master/departamentos-buenos_aires.json"
)
out_geo <- file.path("scripts", "R", "_outputs", "geo")
dir.create(out_geo, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path("data", "geo"), recursive = TRUE, showWarnings = FALSE)

# Los 24 partidos que INDEC agrupa en el aglomerado 33 de la EPH.
partidos_gba <- c(
  "ALMIRANTE BROWN", "AVELLANEDA", "BERAZATEGUI", "ESTEBAN ECHEVERRIA",
  "EZEIZA", "FLORENCIO VARELA", "GENERAL SAN MARTIN", "HURLINGHAM",
  "ITUZAINGO", "JOSE C PAZ", "LA MATANZA", "LANUS", "LOMAS DE ZAMORA",
  "MALVINAS ARGENTINAS", "MERLO", "MORENO", "MORON", "QUILMES",
  "SAN FERNANDO", "SAN ISIDRO", "SAN MIGUEL", "TIGRE", "TRES DE FEBRERO",
  "VICENTE LOPEZ"
)

# 1. Data Loading ----
geo_pba <- st_read(url_geo, quiet = TRUE)
stopifnot(all(partidos_gba %in% geo_pba$departamento))

geo_gba <- geo_pba |>
  filter(departamento %in% partidos_gba) |>
  mutate(partido = departamento) |>
  select(partido, cabecera)

stopifnot(nrow(geo_gba) == length(partidos_gba))

# 2. Plantilla de insumos ----
# Una fila por partido; cada columna es un insumo público a completar.
plantilla <- geo_gba |>
  st_drop_geometry() |>
  select(partido) |>
  mutate(
    hogares_censo2022 = NA_integer_,
    personas_censo2022 = NA_integer_,
    celdas_redatam_csv = NA_character_,  # ruta al cruce de 6 variables (ver docs)
    nbi_hogares_pct = NA_real_,
    titulares_auh = NA_integer_,
    personas_barrios_renabap = NA_integer_,
    asalariados_sipa_residentes = NA_integer_
  )

# 3. Figura de referencia ----
# Proyección plana (POSGAR 2007 faja 5) para ubicar bien las etiquetas.
fig_mapa <- ggplot(st_transform(geo_gba, 5347)) +
  geom_sf(fill = col_frio, alpha = 0.35, color = "white", linewidth = 0.3) +
  geom_sf_text(aes(label = partido), size = 1.8, color = col_tinta) +
  labs(
    title = "24 partidos del GBA (aglomerado 33 de la EPH)",
    subtitle = "Unidad objetivo de la estimación en áreas pequeñas",
    x = NULL, y = NULL,
    caption = "Límites: mgaitan/departamentos_argentina (derivado de IGN)."
  ) +
  theme_custom()

# 4. Export ----
st_write(geo_gba, file.path("data", "geo", "partidos_gba_24.geojson"),
         delete_dsn = TRUE, quiet = TRUE)
write_csv(plantilla, file.path("data", "plantilla_insumos_partido.csv"), na = "")
saveRDS(geo_gba, file.path(out_geo, "geo_gba.rds"))
ggsave(file.path(out_geo, "mapa_partidos_gba.pdf"), fig_mapa, width = 7, height = 7,
       bg = "transparent", device = cairo_pdf)
ggsave(file.path(out_geo, "mapa_partidos_gba.png"), fig_mapa, width = 7, height = 7,
       dpi = 200, bg = "transparent")
message("Partidos exportados: ", nrow(geo_gba))
