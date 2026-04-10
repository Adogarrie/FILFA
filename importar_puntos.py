"""
Fase 2 - Puntuaciones de LaLiga Fantasy
Importa los puntos de cada jornada y los guarda en Supabase.

La API de LaLiga Fantasy Marca requiere autenticacion y no es publica.
El metodo mas fiable es importar desde CSV copiando los datos de la app.

Uso:
    python dazn_puntuaciones.py --jornada 15 --csv puntos.csv
    python dazn_puntuaciones.py --jornada 15 --prueba --csv puntos.csv

Formato del CSV (ver instrucciones al final del archivo):
    Nombre,Puntos
    Bellingham,18
    Vinicius,22
"""

import sys
import io
import os
import csv
import json
import argparse
from dotenv import load_dotenv

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")


# ── Importacion desde CSV ──────────────────────────────────────

def obtener_puntos_csv(ruta_csv: str) -> dict[str, int]:
    """
    Lee un CSV con columnas Nombre,Puntos.
    Acepta punto y coma o coma como separador, y cualquier combinacion de
    nombres de columna (nombre/jugador/player/name y puntos/points/pts).
    """
    if not os.path.exists(ruta_csv):
        raise SystemExit(f"No se encontro el archivo: {ruta_csv}")

    puntos = {}
    with open(ruta_csv, encoding="utf-8-sig") as f:
        contenido = f.read()
        sep = ";" if contenido.count(";") > contenido.count(",") else ","
        reader = csv.DictReader(io.StringIO(contenido), delimiter=sep)
        for fila in reader:
            norm = {k.strip().lower(): v.strip() for k, v in fila.items()}
            nombre = (
                norm.get("nombre") or norm.get("jugador") or
                norm.get("player") or norm.get("name") or ""
            ).strip()
            pts_raw = (
                norm.get("puntos") or norm.get("points") or
                norm.get("pts") or "0"
            ).strip()
            if nombre:
                try:
                    puntos[nombre] = int(float(pts_raw))
                except ValueError:
                    print(f"  Advertencia: puntos invalidos para '{nombre}': '{pts_raw}'")

    print(f"  CSV leido: {len(puntos)} jugadores")
    return puntos


# ── Supabase ───────────────────────────────────────────────────

def get_supabase():
    try:
        from supabase import create_client
        return create_client(SUPABASE_URL, SUPABASE_KEY)
    except Exception as e:
        raise SystemExit(f"Error conectando a Supabase: {e}")


def guardar_puntos(sb, jornada: int, puntos: dict[str, int]) -> tuple[int, list[str]]:
    """Guarda puntos en Supabase. Devuelve (guardados, lista_sin_match)."""
    jugadores_db = sb.table("jugadores").select("id, nombre").execute().data
    nombre_a_id  = {j["nombre"]: j["id"] for j in jugadores_db}

    registros = []
    sin_match = []
    for nombre, pts in puntos.items():
        jid = nombre_a_id.get(nombre)
        if jid:
            registros.append({"jugador_id": jid, "jornada": jornada, "puntos": pts})
        else:
            sin_match.append(nombre)

    if registros:
        sb.table("puntuaciones_jornada").upsert(
            registros, on_conflict="jugador_id,jornada"
        ).execute()

    return len(registros), sin_match


def calcular_clasificacion(sb, jornada: int) -> int:
    """Suma puntos de titulares de cada participante y actualiza clasificacion."""
    alineaciones = (
        sb.table("alineaciones")
        .select("participante_id, jugador_id")
        .eq("jornada", jornada)
        .eq("titular", True)
        .execute().data
    )
    pts_map = {
        p["jugador_id"]: p["puntos"]
        for p in sb.table("puntuaciones_jornada")
        .select("jugador_id, puntos")
        .eq("jornada", jornada)
        .execute().data
    }

    totales: dict[str, int] = {}
    for a in alineaciones:
        pid = a["participante_id"]
        totales[pid] = totales.get(pid, 0) + pts_map.get(a["jugador_id"], 0)

    registros = [
        {"participante_id": pid, "jornada": jornada, "puntos_jornada": pts}
        for pid, pts in totales.items()
    ]
    if registros:
        sb.table("clasificacion").upsert(
            registros, on_conflict="participante_id,jornada"
        ).execute()

    return len(registros)


# ── Modo prueba ────────────────────────────────────────────────

def modo_prueba(jornada: int, puntos: dict[str, int]):
    top = sorted(puntos.items(), key=lambda x: -x[1])[:25]
    print(f"\n{'='*50}")
    print(f"TOP 25 - JORNADA {jornada}")
    print(f"{'='*50}")
    print(f"{'Jugador':<30} {'Puntos':>6}")
    print("-" * 50)
    for nombre, pts in top:
        print(f"{nombre:<30} {pts:>6}")
    print(f"{'='*50}")
    print(f"Total jugadores en el CSV: {len(puntos)}")


# ── Main ───────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Importa puntos de una jornada a Supabase")
    parser.add_argument("--jornada", type=int, required=True, help="Numero de jornada")
    parser.add_argument("--csv",     type=str, required=True, help="Ruta al CSV con Nombre,Puntos")
    parser.add_argument("--prueba",  action="store_true",     help="Solo muestra datos, no guarda")
    args = parser.parse_args()

    print(f"\nJornada {args.jornada} - importando desde {args.csv}\n")

    puntos = obtener_puntos_csv(args.csv)

    if not puntos:
        print("El CSV esta vacio o no tiene el formato correcto.")
        print("Formato esperado: Nombre,Puntos (una fila por jugador)")
        return

    if args.prueba or not SUPABASE_URL:
        modo_prueba(args.jornada, puntos)
        return

    print("Guardando en Supabase...")
    sb = get_supabase()

    guardados, sin_match = guardar_puntos(sb, args.jornada, puntos)
    print(f"  Jugadores guardados:    {guardados}")
    if sin_match:
        print(f"  Sin coincidencia en BD: {len(sin_match)}")
        print(f"  (Revisa que los nombres coincidan con los de Transfermarkt)")
        print(f"  Ejemplos: {', '.join(sin_match[:5])}")

    calculados = calcular_clasificacion(sb, args.jornada)
    print(f"  Participantes actualizados: {calculados}")
    print("\nJornada procesada correctamente.")


if __name__ == "__main__":
    main()


# ═══════════════════════════════════════════════════════════════
# COMO EXPORTAR LOS PUNTOS DESDE LALIGA FANTASY
# ═══════════════════════════════════════════════════════════════
#
# En la app de LaLiga Fantasy (fantasy.laliga.com):
#   1. Ve a "Estadisticas" -> "Jugadores"
#   2. Filtra por la jornada que quieras
#   3. Copia la tabla (Ctrl+A, Ctrl+C) y pega en Excel/Google Sheets
#   4. Exporta como CSV con columnas Nombre y Puntos
#
# O crea el CSV directamente en cualquier editor de texto:
#
#   Nombre,Puntos
#   Bellingham,18
#   Vinicius,22
#   Lewandowski,15
#   Ter Stegen,10
#   ...
#
# NOTA SOBRE NOMBRES:
# Los nombres en el CSV deben coincidir con los de Transfermarkt
# (que es lo que guarda el script transfermarkt_scraper.py en la BD).
# Si hay discrepancias, el script avisara de los jugadores sin coincidencia.
# ═══════════════════════════════════════════════════════════════
