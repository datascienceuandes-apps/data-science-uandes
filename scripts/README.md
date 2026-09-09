# Actualización del sitio

El sitio publica dos páginas independientes, con reglas distintas:

- **`index.html`** (raíz) — "Cómo trabajamos las solicitudes": proceso,
  catálogo de metodologías, agente y formación. Es **fija**: se edita a mano,
  y **no** forma parte del cron de actualización.
- **`panel/index.html`** — panel ejecutivo completo (KPIs, demanda por año,
  tiempos por etapa, investigadores que vuelven, dotación, formación).
  Todos sus gráficos se calculan en el navegador a partir de un único array
  `DATA` (una fila anonimizada por solicitud, sin nombres ni correos).

## Qué automatiza el script y qué no

Hay dos versiones **equivalentes** de la misma lógica: `actualizar_metricas.R`
(para correrlo tú, a mano, desde tu R/RStudio) y `actualizar_metricas.py`
(la que usa la tarea programada, porque el entorno donde corre esa tarea no
tiene R instalado — solo Python3). Ambas hacen exactamente lo mismo y
**no reescriben `DATA` completo** ni inventan contenido editorial. Solo
hacen dos cosas, comparando el Excel contra lo que ya está en `DATA`:

1. Para solicitudes que **ya tienen fila en `DATA`** (mismo Id, coincidencia
   exacta): si el estado cambió en el Excel (por ejemplo, pasó de "En
   espera" a "Finalizado"), actualiza el campo `e` de esa fila. No toca
   `met`, `mot`, `cat`, `inv`, `k`, fechas ni nada más — eso quedó escrito
   a mano y se preserva tal cual.
2. Para solicitudes **nuevas** que no tienen fila todavía, no las agrega
   solas: las **reporta en la salida** para que alguien les escriba a mano
   la descripción (`met`) y el código de anonimización, y las agregue al
   array cuando estén listas.

La coincidencia de Id es **exacta** (no se adivina un sufijo `_1`): la hoja
"Antiguo" del Excel ya trae el Id con su propio sufijo `_1` incluido, y la
hoja "Nuevo" no lo lleva — cada hoja numera sus solicitudes por separado,
así que un Id "30" de "Nuevo" y un Id "30_1" de "Antiguo" son dos
solicitudes completamente distintas, no la misma con o sin sufijo.

Si no hay cambios de estado ni solicitudes nuevas, no toca el archivo
(imprime `SIN_CAMBIOS`).

Uso manual (R):

```bash
Rscript scripts/actualizar_metricas.R ruta/al/export.csv panel/index.html
```

Uso manual (Python, mismo resultado):

```bash
python3 scripts/actualizar_metricas.py ruta/al/export.csv panel/index.html
```

El `export.csv` debe tener columnas `Id` y `Estado`, con el Id exactamente
en el mismo formato que usan las hojas "Nuevo" y "Antiguo" del Excel de
`InnovacionDataScience2/Documentos compartidos/General/Formulario de
solicitud de apoyo en gestión y análisis de datos.xlsx`.

## Automatización semanal

Una tarea programada de Claude hace esto una vez por semana:

- Descarga las hojas "Nuevo" y "Antiguo" vía el conector de Microsoft 365
  (ya autenticado — no requiere credenciales nuevas) y arma el export.csv.
- Corre `python3 scripts/actualizar_metricas.py` sobre ese export (el
  entorno de la tarea programada no tiene R instalado).
- Si hubo cambios de estado, revisa el diff y hace **commit local**
  (nunca push — el shell de este computador no tiene salida a GitHub).
- Te avisa con: cuántos estados cambiaron, las solicitudes nuevas
  pendientes de descripción (si hay), el código para pegar y publicar, y
  un link `file://` al `panel/index.html` local para que lo veas en tu
  navegador antes de subirlo.
- Si no hay nada que cambiar, no te avisa (no genera ruido cada semana).
- Nunca toca `index.html`.

## Si el formulario cambia de estructura

Si en Microsoft Forms se renombra la columna de Id o de Estado, ajusta las
constantes `COL_ID` / `COL_ESTADO` al inicio de `scripts/actualizar_metricas.R`
**y** de `scripts/actualizar_metricas.py` para que vuelvan a calzar con las
cabeceras reales del export.
