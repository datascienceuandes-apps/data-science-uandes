#!/usr/bin/env Rscript
# =============================================================================
# actualizar_metricas.R
#
# Recalcula RESUMEN_METRICAS (total, por estado, por tipo de apoyo, por
# facultad/unidad, por año) a partir de un export de la hoja consolidada del
# formulario ("PowerBI" en el Excel de SharePoint) y reescribe ese bloque
# dentro de panel/index.html, entre los marcadores:
#   // __RESUMEN_METRICAS_START__  ...  // __RESUMEN_METRICAS_END__
#
# No toca ROADMAP ni ninguna otra parte del archivo.
#
# Uso:
#   Rscript actualizar_metricas.R ruta/al/export.csv panel/index.html
#
# El export.csv debe ser la hoja "PowerBI" exportada tal cual (una fila por
# solicitud, con las cabeceras originales del formulario). Si el formulario
# cambia de nombre alguna columna, ajusta las constantes COL_* más abajo.
# =============================================================================

suppressWarnings(suppressMessages({
  library(dplyr)
  library(tidyr)
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
# 1. Nombres de columna esperados en el export (ajustar aquí si cambian)
# ---------------------------------------------------------------------------
COL_ESTADO <- "Estado"
COL_TIPO_APOYO <- "¿Qué tipo de apoyo necesita sobre sus datos?"   # multi-selección separada por ";"
COL_FACULTAD <- "Facultad o Unidad (si no encuentra su centro, por favor especifique en la opción Otras)"
COL_FECHA_INGRESO <- "Start time"   # fecha de ingreso del formulario -> año

# Etiqueta larga -> etiqueta corta para mostrar en el panel público
MAPA_FACULTAD <- c(
  "Facultad de Ciencias Sociales" = "Facultad de Ciencias Sociales",
  "Facultad de Odontología" = "Facultad de Odontología",
  "Facultad de Medicina" = "Facultad de Medicina",
  "Facultad de Comunicación" = "Facultad de Comunicación",
  "Facultad de Enfermería y Obstetricia" = "Facultad de Enfermería y Obstetricia",
  "Clínica UAndes" = "Clínica UAndes",
  "CIIB" = "CIIB",
  "Dirección de Innovación" = "Dirección de Innovación",
  "CIIL Uandes" = "CIIL Uandes",
  "Dirección de Investigación y Doctorado" = "Dirección de Investigación y Doctorado"
)
OTRAS_FACULTADES_LABEL <- "Otras unidades (Ing., Economía, CEG)"

# ---------------------------------------------------------------------------
# 2. Cargar datos
# ---------------------------------------------------------------------------
if (!file.exists(ruta_csv)) stop("No se encontró el export: ", ruta_csv)
datos <- read_csv(ruta_csv, show_col_types = FALSE)

faltantes <- setdiff(c(COL_ESTADO, COL_TIPO_APOYO, COL_FACULTAD, COL_FECHA_INGRESO), names(datos))
if (length(faltantes) > 0) {
  stop(
    "El export no tiene las columnas esperadas: ", paste(faltantes, collapse = ", "),
    "\nRevisa los nombres COL_* al inicio de este script contra las cabeceras reales:\n",
    paste(names(datos), collapse = " | ")
  )
}

# Quitar filas vacías/plantilla
datos <- datos %>% filter(!is.na(.data[[COL_ESTADO]]), .data[[COL_ESTADO]] != "")

total <- nrow(datos)
if (total < 1) stop("El export no tiene filas válidas después de filtrar vacías; no se publica nada.")

# ---------------------------------------------------------------------------
# 3. Por estado
# ---------------------------------------------------------------------------
por_estado <- datos %>%
  count(label = .data[[COL_ESTADO]], name = "n") %>%
  arrange(desc(n))

# ---------------------------------------------------------------------------
# 4. Por tipo de apoyo (columna multi-selección separada por ";")
# ---------------------------------------------------------------------------
por_tipo <- datos %>%
  select(tipo = all_of(COL_TIPO_APOYO)) %>%
  filter(!is.na(tipo), tipo != "") %>%
  separate_rows(tipo, sep = "\\s*;\\s*") %>%
  count(label = tipo, name = "n") %>%
  arrange(desc(n))

# ---------------------------------------------------------------------------
# 5. Por facultad/unidad (agrupando las minoritarias en "Otras unidades")
# ---------------------------------------------------------------------------
fac_cruda <- datos %>%
  count(label = .data[[COL_FACULTAD]], name = "n")

fac_conocidas <- fac_cruda %>% filter(label %in% names(MAPA_FACULTAD))
fac_otras_n <- fac_cruda %>% filter(!label %in% names(MAPA_FACULTAD)) %>% pull(n) %>% sum()

por_facultad <- fac_conocidas %>%
  arrange(desc(n))
if (fac_otras_n > 0) {
  por_facultad <- bind_rows(por_facultad, tibble(label = OTRAS_FACULTADES_LABEL, n = fac_otras_n))
}

# ---------------------------------------------------------------------------
# 6. Por año de ingreso
# ---------------------------------------------------------------------------
anio_actual <- as.integer(format(Sys.Date(), "%Y"))
por_anio <- datos %>%
  mutate(anio = suppressWarnings(as.integer(format(
    as.Date(.data[[COL_FECHA_INGRESO]], tryFormats = c("%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y")),
    "%Y"
  )))) %>%
  filter(!is.na(anio)) %>%
  count(anio, name = "n") %>%
  arrange(anio) %>%
  mutate(label = ifelse(anio == anio_actual, paste0(anio, " (a la fecha)"), as.character(anio)))

# ---------------------------------------------------------------------------
# 7. Armar el bloque JS
# ---------------------------------------------------------------------------
a_lista_js <- function(df) {
  filas <- sprintf('    {label:%s, n:%d}', jsonlite::toJSON(df$label), df$n)
  paste(filas, collapse = ",\n")
}

bloque <- sprintf(
'// __RESUMEN_METRICAS_START__
const RESUMEN_METRICAS = {
  total: %d,
  fuente: \'Hoja consolidada del formulario, histórico + año en curso.\',
  actualizado: \'%s\',
  porEstado: [
%s
  ],
  porTipoApoyo: [
%s
  ],
  porFacultad: [
%s
  ],
  porAnio: [
%s
  ]
};
// __RESUMEN_METRICAS_END__',
  total,
  format(Sys.Date(), "%Y-%m-%d"),
  a_lista_js(por_estado),
  a_lista_js(por_tipo),
  a_lista_js(por_facultad),
  a_lista_js(por_anio %>% select(label, n))
)

# ---------------------------------------------------------------------------
# 8. Comparar contra lo ya publicado (ignorando la fecha) y solo escribir si
#    los números realmente cambiaron. Evita commits vacíos cada semana.
# ---------------------------------------------------------------------------
if (!file.exists(ruta_panel)) stop("No se encontró: ", ruta_panel)
html <- read_file(ruta_panel)

patron <- "// __RESUMEN_METRICAS_START__[\\s\\S]*?// __RESUMEN_METRICAS_END__"
if (!str_detect(html, patron)) {
  stop("No se encontraron los marcadores __RESUMEN_METRICAS_START__/END__ en ", ruta_panel,
       ". No se modifica el archivo para evitar publicar algo inconsistente.")
}

quitar_fecha <- function(x) str_replace(x, "actualizado: '[^']*',", "actualizado: '',")

bloque_anterior <- str_extract(html, patron)
sin_cambios <- quitar_fecha(bloque_anterior) == quitar_fecha(bloque)

if (sin_cambios) {
  cat(sprintf("SIN_CAMBIOS: %d solicitudes procesadas, los números no variaron respecto a la última publicación. No se modifica %s.\n",
              total, ruta_panel))
} else {
  html_nuevo <- str_replace(html, patron, bloque)
  write_file(html_nuevo, ruta_panel)
  cat(sprintf(
    "OK: %d solicitudes procesadas. %s actualizado (%s).\n",
    total, ruta_panel, format(Sys.Date(), "%Y-%m-%d")
  ))
}
