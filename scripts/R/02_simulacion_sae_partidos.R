# ============================================================
# Pobreza por partido del GBA: ¿cuán confiable es una estimación en áreas pequeñas?
# Author: simulador_macro
# Purpose: la EPH pública no identifica el partido dentro del aglomerado 33, así que
#          la única vía abierta es un estimador sintético: ajustar P(pobre | X) en la
#          EPH con variables que también mide el Censo 2022 y aplicarlo a los cruces
#          censales de cada partido. Este script mide, por Monte Carlo, cuánto error
#          tiene ese estimador y cuánto mejora un Fay-Herriot si INDEC entregara
#          estimaciones directas por partido (procesamiento especial).
# Inputs:  ninguno (población sintética calibrada a la incidencia en hogares del
#          aglomerado Partidos del GBA, 1S 2026: 29,7%).
# Outputs: scripts/R/_outputs/sae/resumen_escenarios.{rds,csv}
#          scripts/R/_outputs/sae/resultados_replicas.rds
#          scripts/R/_outputs/sae/fig_rmse_escenarios.{pdf,png}
#          scripts/R/_outputs/sae/fig_verdad_vs_estimado.{pdf,png}
#          scripts/R/_outputs/diagnostics/fig_covariables_por_partido.{pdf,png}
# ============================================================

# 0. Setup ----
library(dplyr)
library(tidyr)
library(purrr)
library(readr)
library(ggplot2)

source(file.path("scripts", "R", "00_tema.R"))

set.seed(20260925)  # YYYYMMDD (INV-9)

out_dir  <- file.path("scripts", "R", "_outputs", "sae")
diag_dir <- file.path("scripts", "R", "_outputs", "diagnostics")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(diag_dir, recursive = TRUE, showWarnings = FALSE)

# Parámetros del diseño ----
n_partidos     <- 24L
hog_medio      <- 20000L    # escala reducida; el estimador sintético no depende de N
n_eph          <- 4000L     # hogares EPH del aglomerado 33 en un semestre (supuesto)
deff_eph       <- 1.5       # efecto de diseño de la EPH (conglomerados, supuesto)
n_reps         <- 200L
pobreza_obj    <- 0.297     # INDEC 1S 2026, hogares, Partidos del GBA
sigma_u_grid   <- c(0, 0.25, 0.5)  # efecto partido no explicado por X (escala logit)
gamma_grid     <- c(0, 0.4)        # efecto contextual ligado a la privación del partido
eps            <- 1e-12

# Seis variables binarias que existen tanto en la EPH como en el Censo 2022.
covariables <- tibble(
  nombre = c("jefe_sin_secundario", "hacinamiento", "sin_cobertura_salud",
             "vivienda_deficitaria", "tres_o_mas_menores", "jefe_sin_ocupacion"),
  a      = c(-0.3, -2.0, -0.7, -2.2, -2.0, -2.3),  # intercepto de prevalencia
  c      = c(0.8, 0.7, 0.7, 0.8, 0.5, 0.4),        # gradiente por privación del partido
  beta   = c(1.0, 0.9, 1.1, 0.6, 0.8, 1.0)         # efecto sobre logit(pobre)
)
k_cov <- nrow(covariables)

# 1. Población sintética ----

#' Genera la población de hogares con covariables fijas
#' @param n_partidos Cantidad de partidos.
#' @param hog_medio Tamaño medio (hogares) por partido.
#' @return Lista con tibble de partidos y matriz de covariables por hogar.
generar_poblacion <- function(n_partidos, hog_medio) {
  partidos <- tibble(
    partido = sprintf("P%02d", seq_len(n_partidos)),
    z = as.numeric(scale(rnorm(n_partidos))),  # índice latente de privación
    n_hog = as.integer(round(hog_medio * exp(rnorm(n_partidos, 0, 0.6))))
  )
  id_partido <- rep(seq_len(n_partidos), partidos$n_hog)
  h <- rnorm(length(id_partido))  # privación del hogar: correlaciona las X
  z_hog <- partidos$z[id_partido]
  x <- matrix(0L, nrow = length(id_partido), ncol = k_cov,
              dimnames = list(NULL, covariables$nombre))
  for (k in seq_len(k_cov)) {
    p_k <- plogis(covariables$a[k] + covariables$c[k] * z_hog + 0.8 * h)
    x[, k] <- rbinom(length(p_k), 1L, p_k)
  }
  list(partidos = partidos, id = id_partido, x = x)
}

