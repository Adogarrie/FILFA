"""
Importa el calendario de liga desde un CSV y lo inserta en Supabase.

Formato del CSV (separador coma o punto y coma):
    Jornada,Division,Local,Visitante,Neutral
    1,Primera,Buguis,CD Fuenteolletas,no
    1,Primera,Como Tu CF,Cuadrabondigas United,no
    2,Segunda,AC Riera Team,Bulerias CF,no

  - Jornada  : número entero
  - Division  : "Primera" o "Segunda" (exacto)
  - Local     : nombre exacto del equipo en la BD
  - Visitante : nombre exacto del equipo en la BD
  - Neutral   : "si"/"sí"/"yes"/"1"/"true" → neutral; cualquier otra cosa → no neutral

Uso:
    python importar_calendario.py --csv mi_calendario.csv
    python importar_calendario.py --csv mi_calendario.csv --prueba
    python importar_calendario.py --csv mi_calendario.csv --reset
"""

import sys, io, os, csv, argparse
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from dotenv import load_dotenv
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")


def get_supabase():
    from supabase import create_client
    return create_client(SUPABASE_URL, SUPABASE_KEY)


def leer_csv(ruta):
    if not os.path.exists(ruta):
        raise SystemExit(f"Archivo no encontrado: {ruta}")
    filas = []
    with open(ruta, encoding="utf-8-sig") as f:
        contenido = f.read()
        sep = ";" if contenido.count(";") > contenido.count(",") else ","
        reader = csv.DictReader(io.StringIO(contenido), delimiter=sep)
        for fila in reader:
            norm = {k.strip().lower(): v.strip() for k, v in fila.items()}
            filas.append(norm)
    return filas


def es_neutral(val: str) -> bool:
    return val.lower() in ("si", "sí", "yes", "1", "true", "s", "y")


def main():
    parser = argparse.ArgumentParser(description="Importa calendario de liga desde CSV")
    parser.add_argument("--csv",    required=True, help="Ruta al CSV")
    parser.add_argument("--prueba", action="store_true", help="Simula sin guardar")
    parser.add_argument("--reset",  action="store_true", help="Borra el calendario existente primero")
    args = parser.parse_args()

    sb  = get_supabase()
    filas = leer_csv(args.csv)
    print(f"  Filas leídas: {len(filas)}\n")

    # Cachear nombres → IDs
    partics = sb.table("participantes").select("id, nombre").execute().data or []
    nombre_a_id = {p["nombre"]: p["id"] for p in partics}

    divs = sb.table("divisiones").select("id, nombre").execute().data or []
    div_a_id = {d["nombre"]: d["id"] for d in divs}

    registros = []
    errores   = []

    for i, f in enumerate(filas, 1):
        jornada   = f.get("jornada", "").strip()
        division  = f.get("division", "").strip()
        local     = f.get("local", "").strip()
        visitante = f.get("visitante", "").strip()
        neutral   = es_neutral(f.get("neutral", "no"))

        if not jornada or not division or not local or not visitante:
            errores.append(f"Fila {i}: campos vacíos — {f}")
            continue

        div_id = div_a_id.get(division)
        loc_id = nombre_a_id.get(local)
        vis_id = nombre_a_id.get(visitante)

        if not div_id:
            errores.append(f"Fila {i}: división '{division}' no encontrada")
            continue
        if not loc_id:
            errores.append(f"Fila {i}: equipo local '{local}' no encontrado")
            continue
        if not vis_id:
            errores.append(f"Fila {i}: equipo visitante '{visitante}' no encontrado")
            continue
        if loc_id == vis_id:
            errores.append(f"Fila {i}: local y visitante son el mismo equipo")
            continue

        registros.append({
            "jornada":      int(jornada),
            "division_id":  div_id,
            "local_id":     loc_id,
            "visitante_id": vis_id,
            "es_neutral":   neutral,
        })

    if errores:
        print("Advertencias:")
        for e in errores:
            print(f"  ⚠  {e}")
        print()

    print(f"Partidos válidos: {len(registros)}")

    if args.prueba:
        print("\nMuestra (primeros 5):")
        id_nom = {v: k for k, v in nombre_a_id.items()}
        for r in registros[:5]:
            loc = id_nom.get(r["local_id"], "?")
            vis = id_nom.get(r["visitante_id"], "?")
            print(f"  J{r['jornada']:2d}  {loc:<25} vs  {vis}")
        print("\n[PRUEBA] No se ha guardado nada.")
        return

    if args.reset:
        print("Borrando calendario existente…")
        sb.table("calendario").delete().gt("id", 0).execute()
        print("  Borrado.\n")

    print("Insertando en Supabase…")
    batch = 100
    for i in range(0, len(registros), batch):
        sb.table("calendario").insert(registros[i:i+batch]).execute()

    print(f"Calendario importado correctamente ({len(registros)} partidos).")


if __name__ == "__main__":
    main()


# ═══════════════════════════════════════════════════════════════
# FORMATO DEL CSV
# ═══════════════════════════════════════════════════════════════
#
# Jornada,Division,Local,Visitante,Neutral
# 1,Primera,Buguis,CD Fuenteolletas,no
# 1,Primera,Como Tu CF,Cuadrabondigas United,no
# 1,Segunda,AC Riera Team,Bulerias CF,no
#
# Columnas:
#   Jornada   → número entero (1-38)
#   Division  → "Primera" o "Segunda" (tal cual en la BD)
#   Local     → nombre exacto del equipo
#   Visitante → nombre exacto del equipo
#   Neutral   → "si" o "no"
# ═══════════════════════════════════════════════════════════════
