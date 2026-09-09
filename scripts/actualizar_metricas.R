#!/usr/bin/env Rscript
# =============================================================================
# actualizar_metricas.R
#
# El panel publico (panel/index.html) calcula TODOS sus KPIs en el navegador
# a partir de un unico array `DATA` (una fila anonimizada por solicitud).
# Este script NO reescribe ese calculo: solo sincroniza el campo "estado" (e)
# de las filas que YA EXISTEN en DATA contra el Excel, y reporta -sin
# publicarlas- las solicitudes nuevas que todavia no tienen fila en DATA,
# para que alguien les escriba a mano la descripcion (met) antes de agregarlas.
#
# Por que asi: los campos 'met' (metodologia, una linea editorial), 'mot'
# (motivo si no prospero) y 'cat' se escriben a mano -no son un calculo
# mecanico del Excel- y el codigo de anonimizacion ('inv'/'k') debe ser
# estable entre corridas. Este script nunca los toca ni los inventa.
#
# Uso:
#   Rscript actualizar_metricas.R ruta/al/export.csv panel/index.html
#
# El export.csv debe ser la hoja "PowerBI" (consolidada) exportada tal cual.
# =============================================================================

suppressWarnings(suppressMessages({
  library(dplyr)
  library(readr)
  library(stringr)
  library(jsonlite)
}))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("Uso: Rscript actualizar_metricas.R <export.csv> <panel/index.html>")
}
ruta_csv   <- args[[1]]
ruta_panel <- args[[2]]

# ---------------------------------------------------------------------------
# 1. Columnas esperadas en el export (ajustar aqui si el formulario cambia)
# ---------------------------------------------------------------------------
COL_ID     <- "Id"       # debe calzar con el "id" usado en DATA (ver mas abajo)
COL_ESTADO <- "Estado"

# ---------------------------------------------------------------------------
# 2. Cargar el export
# ---------------------------------------------------------------------------
if (!file.exists(ruta_csv)) stop("No se encontró el export: ", ruta_csv)
export <- read_csv(ruta_csv, show_col_types = FALSE)

faltantes <- setdiff(c(COL_ID, COL_ESTADO), names(export))
if (length(faltantes) > 0) {
  stop(
    "El export no tiene las columnas esperadas: ", paste(faltantes, collapse = ", "),
    "\nAjusta COL_ID / COL_ESTADO al inicio del script contra estas cabeceras reales:\n",
    paste(names(export), collapse = " | ")
  )
}

export <- export %>%
  transmute(
    id_raw = as.character(.data[[COL_ID]]),
    estado = .data[[COL_ESTADO]]
  ) %>%
  filter(!is.na(id_raw), id_raw != "", !is.na(estado), estado != "")

# ---------------------------------------------------------------------------
# 3. Extraer el array DATA actual de panel/index.html
# ---------------------------------------------------------------------------
if (!file.exists(ruta_panel)) stop("No se encontró: ", ruta_panel)
html <- read_file(ruta_panel)

patron_data <- "const DATA = (\\[.*?\\]);"
m <- str_match(html, patron_data)
if (is.na(m[1, 2])) {
  stop("No se encontró 'const DATA = [...]' en ", ruta_panel,
       ". No se modifica el archivo para evitar publicar algo inconsistente.")
}
data_json <- m[1, 2]
data_actual <- fromJSON(data_json, simplifyDataFrame = FALSE)

ids_data <- vapply(data_actual, function(r) as.character(r$id), character(1))

# ---------------------------------------------------------------------------
# 4. Emparejar por Id: separar en (a) filas existentes con estado distinto,
#    (b) solicitudes nuevas que no tienen fila en DATA todavia.
# ---------------------------------------------------------------------------
# El export.csv ya trae el id EXACTAMENTE en el mismo formato que DATA (la
# hoja "Antiguo" del Excel ya incluye el sufijo "_1" en su propia columna Id;
# la hoja "Nuevo" no lo lleva). Por eso la coincidencia debe ser EXACTA, sin
# adivinar sufijos: dos hojas distintas reinician su numeración y un id
# "30" de "Nuevo" puede coincidir por casualidad con el id "30_1" de
# "Antiguo", que es una solicitud completamente distinta.
cambios <- list()
nuevas  <- list()

for (i in seq_len(nrow(export))) {
  fila <- export[i, ]
  idx <- which(ids_data == fila$id_raw)

  if (length(idx) == 0) {
    nuevas[[length(nuevas) + 1]] <- fila
  } else {
    fila_data <- data_actual[[idx[[1]]]]
    if (!identical(fila_data$e, fila$estado)) {
      cambios[[length(cambios) + 1]] <- list(
        id = fila_data$id, estado_anterior = fila_data$e, estado_nuevo = fila$estado
      )
      data_actual[[idx[[1]]]]$e <- fila$estado
    }
  }
}

# ---------------------------------------------------------------------------
# 5. Si no hay cambios de estado ni solicitudes nuevas, no tocar el archivo.
# ---------------------------------------------------------------------------
if (length(cambios) == 0 && length(nuevas) == 0) {
  cat("SIN_CAMBIOS: no hay estados nuevos que sincronizar ni solicitudes nuevas.\n")
  quit(save = "no", status = 0)
}

# ---------------------------------------------------------------------------
# 6. Si hubo cambios de estado, reescribir el array DATA (solo el campo 'e'
#    de las filas afectadas cambia; el resto queda byte a byte igual).
# ---------------------------------------------------------------------------
if (length(cambios) > 0) {
  data_json_nuevo <- toJSON(data_actual, auto_unbox = TRUE, null = "null")
  html_nuevo <- str_replace(html, patron_data, paste0("const DATA = ", data_json_nuevo, ";"))

  patron_fecha <- "const LAST_UPDATE = '[^']*';"
  fecha_nueva <- sprintf("const LAST_UPDATE = '%s';", format(Sys.Date(), "%Y-%m-%d"))
  if (str_detect(html_nuevo, patron_fecha)) {
    html_nuevo <- str_replace(html_nuevo, patron_fecha, fecha_nueva)
  }

  write_file(html_nuevo, ruta_panel)

  cat(sprintf("OK: %d solicitud(es) con estado actualizado en %s:\n", length(cambios), ruta_panel))
  for (c in cambios) {
    cat(sprintf("  - id %s: %s -> %s\n", c$id, c$estado_anterior, c$estado_nuevo))
  }
} else {
  cat("SIN_CAMBIOS_DE_ESTADO: no se modifica DATA (solo hay solicitudes nuevas pendientes, ver abajo).\n")
}

# ---------------------------------------------------------------------------
# 7. Solicitudes nuevas: NUNCA se agregan solas a DATA. Se listan para que
#    Pamela las agregue a mano (con su descripcion 'met' y su codigo de
#    anonimizacion).
# ---------------------------------------------------------------------------
if (length(nuevas) > 0) {
  cat(sprintf("\nPENDIENTES: %d solicitud(es) nueva(s) en el Excel sin fila en DATA todavía:\n", length(nuevas)))
  for (n in nuevas) {
    cat(sprintf("  - Id %s (estado: %s) — agregar a mano en panel/index.html con su descripción.\n", n$id_raw, n$estado))
  }
}
