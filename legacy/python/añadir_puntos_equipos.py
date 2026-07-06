"""
Añade puntos de jornada a los equipos (participantes) de cada división.

Uso:
    # Modo interactivo — pide puntos para cada equipo
    python añadir_puntos_equipos.py --jornada 15

    # Solo una división
    python añadir_puntos_equipos.py --jornada 15 --division Primera

    # Desde CSV (Nombre,Puntos)
    python añadir_puntos_equipos.py --jornada 15 --csv puntos_j15.csv

    # Simula sin guardar
    python añadir_puntos_equipos.py --jornada 15 --prueba

Formato CSV:
    Nombre,Puntos
    Marcos,42
    Luisa,38
"""

import sys
import io
import os
import csv
import argparse

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from dotenv import load_dotenv
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")


# ── Supabase ───────────────────────────────────────────────────

def get_supabase():
    try:
        from supabase import create_client
        return create_client(SUPABASE_URL, SUPABASE_KEY)
    except Exception as e:
        raise SystemExit(f"Error conectando a Supabase: {e}")


def cargar_participantes(sb, division: str | None) -> list[dict]:
    """Devuelve participantes con su nombre de división."""
    query = sb.table("participantes").select("id, nombre, division_id, divisiones(nombre)").order("nombre")

    if division:
        div_res = sb.table("divisiones").select("id").eq("nombre", division).execute()
        if not div_res.data:
            raise SystemExit(f"División '{division}' no encontrada en la base de datos.")
        query = query.eq("division_id", div_res.data[0]["id"])

    res = query.execute()
    return res.data or []


# ── Puntos desde CSV ───────────────────────────────────────────

def leer_csv(ruta: str) -> dict[str, int]:
    if not os.path.exists(ruta):
        raise SystemExit(f"Archivo no encontrado: {ruta}")

    puntos = {}
    with open(ruta, encoding="utf-8-sig") as f:
        contenido = f.read()
        sep = ";" if contenido.count(";") > contenido.count(",") else ","
        reader = csv.DictReader(io.StringIO(contenido), delimiter=sep)
        for fila in reader:
            norm = {k.strip().lower(): v.strip() for k, v in fila.items()}
            nombre = (norm.get("nombre") or norm.get("equipo") or norm.get("name") or "").strip()
            pts_raw = (norm.get("puntos") or norm.get("points") or norm.get("pts") or "0").strip()
            if nombre:
                try:
                    puntos[nombre] = int(float(pts_raw))
                except ValueError:
                    print(f"  Advertencia: puntos inválidos para '{nombre}': '{pts_raw}'")
    print(f"  CSV leído: {len(puntos)} equipos")
    return puntos


# ── Modo interactivo ───────────────────────────────────────────

def pedir_puntos_interactivo(participantes: list[dict]) -> dict[str, int]:
    """Pide puntos por teclado para cada equipo agrupado por división."""
    # Agrupar por división
    by_div: dict[str, list] = {}
    for p in participantes:
        div_name = (p.get("divisiones") or {}).get("nombre", "Sin división")
        by_div.setdefault(div_name, []).append(p)

    print("\nIntroduce los puntos de la jornada para cada equipo.")
    print("(Deja vacío y pulsa Enter para no modificar ese equipo)\n")

    puntos_map: dict[str, int] = {}
    for div_name in sorted(by_div):
        print(f"── {div_name} División ──────────────────────────")
        for p in by_div[div_name]:
            while True:
                try:
                    val = input(f"  {p['nombre']:<25} pts: ").strip()
                    if val == "":
                        break
                    puntos_map[p["id"]] = int(val)
                    break
                except ValueError:
                    print("    Introduce un número entero.")

    return puntos_map


# ── Guardar ────────────────────────────────────────────────────

def guardar(sb, jornada: int, puntos_map: dict[str, int]) -> int:
    registros = [
        {"participante_id": pid, "jornada": jornada, "puntos_jornada": pts}
        for pid, pts in puntos_map.items()
    ]
    sb.table("clasificacion").upsert(
        registros, on_conflict="participante_id,jornada"
    ).execute()
    return len(registros)


# ── Resumen ────────────────────────────────────────────────────

def mostrar_resumen(jornada: int, puntos_map: dict[str, int], participantes: list[dict]):
    id_a_nombre = {p["id"]: p["nombre"] for p in participantes}
    print(f"\n{'='*40}")
    print(f"  Jornada {jornada} — resumen")
    print(f"{'='*40}")
    print(f"  {'Equipo':<25} {'Pts':>5}")
    print(f"  {'-'*32}")
    for pid, pts in sorted(puntos_map.items(), key=lambda x: -x[1]):
        nombre = id_a_nombre.get(pid, pid)
        print(f"  {nombre:<25} {pts:>5}")
    print(f"{'='*40}")


# ── Main ───────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Añade puntos de jornada a los equipos de una división"
    )
    parser.add_argument("--jornada",   type=int, required=True,
                        help="Número de jornada (1-38)")
    parser.add_argument("--division",  choices=["Primera", "Segunda"],
                        help="Filtrar por división (por defecto: ambas)")
    parser.add_argument("--csv",       type=str,
                        help="CSV con columnas Nombre,Puntos")
    parser.add_argument("--prueba",    action="store_true",
                        help="Muestra el resultado sin guardar en la BD")
    args = parser.parse_args()

    if not SUPABASE_URL:
        raise SystemExit("SUPABASE_URL no definida en .env")

    sb = get_supabase()
    participantes = cargar_participantes(sb, args.division)

    if not participantes:
        raise SystemExit("No se encontraron participantes en la base de datos.")

    # Construir mapa id → puntos
    puntos_map: dict[str, int] = {}

    if args.csv:
        puntos_csv = leer_csv(args.csv)
        id_a_nombre = {p["nombre"]: p["id"] for p in participantes}
        for nombre, pts in puntos_csv.items():
            pid = id_a_nombre.get(nombre)
            if pid:
                puntos_map[pid] = pts
            else:
                # Búsqueda case-insensitive
                coincidencias = [
                    p for p in participantes
                    if p["nombre"].lower() == nombre.lower()
                ]
                if coincidencias:
                    puntos_map[coincidencias[0]["id"]] = pts
                else:
                    print(f"  Advertencia: equipo '{nombre}' no encontrado en BD")
    else:
        puntos_map = pedir_puntos_interactivo(participantes)

    if not puntos_map:
        print("No hay puntos que guardar.")
        return

    mostrar_resumen(args.jornada, puntos_map, participantes)

    if args.prueba:
        print("\n[PRUEBA] Simulación completada — no se ha guardado nada.")
        return

    guardados = guardar(sb, args.jornada, puntos_map)
    print(f"\nGuardados correctamente: {guardados} registros para la jornada {args.jornada}.")


if __name__ == "__main__":
    main()


# ═══════════════════════════════════════════════════════════════
# EJEMPLOS DE USO
# ═══════════════════════════════════════════════════════════════
#
# Modo interactivo (ambas divisiones):
#   python añadir_puntos_equipos.py --jornada 15
#
# Solo Primera División:
#   python añadir_puntos_equipos.py --jornada 15 --division Primera
#
# Desde CSV:
#   python añadir_puntos_equipos.py --jornada 15 --csv puntos_j15.csv
#
# Formato CSV:
#   Nombre,Puntos
#   Marcos,42
#   Luisa,38
#   Pablo,25
#
# Simular sin guardar:
#   python añadir_puntos_equipos.py --jornada 15 --prueba
# ═══════════════════════════════════════════════════════════════
