"""
Genera el calendario de partidos para cada división y lo inserta en Supabase.

  Primera División : todos contra todos, ida y vuelta  → 2*(n-1) jornadas
  Segunda División : todos contra todos, 3 vueltas     → 3*(n-1) jornadas
                     vuelta 1 = local definido por sorteo
                     vuelta 2 = local/visitante invertidos
                     vuelta 3 = campo neutral (es_neutral = true)

Cada jornada del calendario corresponde a la misma jornada de LaLiga Fantasy,
por lo que los puntos de clasificacion se usan directamente para calcular
goles y resultados.

Uso:
    python generar_calendario.py             # genera e inserta
    python generar_calendario.py --prueba    # muestra sin guardar
    python generar_calendario.py --reset     # borra el existente y regenera
"""

import sys
import io
import os
import argparse

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from dotenv import load_dotenv
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")


# ── Algoritmo round-robin ──────────────────────────────────────

def round_robin_una_vuelta(teams: list) -> list[list[tuple]]:
    """
    Genera una vuelta completa (todos contra todos).
    Devuelve lista de jornadas; cada jornada = lista de (local_idx, visitante_idx).
    Si el número de equipos es impar, añade un bye (None).
    """
    n = len(teams)
    if n % 2 != 0:
        teams = list(teams) + [None]
        n += 1

    jornadas = []
    fijo = teams[0]
    rotando = list(teams[1:])

    for _ in range(n - 1):
        jornada = [(fijo, rotando[0])]
        for j in range(1, n // 2):
            jornada.append((rotando[j], rotando[n - 1 - j]))  # n-1-j, no n-2-j
        jornadas.append(jornada)
        rotando = rotando[-1:] + rotando[:-1]   # rotar a la derecha

    return jornadas


def generar_primera(equipos: list) -> list[dict]:
    """Ida + vuelta (local/visitante se invierten en la vuelta)."""
    ids = [e["id"] for e in equipos]
    ida    = round_robin_una_vuelta(ids)
    vuelta = [[(b, a) for a, b in j] for j in ida]

    fixtures = []
    for num_j, jornada in enumerate(ida + vuelta, start=1):
        for local, visitante in jornada:
            if local and visitante:
                fixtures.append({
                    "jornada": num_j,
                    "local_id": local,
                    "visitante_id": visitante,
                    "es_neutral": False,
                })
    return fixtures


def generar_segunda(equipos: list) -> list[dict]:
    """
    3 vueltas:
      vuelta 1 → local definido por el sorteo del algoritmo
      vuelta 2 → se invierten local/visitante
      vuelta 3 → mismos emparejamientos que vuelta 1, campo neutral
    """
    ids = [e["id"] for e in equipos]
    vuelta1 = round_robin_una_vuelta(ids)
    vuelta2 = [[(b, a) for a, b in j] for j in vuelta1]
    vuelta3 = vuelta1   # mismo sorteo, pero neutral

    rondas = [
        (vuelta1, False),
        (vuelta2, False),
        (vuelta3, True),
    ]

    fixtures = []
    num_j = 1
    for jornadas, es_neutral in rondas:
        for jornada in jornadas:
            for local, visitante in jornada:
                if local and visitante:
                    fixtures.append({
                        "jornada": num_j,
                        "local_id": local,
                        "visitante_id": visitante,
                        "es_neutral": es_neutral,
                    })
            num_j += 1

    return fixtures


# ── Supabase ───────────────────────────────────────────────────

def get_supabase():
    try:
        from supabase import create_client
        return create_client(SUPABASE_URL, SUPABASE_KEY)
    except Exception as e:
        raise SystemExit(f"Error conectando a Supabase: {e}")


# ── Mostrar calendario ─────────────────────────────────────────

def mostrar_muestra(fixtures: list, id_a_nombre: dict, titulo: str, max_jornadas: int = 3):
    print(f"\n── {titulo} ──────────────────────────────────────")
    jornadas_visibles = sorted({f["jornada"] for f in fixtures})[:max_jornadas]
    for j in jornadas_visibles:
        print(f"  Jornada {j}:")
        for f in [f for f in fixtures if f["jornada"] == j]:
            loc  = id_a_nombre.get(f["local_id"], f["local_id"])
            vis  = id_a_nombre.get(f["visitante_id"], f["visitante_id"])
            flag = "  [NEUTRAL]" if f["es_neutral"] else ""
            print(f"    {loc:<22} vs  {vis:<22}{flag}")


# ── Main ───────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Genera el calendario de la liga fantasy")
    parser.add_argument("--prueba", action="store_true",
                        help="Muestra el calendario generado sin guardar en Supabase")
    parser.add_argument("--reset",  action="store_true",
                        help="Borra el calendario existente antes de insertar el nuevo")
    args = parser.parse_args()

    if not SUPABASE_URL:
        raise SystemExit("SUPABASE_URL no definida en .env")

    sb = get_supabase()

    # Cargar participantes con nombre de división
    participantes = sb.table("participantes").select(
        "id, nombre, division_id, divisiones(nombre)"
    ).order("nombre").execute().data or []

    if not participantes:
        raise SystemExit("No hay participantes en la base de datos.")

    def div_nombre(p):
        d = p.get("divisiones")
        return (d.get("nombre") if isinstance(d, dict) else None) or ""

    primera = [p for p in participantes if div_nombre(p) == "Primera"]
    segunda = [p for p in participantes if div_nombre(p) == "Segunda"]

    print(f"\nEquipos encontrados:")
    print(f"  Primera División ({len(primera)} equipos): {', '.join(p['nombre'] for p in primera)}")
    print(f"  Segunda División ({len(segunda)} equipos): {', '.join(p['nombre'] for p in segunda)}")

    if len(primera) < 2 and len(segunda) < 2:
        raise SystemExit("Se necesitan al menos 2 equipos por división.")

    # Generar fixtures
    fix_primera = generar_primera(primera) if len(primera) >= 2 else []
    fix_segunda = generar_segunda(segunda) if len(segunda) >= 2 else []

    def jornadas_de(fix):
        return len({f["jornada"] for f in fix})

    print(f"\nCalendario generado:")
    if fix_primera:
        print(f"  Primera División: {len(fix_primera)} partidos en {jornadas_de(fix_primera)} jornadas")
    if fix_segunda:
        print(f"  Segunda División: {len(fix_segunda)} partidos en {jornadas_de(fix_segunda)} jornadas")

    # Mostrar muestra
    id_a_nombre = {p["id"]: p["nombre"] for p in participantes}
    if fix_primera:
        mostrar_muestra(fix_primera, id_a_nombre, "Primera División — primeras 3 jornadas")
    if fix_segunda:
        mostrar_muestra(fix_segunda, id_a_nombre, "Segunda División — primeras 3 jornadas")

    if args.prueba:
        print("\n[PRUEBA] Simulación completa — no se ha guardado nada.")
        return

    # Obtener IDs de divisiones
    divs = {d["nombre"]: d["id"] for d in (
        sb.table("divisiones").select("id, nombre").execute().data or []
    )}

    if args.reset:
        print("\nBorrando calendario existente...")
        sb.table("calendario").delete().gt("id", 0).execute()
        print("  Borrado.")

    # Construir registros finales
    registros = []
    for f in fix_primera:
        registros.append({**f, "division_id": divs["Primera"]})
    for f in fix_segunda:
        registros.append({**f, "division_id": divs["Segunda"]})

    if not registros:
        print("No hay registros que insertar.")
        return

    print(f"\nInsertando {len(registros)} partidos en Supabase...")
    batch = 100
    for i in range(0, len(registros), batch):
        sb.table("calendario").insert(registros[i:i + batch]).execute()

    print(f"Calendario guardado correctamente.")
    print(f"\nPróximos pasos:")
    print(f"  1. Añade los puntos de cada jornada:")
    print(f"       python añadir_puntos_equipos.py --jornada N")
    print(f"  2. Consulta la tabla 'Liga' en la app para ver resultados.")


if __name__ == "__main__":
    main()


# ═══════════════════════════════════════════════════════════════
# REGLAS DEL SISTEMA DE LIGA
# ═══════════════════════════════════════════════════════════════
#
# Conversión puntos fantasy → goles:
#   0-35 pts   = 0 goles
#   36-44 pts  = 1 gol
#   45-53 pts  = 2 goles
#   54-62 pts  = 3 goles
#   63-71 pts  = 4 goles
#   ... (+1 gol cada 9 puntos desde 36)
#
# Bono de localía: el equipo local suma 5 puntos extra ANTES de convertir.
# En campo neutral (3.ª vuelta de Segunda) no hay bono.
#
# Puntos de liga: victoria=3, empate=1, derrota=0
#
# Para regenerar el calendario (p.ej. si cambian los participantes):
#   python generar_calendario.py --reset
# ═══════════════════════════════════════════════════════════════