pob <- generar_poblacion(n_partidos, hog_medio)
n_pob <- length(pob$id)

# Celdas: cruce de las 6 binarias (64 celdas). Es lo que se pediría a REDATAM
# por partido; el estimador sólo usa estos conteos, nunca microdatos censales.
celda <- as.integer(pob$x %*% (2L^(seq_len(k_cov) - 1L))) + 1L
conteos_celda <- as.matrix(table(factor(pob$id, seq_len(n_partidos)),
                                 factor(celda, seq_len(2L^k_cov))))
x_celdas <- as.data.frame(
  (outer(seq_len(2L^k_cov) - 1L, 2L^(seq_len(k_cov) - 1L), `%/%`) %% 2L)
)
names(x_celdas) <- covariables$nombre

xb_hog <- drop(pob$x %*% covariables$beta)
z_hog  <- pob$partidos$z[pob$id]

# Intercepto calibrado para que la incidencia media sea la del aglomerado 33.
beta0 <- uniroot(function(b0) mean(plogis(b0 + xb_hog)) - pobreza_obj,
                 c(-10, 5))$root

# 2. Exploración de la población ----
prev_partido <- as_tibble(pob$x) |>
  mutate(partido = pob$partidos$partido[pob$id]) |>
  group_by(partido) |>
  summarise(across(everything(), mean), .groups = "drop") |>
  left_join(pob$partidos, by = "partido")
print(summary(prev_partido |> select(all_of(covariables$nombre))))
print(round(cor(pob$x), 2))

fig_cov <- prev_partido |>
  pivot_longer(all_of(covariables$nombre), names_to = "variable", values_to = "prev") |>
  ggplot(aes(z, prev)) +
  geom_point(color = col_acento) +
  facet_wrap(~variable, scales = "free_y") +
  labs(title = "Prevalencia de cada covariable censal por partido",
       x = "Índice latente de privación del partido", y = "Proporción de hogares") +
  theme_custom()

# 3. Estimadores ----

#' Ajusta Fay-Herriot por REML con varianzas de muestreo conocidas
#' @param y Estimaciones directas por área.
#' @param X Matriz de diseño a nivel área (con intercepto).
#' @param psi Varianzas de muestreo conocidas.
#' @return Lista con EBLUP, sigma2_v y beta.
ajustar_fay_herriot <- function(y, X, psi) {
  reml_neg <- function(s2) {
    v <- s2 + psi
    xtwx <- crossprod(X, X / v)
    b <- solve(xtwx, crossprod(X, y / v))
    r <- y - drop(X %*% b)
    # -2 log verosimilitud restringida (V diagonal)
    sum(log(v)) + as.numeric(determinant(xtwx)$modulus) + sum(r^2 / v)
  }
  s2 <- optimize(reml_neg, c(0, 10 * var(y)))$minimum
  v <- s2 + psi
  b <- solve(crossprod(X, X / v), crossprod(X, y / v))
  g <- s2 / v
  list(eblup = g * y + (1 - g) * drop(X %*% b), sigma2_v = s2, beta = drop(b))
}

