# Actualización del sitio

El sitio publica dos páginas independientes, con reglas distintas:

- **`index.html`** (raíz) — "Cómo trabajamos las solicitudes": proceso,
  catálogo de metodologías, agente y formación. Es **fija**: se edita a mano
  cuando el equipo actualiza su forma de trabajar, y **no** forma parte del
  cron de actualización.
- **`panel/index.html`** — "Métricas generales": conteos agregados del
  formulario (total, por estado, por tipo de apoyo, por facultad/unidad, por
  año), sin datos identificables. Es la **única** página que se recalcula
  automáticamente.

## Cómo se actualizan las métricas

1. Se exporta la hoja consolidada del formulario ("PowerBI" en el Excel de
   `InnovacionDataScience2/Documentos compartidos/General/Formulario de
   solicitud de apoyo en gestión y análisis de datos.xlsx`) a un CSV.
2. Se corre:

   ```bash
   Rscript scripts/actualizar_metricas.R ruta/al/export.csv panel/index.html
   ```

   Esto recalcula el total, por estado, por tipo de apoyo, por facultad/
   unidad y por año, y reemplaza **solo** el bloque `RESUMEN_METRICAS` dentro
   de `panel/index.html` (entre los marcadores `__RESUMEN_METRICAS_START__`
   y `__RESUMEN_METRICAS_END__`). No toca `index.html`.
3. Se revisa el diff (`git diff panel/index.html`) y se hace commit + push.
   GitHub Pages publica el cambio automáticamente al hacer push a `main`.

## Automatización semanal

Hay una tarea programada (scheduled task de Claude) que hace los tres pasos
de arriba una vez por semana, solo sobre `panel/index.html`:

- Descarga la hoja "PowerBI" vía el conector de Microsoft 365 (ya autenticado
  con la cuenta de la universidad — no requiere credenciales nuevas).
- Corre `actualizar_metricas.R` sobre ese export.
- Si el script termina sin error, hace commit y push directamente.
- Si el script falla (por ejemplo, porque cambió el nombre de alguna
  columna del formulario), **no publica nada** y avisa para revisar.
- Nunca toca `index.html`.

## Si el formulario cambia de estructura

Si en Microsoft Forms se renombra o agrega una columna (por ejemplo el
nombre exacto de "¿Qué tipo de apoyo necesita sobre sus datos?"), ajusta las
constantes `COL_*` al inicio de `scripts/actualizar_metricas.R` para que
vuelvan a calzar con las cabeceras reales del export.
