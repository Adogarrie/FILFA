"""
Actualiza los jugadores a una nueva temporada de LaLiga.

  1. Marca como inactivos (activo=false) todos los jugadores actuales.
  2. Carga los jugadores del jugadores_cache.json como activos.
  3. Los jugadores de temporadas anteriores que ya no estén en la caché
     quedan inactivos y no aparecen en el mercado, pero se conservan en
     la BD para mantener el historial de plantillas.

Flujo completo:
    # Paso 1: actualizar la caché con los jugadores de la nueva temporada
    python transfermarkt_scraper.py --prueba   # para verificar
    python transfermarkt_scraper.py            # guarda jugadores_cache.json

    # Paso 2: cargar en Supabase
    python actualizar_temporada.py
    python actualizar_temporada.py --prueba    # simula sin guardar

Uso:
    python actualizar_temporada.py
    python actualizar_temporada.py --prueba
"""

import sys, io, os, json, argparse
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from dotenv import load_dotenv
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")

CACHE = "jugadores_cache.json"

POSICIONES_VALIDAS = {"POR", "DEF", "MED", "DEL"}

POSICIONES_MAP = {
    "Portero":                  "POR",
    "Portero suplente":         "POR",
    "Defensa central":          "DEF",
    "Lateral derecho":          "DEF",
    "Lateral izquierdo":        "DEF",
    "Defensa":                  "DEF",
    "Centrocampista":           "MED",
    "Centrocampista defensivo": "MED",
    "Centrocampista ofensivo":  "MED",
    "Pivote":                   "MED",
    "Mediapunta":               "MED",
    "Extremo derecho":          "DEL",
    "Extremo izquierdo":        "DEL",
    "Delantero centro":         "DEL",
    "Delantero":                "DEL",
    "Segunda punta":            "DEL",
}

def mapear_posicion(pos_raw):
    """Acepta códigos ya mapeados (POR/DEF/MED/DEL) o nombres en español."""
    if pos_raw in POSICIONES_VALIDAS:
        return pos_raw
    return POSICIONES_MAP.get(pos_raw)


def get_supabase():
    from supabase import create_client
    return create_client(SUPABASE_URL, SUPABASE_KEY)


def main():
    parser = argparse.ArgumentParser(description="Actualiza jugadores a nueva temporada")
    parser.add_argument("--prueba", action="store_true", help="Simula sin guardar")
    args = parser.parse_args()

    if not os.path.exists(CACHE):
        raise SystemExit(f"No se encontró {CACHE}. Ejecuta primero transfermarkt_scraper.py")

    with open(CACHE, encoding="utf-8") as f:
        cache = json.load(f)

    print(f"Jugadores en caché: {len(cache)}\n")

    # Preparar registros
    registros = []
    sin_pos    = []
    for j in cache:
        pos_raw = j.get("posicion", "")
        pos = mapear_posicion(pos_raw)
        if not pos:
            sin_pos.append(f"  {j.get('nombre','?')} ({pos_raw})")
            continue
        try:
            valor_raw = str(j.get("valor", "0")).replace(" EUR", "").replace(".", "").replace(",", ".").strip()
            valor = float(valor_raw) if valor_raw else 0.0
        except ValueError:
            valor = 0.0
        registros.append({
            "nombre":        j["nombre"],
            "equipo":        j["equipo"],
            "posicion":      pos,
            "valor_mercado": valor,
            "url_tm":        j.get("url"),
            "activo":        True,
        })

    if sin_pos:
        print(f"Jugadores con posición no reconocida ({len(sin_pos)}) — se omiten:")
        for s in sin_pos[:10]:
            print(s)
        if len(sin_pos) > 10:
            print(f"  … y {len(sin_pos)-10} más")
        print()

    print(f"Jugadores válidos a cargar: {len(registros)}")

    if args.prueba:
        print("\nMuestra (primeros 5):")
        for r in registros[:5]:
            print(f"  {r['nombre']:<30} {r['equipo']:<25} {r['posicion']}  {r['valor_mercado']:,.0f}€")
        print("\n[PRUEBA] No se ha guardado nada.")
        return

    sb = get_supabase()

    # 1. Desactivar todos los jugadores existentes
    print("\nPaso 1: Desactivando jugadores de la temporada anterior…")
    sb.table("jugadores").update({"activo": False}).gt("valor_mercado", -1).execute()
    print("  Hecho.")

    # 2. Cargar nuevos jugadores (upsert por nombre+equipo → activo=True)
    print(f"Paso 2: Cargando {len(registros)} jugadores nuevos…")
    batch = 200
    cargados = 0
    for i in range(0, len(registros), batch):
        sb.table("jugadores").upsert(
            registros[i:i+batch],
            on_conflict="nombre,equipo"
        ).execute()
        cargados += len(registros[i:i+batch])
        print(f"  {cargados}/{len(registros)}…")

    print(f"\nTemporada actualizada correctamente.")
    print(f"  Jugadores cargados : {len(registros)}")
    print(f"  Jugadores sin pos  : {len(sin_pos)}")
    print(f"\nNOTA: Los jugadores de la temporada anterior que no están")
    print(f"en la nueva caché han quedado marcados como inactivos.")


if __name__ == "__main__":
    main()