#' Una réplica: genera pobreza, muestrea la EPH y calcula los tres estimadores
#' @param sigma_u Desvío del efecto aleatorio de partido (logit).
#' @param gamma Efecto contextual de la privación del partido (logit).
#' @return Tibble con verdad y estimaciones por partido.
correr_replica <- function(sigma_u, gamma) {
  u <- rnorm(n_partidos, 0, sigma_u)
  eta <- beta0 + xb_hog + gamma * z_hog + u[pob$id]
  y <- rbinom(n_pob, 1L, plogis(eta))
  verdad <- as.numeric(tapply(y, pob$id, mean))

  # EPH: muestra del aglomerado completo. La versión pública no trae partido.
  s <- sample.int(n_pob, n_eph)
  datos_eph <- as.data.frame(pob$x[s, ])
  datos_eph$pobre <- y[s]
  modelo <- glm(pobre ~ ., family = binomial(), data = datos_eph)

  # Sintético: probabilidad predicha por celda ponderada por conteos censales.
  p_celda <- predict(modelo, newdata = x_celdas, type = "response")
  sintetico <- drop(conteos_celda %*% p_celda) / rowSums(conteos_celda)

  # Benchmarking de razón: el total de los 24 partidos reproduce la EPH directa.
  n_hog <- pob$partidos$n_hog
  factor_bm <- mean(datos_eph$pobre) / (sum(n_hog * sintetico) / sum(n_hog))
  sintetico_bm <- pmin(1 - eps, sintetico * factor_bm)

  # Directo por partido: sólo posible si INDEC procesa con el identificador.
  id_s <- factor(pob$id[s], seq_len(n_partidos))
  n_d <- as.numeric(table(id_s))
  directo <- as.numeric(tapply(y[s], id_s, mean))
  # Varianza de muestreo con p suavizado (evita psi = 0 cuando directo es 0 o 1)
  psi <- deff_eph * sintetico_bm * (1 - sintetico_bm) / pmax(n_d, 1)
  ok <- n_d >= 2
  fh <- rep(NA_real_, n_partidos)
  if (sum(ok) > 3L) {
    ajuste <- ajustar_fay_herriot(directo[ok], cbind(1, sintetico_bm[ok]), psi[ok])
    fh[ok] <- ajuste$eblup
  }

  tibble(
    partido = pob$partidos$partido, n_muestra = n_d, verdad = verdad,
    sintetico = sintetico, sintetico_bm = sintetico_bm,
    directo = directo, fay_herriot = fh
  )
}

# 4. Monte Carlo ----
escenarios <- expand_grid(sigma_u = sigma_u_grid, gamma = gamma_grid)
resultados <- vector("list", nrow(escenarios))
for (i in seq_len(nrow(escenarios))) {
  sc <- escenarios[i, ]
  resultados[[i]] <- map_dfr(seq_len(n_reps), function(r) {
    correr_replica(sc$sigma_u, sc$gamma) |> mutate(rep = r)
  }) |>
    mutate(sigma_u = sc$sigma_u, gamma = sc$gamma)
  message(sprintf("Escenario %d/%d listo (sigma_u = %.2f, gamma = %.1f)",
                  i, nrow(escenarios), sc$sigma_u, sc$gamma))
}
resultados <- bind_rows(resultados)

estimadores <- c(sintetico_bm = "Sintético (EPH pública + censo)",
                 directo = "Directo por partido (procesamiento INDEC)",
                 fay_herriot = "Fay-Herriot (directo + sintético)")

metricas_rep <- resultados |>
  pivot_longer(all_of(names(estimadores)), names_to = "estimador", values_to = "est") |>
  group_by(sigma_u, gamma, estimador, rep) |>
  summarise(
    rmse_pp = 100 * sqrt(mean((est - verdad)^2, na.rm = TRUE)),
    mae_pp = 100 * mean(abs(est - verdad), na.rm = TRUE),
    spearman = cor(est, verdad, method = "spearman", use = "complete.obs"),
    # Pendiente < 1: el estimador aplana las diferencias entre partidos.
    pendiente = coef(lm(est ~ verdad))[["verdad"]],
    rango_verdad_pp = 100 * diff(range(verdad)),
    .groups = "drop"
  )

resumen <- metricas_rep |>
  group_by(sigma_u, gamma, estimador) |>
  summarise(
    rmse_pp = mean(rmse_pp), mae_pp = mean(mae_pp),
    spearman = mean(spearman), pendiente = mean(pendiente),
    rango_verdad_pp = mean(rango_verdad_pp), .groups = "drop"
  ) |>
  mutate(estimador_lbl = estimadores[estimador])
