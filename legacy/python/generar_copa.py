"""
Configura la Copa de la Liga: asigna equipos a grupos y genera el calendario.

Lee un CSV con la asignación de grupos y genera partidos de liguilla
(todos contra todos dentro de cada grupo).

Uso:
    python generar_copa.py --grupos grupos_copa.csv --jornada-inicio 1
    python generar_copa.py --grupos grupos_copa.csv --jornada-inicio 1 --prueba
    python generar_copa.py --grupos grupos_copa.csv --jornada-inicio 1 --reset

Formato del CSV de grupos:
    Grupo,Equipo
    A,Buguis
    A,CD Fuenteolletas
    A,Como Tu CF
    A,Cuadrabondigas United
    B,Deportivo Mape
    ...
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


def leer_grupos_csv(ruta):
    if not os.path.exists(ruta):
        raise SystemExit(f"Archivo no encontrado: {ruta}")
    grupos = {}  # {grupo: [nombre_equipo, ...]}
    with open(ruta, encoding="utf-8-sig") as f:
        contenido = f.read()
        sep = ";" if contenido.count(";") > contenido.count(",") else ","
        reader = csv.DictReader(io.StringIO(contenido), delimiter=sep)
        for fila in reader:
            norm = {k.strip().lower(): v.strip() for k, v in fila.items()}
            grupo  = (norm.get("grupo") or "").upper().strip()
            equipo = (norm.get("equipo") or norm.get("equip") or "").strip()
            if grupo and equipo:
                grupos.setdefault(grupo, []).append(equipo)
    return grupos


def round_robin(teams):
    """Genera una vuelta de liguilla. Devuelve lista de rondas."""
    n = len(teams)
    if n < 2:
        return []
    if n % 2 != 0:
        teams = list(teams) + [None]
        n += 1
    rondas = []
    fijo, rot = teams[0], list(teams[1:])
    for _ in range(n - 1):
        ronda = [(fijo, rot[0])]
        for j in range(1, n // 2):
            ronda.append((rot[j], rot[n - 1 - j]))
        rondas.append(ronda)
        rot = rot[-1:] + rot[:-1]
    return rondas


def main():
    parser = argparse.ArgumentParser(description="Genera calendario de Copa de la Liga")
    parser.add_argument("--grupos",         required=True, help="CSV con Grupo,Equipo")
    parser.add_argument("--jornada-inicio", type=int, default=1,
                        help="Jornada en la que empieza la Copa (default: 1)")
    parser.add_argument("--prueba",  action="store_true", help="Simula sin guardar")
    parser.add_argument("--reset",   action="store_true", help="Borra datos Copa existentes")
    args = parser.parse_args()

    sb     = get_supabase()
    grupos_csv = leer_grupos_csv(args.grupos)

    if not grupos_csv:
        raise SystemExit("El CSV de grupos está vacío o tiene formato incorrecto.")

    # Mapear nombres → IDs
    partics = sb.table("participantes").select("id, nombre").execute().data or []
    nombre_a_id = {p["nombre"]: p["id"] for p in partics}

    # Resolver IDs y reportar errores
    grupos_ids = {}   # {grupo: [participante_id, ...]}
    errores    = []
    for grupo, equipos in sorted(grupos_csv.items()):
        ids = []
        for eq in equipos:
            pid = nombre_a_id.get(eq)
            if pid:
                ids.append(pid)
            else:
                errores.append(f"Equipo '{eq}' del grupo {grupo} no encontrado en BD")
        grupos_ids[grupo] = ids

    if errores:
        print("Advertencias:")
        for e in errores:
            print(f"  ⚠  {e}")
        print()

    # Mostrar resumen de grupos
    total_equipos = sum(len(v) for v in grupos_ids.values())
    print(f"\nGrupos de la Copa ({len(grupos_ids)} grupos, {total_equipos} equipos):")
    for g, ids in sorted(grupos_ids.items()):
        id_nom = {v: k for k, v in nombre_a_id.items()}
        nombres = [id_nom.get(i, "?") for i in ids]
        print(f"  Grupo {g} ({len(ids)} equipos): {', '.join(nombres)}")

    # Generar calendario
    registros_grupos = []
    registros_cal    = []
    jornada_actual   = args.jornada_inicio

    for grupo in sorted(grupos_ids):
        ids   = grupos_ids[grupo]
        rondas = round_robin(ids)

        for ronda in rondas:
            for local, visitante in ronda:
                if local and visitante:
                    registros_cal.append({
                        "jornada":      jornada_actual,
                        "grupo":        grupo,
                        "local_id":     local,
                        "visitante_id": visitante,
                        "es_neutral":   False,
                    })
            jornada_actual += 1

        for pid in ids:
            registros_grupos.append({"grupo": grupo, "participante_id": pid})

    print(f"\nCalendario Copa generado:")
    print(f"  Partidos : {len(registros_cal)}")
    print(f"  Jornadas : {args.jornada_inicio} – {jornada_actual - 1}")

    if args.prueba:
        id_nom = {v: k for k, v in nombre_a_id.items()}
        print("\nMuestra (primeros 8 partidos):")
        for r in registros_cal[:8]:
            loc = id_nom.get(r["local_id"], "?")
            vis = id_nom.get(r["visitante_id"], "?")
            print(f"  J{r['jornada']:2d} Grupo {r['grupo']}: {loc:<25} vs  {vis}")
        print("\n[PRUEBA] No se ha guardado nada.")
        return

    if args.reset:
        print("\nBorrando datos Copa existentes…")
        sb.table("copa_calendario").delete().gt("id", 0).execute()
        sb.table("copa_grupos").delete().gt("id", 0).execute()
        print("  Borrado.\n")

    print("Guardando grupos…")
    sb.table("copa_grupos").upsert(registros_grupos, on_conflict="grupo,participante_id").execute()

    print("Guardando calendario…")
    batch = 100
    for i in range(0, len(registros_cal), batch):
        sb.table("copa_calendario").insert(registros_cal[i:i+batch]).execute()

    print(f"\nCopa de la Liga configurada correctamente.")
    print(f"Los resultados se calculan con los puntos de las jornadas {args.jornada_inicio}–{jornada_actual-1}.")


if __name__ == "__main__":
    main()
