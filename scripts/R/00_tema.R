# ============================================================
# Tema gráfico del proyecto
# Purpose: paleta y theme_custom() compartidos por todos los scripts,
#          alineados con el tablero de pobreza (tonos terracota / azul gris).
# ============================================================

col_acento  <- "#C4643A"
col_frio    <- "#6F8195"
col_tinta   <- "#2B2723"
col_tinta2  <- "#6B625A"
col_regla   <- "#E6DED4"

#' Tema base para todas las figuras
#' @param base_size Tamaño base de fuente.
#' @return Objeto theme de ggplot2.
theme_custom <- function(base_size = 12) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", color = col_tinta),
      plot.subtitle = ggplot2::element_text(color = col_tinta2),
      plot.caption = ggplot2::element_text(color = col_tinta2, hjust = 0),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(color = col_regla, linewidth = 0.3),
      legend.position = "bottom"
    )
}
