#!/usr/bin/env python3
# =============================================================================
# actualizar_metricas.py
#
# Equivalente en Python de scripts/actualizar_metricas.R, para correr en el
# shell del puente (Linux, sin R instalado). Misma lógica exacta:
#   - Solo actualiza el campo de estado ('e') de filas que YA EXISTEN en
#     DATA si el Excel muestra un estado distinto. No toca 'met', 'mot',
#     'cat', 'inv', 'k' ni fechas.
#   - Las solicitudes nuevas (Id sin fila en DATA) se reportan, nunca se
#     agregan solas.
#   - Actualiza LAST_UPDATE solo si de verdad hubo un cambio.
#
# Uso:
#   python3 actualizar_metricas.py export.csv panel/index.html
# =============================================================================
import csv
import json
import re
import sys
from datetime import date

if len(sys.argv) < 3:
    sys.exit("Uso: python3 actualizar_metricas.py <export.csv> <panel/index.html>")

ruta_csv, ruta_panel = sys.argv[1], sys.argv[2]

COL_ID = "Id"
COL_ESTADO = "Estado"

with open(ruta_csv, encoding="utf-8") as f:
    reader = csv.DictReader(f)
    if COL_ID not in reader.fieldnames or COL_ESTADO not in reader.fieldnames:
        sys.exit(
            f"El export no tiene las columnas esperadas: {COL_ID}, {COL_ESTADO}\n"
            f"Cabeceras reales: {reader.fieldnames}"
        )
    # Se exige Id no vacío, pero NO se descartan filas con Estado vacío: una
    # solicitud nueva que todavía no tiene estado asignado en el Excel debe
    # reportarse igual como pendiente, nunca desaparecer silenciosamente.
    export_rows = [
        (row[COL_ID].strip(), row[COL_ESTADO].strip())
        for row in reader
        if row[COL_ID].strip()
    ]

with open(ruta_panel, encoding="utf-8") as f:
    html = f.read()

m = re.search(r"const DATA = (\[.*?\]);", html, re.S)
if not m:
    sys.exit(f"No se encontró 'const DATA = [...]' en {ruta_panel}. No se modifica el archivo.")

data = json.loads(m.group(1))
ids_data = {str(r["id"]): i for i, r in enumerate(data)}

cambios = []
nuevas = []

for id_raw, estado in export_rows:
    # El export.csv ya trae el id en el mismo formato que DATA (con o sin
    # sufijo "_1" segun de que hoja vino) -- coincidencia exacta, sin adivinar.
    idx = ids_data.get(id_raw)
    if idx is None:
        nuevas.append((id_raw, estado or "(sin estado en el Excel)"))
    elif estado and data[idx]["e"] != estado:
        # Si el Excel no trae estado todavia, no se sobreescribe el que ya
        # hay en DATA con un valor vacio.
        cambios.append((data[idx]["id"], data[idx]["e"], estado))
        data[idx]["e"] = estado

if not cambios and not nuevas:
    print("SIN_CAMBIOS: no hay estados nuevos que sincronizar ni solicitudes nuevas.")
    sys.exit(0)

if cambios:
    data_json_nuevo = json.dumps(data, ensure_ascii=False)
    html_nuevo = html[:m.start()] + f"const DATA = {data_json_nuevo};" + html[m.end():]

    fecha_nueva = date.today().isoformat()
    html_nuevo = re.sub(
        r"const LAST_UPDATE = '[^']*';",
        f"const LAST_UPDATE = '{fecha_nueva}';",
        html_nuevo,
    )

    with open(ruta_panel, "w", encoding="utf-8") as f:
        f.write(html_nuevo)

    print(f"OK: {len(cambios)} solicitud(es) con estado actualizado en {ruta_panel}:")
    for id_, antes, despues in cambios:
        print(f"  - id {id_}: {antes} -> {despues}")
else:
    print("SIN_CAMBIOS_DE_ESTADO: no se modifica DATA (solo hay solicitudes nuevas pendientes, ver abajo).")

if nuevas:
    print(f"\nPENDIENTES: {len(nuevas)} solicitud(es) nueva(s) en el Excel sin fila en DATA todavía:")
    for id_raw, estado in nuevas:
        print(f"  - Id {id_raw} (estado: {estado}) — agregar a mano en panel/index.html con su descripción.")
