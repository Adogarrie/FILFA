"""
Carga los jugadores del cache de Transfermarkt en la tabla 'jugadores' de Supabase.

Uso:
    python cargar_jugadores.py                       # carga jugadores_cache.json
    python cargar_jugadores.py --cache otro.json     # carga otro archivo
    python cargar_jugadores.py --prueba              # muestra sin guardar
"""

import sys
import io
import os
import json
import re
import argparse
from dotenv import load_dotenv

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")
CACHE_FILE   = "jugadores_cache.json"

POSICIONES_VALIDAS = {"POR", "DEF", "MED", "DEL"}


def valor_a_numero(texto: str) -> float:
    """Convierte '12.000.000 EUR' o '800.000 EUR' a float."""
    texto = texto.replace(" EUR", "").replace(".", "").replace(",", ".").strip()
    try:
        return float(texto)
    except ValueError:
        return 0.0


def cargar_cache(ruta: str) -> list[dict]:
    with open(ruta, encoding="utf-8") as f:
        return json.load(f)


def preparar_registros(jugadores_raw: list[dict]) -> list[dict]:
    registros = []
    for j in jugadores_raw:
        posicion = j.get("posicion", "N/D")
        if posicion not in POSICIONES_VALIDAS:
            continue  # Omitir jugadores sin posicion valida

        valor = valor_a_numero(j.get("valor", "0"))

        registros.append({
            "nombre":        j["nombre"],
            "equipo":        j["equipo"],
            "posicion":      posicion,
            "valor_mercado": valor,
            "url_tm":        j.get("url", ""),
            "activo":        True,
        })
    return registros


def get_supabase():
    from supabase import create_client
    return create_client(SUPABASE_URL, SUPABASE_KEY)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache",  default=CACHE_FILE, help="Ruta al JSON del cache")
    parser.add_argument("--prueba", action="store_true", help="Solo muestra, no guarda")
    args = parser.parse_args()

    if not os.path.exists(args.cache):
        print(f"No se encontro el archivo: {args.cache}")
        print("Ejecuta primero: python transfermarkt_scraper.py --prueba")
        return

    print(f"Leyendo cache: {args.cache}")
    raw = cargar_cache(args.cache)
    print(f"  Jugadores en cache: {len(raw)}")

    registros = preparar_registros(raw)
    omitidos  = len(raw) - len(registros)
    print(f"  Listos para subir: {len(registros)}  |  Omitidos (sin posicion): {omitidos}")

    if args.prueba:
        print("\nPrimeros 10 registros:")
        for r in registros[:10]:
            print(f"  {r['nombre']:<30} {r['equipo']:<20} {r['posicion']}  {r['valor_mercado']:>14,.0f} EUR")
        return

    if not SUPABASE_URL or not SUPABASE_KEY:
        print("\nSupabase no configurado. Revisa el .env")
        return

    sb = get_supabase()
    # Comprobar si la tabla ya tiene datos
    existentes = sb.table("jugadores").select("id", count="exact").execute()
    n_existentes = existentes.count or 0

    if n_existentes > 0:
        print(f"\nLa tabla ya tiene {n_existentes} jugadores.")
        resp = input("Borrar y recargar desde cero? [s/N]: ").strip().lower()
        if resp == "s":
            sb.table("jugadores").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
            print("  Tabla vaciada.")
        else:
            print("Cancelado.")
            return

    print("\nSubiendo a Supabase...")

    # Subir en bloques de 200 para no exceder limites
    BLOQUE = 200
    total_ok = 0
    for i in range(0, len(registros), BLOQUE):
        bloque = registros[i:i + BLOQUE]
        sb.table("jugadores").insert(bloque).execute()
        total_ok += len(bloque)
        print(f"  Bloque {i//BLOQUE + 1}: {len(bloque)} jugadores subidos")

    print(f"\nTotal cargado en Supabase: {total_ok} jugadores")
    print("Listo. Ya puedes cargar participantes y plantillas.")


if __name__ == "__main__":
    main()