print(resumen |> select(-estimador_lbl), n = Inf, width = Inf)

cv_directo <- resultados |>
  filter(sigma_u == 0.25, gamma == 0.4) |>
  group_by(partido) |>
  summarise(n_medio = mean(n_muestra),
            cv_pct = 100 * sd(directo, na.rm = TRUE) / mean(verdad), .groups = "drop")
message(sprintf("CV del directo por partido: mediana %.1f%%, máx %.1f%% (n medio %.0f)",
                median(cv_directo$cv_pct), max(cv_directo$cv_pct),
                mean(cv_directo$n_medio)))

# 5. Figuras ----
lbl_esc <- function(s, g) sprintf("desvío partido = %.2f\nefecto contextual = %.1f", s, g)
fig_rmse <- resumen |>
  mutate(escenario = lbl_esc(sigma_u, gamma),
         estimador_lbl = factor(estimador_lbl, estimadores)) |>
  ggplot(aes(escenario, rmse_pp, fill = estimador_lbl)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.75) +
  scale_fill_manual(values = c(col_acento, col_regla, col_frio)) +
  labs(title = "Error medio por partido según cuánto pesa lo que el censo no mide",
       subtitle = paste0("RMSE entre partidos, puntos porcentuales. ", n_reps,
                         " réplicas por escenario, ", n_eph, " hogares EPH"),
       x = NULL, y = "RMSE (pp)", fill = NULL) +
  theme_custom() +
  theme(axis.text.x = element_text(size = 8))

rep_ilustrativa <- resultados |> filter(sigma_u == 0.25, gamma == 0.4, rep == 1L)
fig_scatter <- rep_ilustrativa |>
  pivot_longer(all_of(names(estimadores)), names_to = "estimador", values_to = "est") |>
  mutate(estimador = factor(estimadores[estimador], estimadores)) |>
  ggplot(aes(100 * verdad, 100 * est)) +
  geom_abline(color = col_tinta2, linetype = "dashed") +
  geom_point(color = col_acento, size = 2) +
  facet_wrap(~estimador) +
  coord_equal() +
  labs(title = "Una réplica: pobreza verdadera contra estimada, 24 partidos",
       subtitle = "Escenario intermedio (desvío partido = 0,25; efecto contextual = 0,4)",
       x = "Verdadera (% hogares)", y = "Estimada (% hogares)") +
  theme_custom()

# 6. Export ----
saveRDS(pob$partidos, file.path(out_dir, "partidos_sinteticos.rds"))
saveRDS(prev_partido, file.path(diag_dir, "prevalencias_por_partido.rds"))
saveRDS(resultados, file.path(out_dir, "resultados_replicas.rds"))
saveRDS(metricas_rep, file.path(out_dir, "metricas_por_replica.rds"))
saveRDS(resumen, file.path(out_dir, "resumen_escenarios.rds"))
saveRDS(cv_directo, file.path(out_dir, "cv_directo_por_partido.rds"))
write_csv(resumen, file.path(out_dir, "resumen_escenarios.csv"))

guardar_fig <- function(fig, nombre, w, h) {
  for (ext in c("pdf", "png")) {
    # cairo_pdf: el dispositivo pdf() por defecto no embebe bien los acentos
    dispositivo <- if (ext == "pdf") cairo_pdf else "png"
    ggsave(file.path(dirname(nombre), paste0(basename(nombre), ".", ext)), fig,
           width = w, height = h, dpi = 200, bg = "transparent", device = dispositivo)
  }
}
guardar_fig(fig_cov, file.path(diag_dir, "fig_covariables_por_partido"), 9, 6)
guardar_fig(fig_rmse, file.path(out_dir, "fig_rmse_escenarios"), 10, 5)
guardar_fig(fig_scatter, file.path(out_dir, "fig_verdad_vs_estimado"), 10, 4.5)
