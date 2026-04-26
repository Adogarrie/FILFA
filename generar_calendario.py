"""
Genera el calendario de partidos para cada división y lo inserta en Supabase.

Estructura de jornadas de LaLiga Fantasy (38 jornadas totales):
  ┌─────────────┬──────────────────────────────────────────────────────┐
  │ Jornadas    │ Competiciones activas                                │
  ├─────────────┼──────────────────────────────────────────────────────┤
  │ 1 – 7       │ Primera (ida), Segunda (vuelta 1)                    │
  │ 8 – 11      │ Primera (ida), Segunda (vuelta 2 — parte 1)          │
  │ 12 – 13     │ Primera (ida, fin)                                   │
  │ 14 – 17     │ Torneo de Navidad (sin Liga)                         │
  │ 18 – 20     │ Primera (vuelta), Segunda (vuelta 2 — parte 2)       │
  │ 21 – 23     │ Primera (vuelta)                                     │
  │ 24 – 30     │ Primera (vuelta), Segunda (vuelta 3 neutral)         │
  │ 31 – 37     │ Copa de la Liga                                      │
  │ 38          │ Liga Fantástica (solo puntos)                        │
  └─────────────┴──────────────────────────────────────────────────────┘

Primera División (14 equipos, ida+vuelta):
  - Ida:    13 rondas → jornadas LaLiga  1 – 13
  - Vuelta: 13 rondas → jornadas LaLiga 18 – 30

Segunda División (8 equipos, 3 vueltas):
  - Vuelta 1 (local sorteo):    7 rondas → jornadas  1 –  7
  - Vuelta 2 (invertida):       7 rondas → jornadas  8 – 11 + 18 – 20
  - Vuelta 3 (neutral):         7 rondas → jornadas 24 – 30

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

# ── Mapping de jornadas ────────────────────────────────────────
# Primera División: 14 equipos → 13 rondas por vuelta
PRIMERA_IDA    = list(range(1,  14))   # jornadas  1-13
PRIMERA_VUELTA = list(range(18, 31))   # jornadas 18-30

# Segunda División: 8 equipos → 7 rondas por vuelta
SEGUNDA_V1 = list(range(1,  8))                        # jornadas  1-7
SEGUNDA_V2 = list(range(8,  12)) + list(range(18, 21)) # jornadas  8-11 + 18-20
SEGUNDA_V3 = list(range(24, 31))                       # jornadas 24-30


# ── Algoritmo round-robin ──────────────────────────────────────

def round_robin_una_vuelta(teams: list) -> list[list[tuple]]:
    """
    Genera una vuelta completa (todos contra todos).
    Devuelve lista de rondas; cada ronda = lista de (local_idx, visitante_idx).
    Si el número de equipos es impar, añade un bye (None).
    """
    n = len(teams)
    if n % 2 != 0:
        teams = list(teams) + [None]
        n += 1

    rondas = []
    fijo = teams[0]
    rotando = list(teams[1:])

    for _ in range(n - 1):
        ronda = [(fijo, rotando[0])]
        for j in range(1, n // 2):
            ronda.append((rotando[j], rotando[n - 1 - j]))
        rondas.append(ronda)
        rotando = rotando[-1:] + rotando[:-1]   # rotar a la derecha

    return rondas


def generar_primera(equipos: list) -> list[dict]:
    """
    Ida (jornadas 1-13) + Vuelta invertida (jornadas 18-30).
    """
    ids = [e["id"] for e in equipos]
    ida    = round_robin_una_vuelta(ids)
    vuelta = [[(b, a) for a, b in r] for r in ida]

    n_rondas = len(ida)
    if n_rondas > len(PRIMERA_IDA):
        raise SystemExit(
            f"Primera División tiene {n_rondas} rondas pero solo hay "
            f"{len(PRIMERA_IDA)} jornadas disponibles (1-13). "
            f"¿Hay más de 14 equipos?"
        )

    fixtures = []
    for i, ronda in enumerate(ida):
        j = PRIMERA_IDA[i]
        for local, visitante in ronda:
            if local and visitante:
                fixtures.append({"jornada": j, "local_id": local,
                                  "visitante_id": visitante, "es_neutral": False})

    for i, ronda in enumerate(vuelta):
        j = PRIMERA_VUELTA[i]
        for local, visitante in ronda:
            if local and visitante:
                fixtures.append({"jornada": j, "local_id": local,
                                  "visitante_id": visitante, "es_neutral": False})

    return fixtures


def generar_segunda(equipos: list) -> list[dict]:
    """
    3 vueltas con mapping de jornadas específico:
      Vuelta 1 (local sorteo)  → jornadas  1-7
      Vuelta 2 (invertida)     → jornadas  8-11 + 18-20
      Vuelta 3 (neutral)       → jornadas 24-30
    """
    ids = [e["id"] for e in equipos]
    v1_rondas = round_robin_una_vuelta(ids)
    v2_rondas = [[(b, a) for a, b in r] for r in v1_rondas]
    v3_rondas = v1_rondas   # mismo emparejamiento, campo neutral

    n_rondas = len(v1_rondas)
    for nombre, jornadas_map in [("vuelta 1", SEGUNDA_V1),
                                  ("vuelta 2", SEGUNDA_V2),
                                  ("vuelta 3", SEGUNDA_V3)]:
        if n_rondas > len(jornadas_map):
            raise SystemExit(
                f"Segunda División {nombre} tiene {n_rondas} rondas pero "
                f"solo hay {len(jornadas_map)} jornadas disponibles. "
                f"¿Hay más de 8 equipos?"
            )

    fixtures = []

    for i, ronda in enumerate(v1_rondas):
        j = SEGUNDA_V1[i]
        for local, visitante in ronda:
            if local and visitante:
                fixtures.append({"jornada": j, "local_id": local,
                                  "visitante_id": visitante, "es_neutral": False})

    for i, ronda in enumerate(v2_rondas):
        j = SEGUNDA_V2[i]
        for local, visitante in ronda:
            if local and visitante:
                fixtures.append({"jornada": j, "local_id": local,
                                  "visitante_id": visitante, "es_neutral": False})

    for i, ronda in enumerate(v3_rondas):
        j = SEGUNDA_V3[i]
        for local, visitante in ronda:
            if local and visitante:
                fixtures.append({"jornada": j, "local_id": local,
                                  "visitante_id": visitante, "es_neutral": True})

    return fixtures


# ── Supabase ───────────────────────────────────────────────────

def get_supabase():
    try:
        from supabase import create_client
        return create_client(SUPABASE_URL, SUPABASE_KEY)
    except Exception as e:
        raise SystemExit(f"Error conectando a Supabase: {e}")


# ── Mostrar calendario ─────────────────────────────────────────

def mostrar_muestra(fixtures: list, id_a_nombre: dict, titulo: str, max_jornadas: int = 5):
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

    fix_primera = generar_primera(primera) if len(primera) >= 2 else []
    fix_segunda = generar_segunda(segunda) if len(segunda) >= 2 else []

    def jornadas_de(fix):
        return sorted({f["jornada"] for f in fix})

    print(f"\nCalendario generado:")
    if fix_primera:
        js = jornadas_de(fix_primera)
        print(f"  Primera División: {len(fix_primera)} partidos, jornadas {js[0]}-{js[-1]}")
        print(f"    Ida    (J1-J13):   {sum(1 for f in fix_primera if f['jornada'] <= 13)} partidos")
        print(f"    Vuelta (J18-J30):  {sum(1 for f in fix_primera if f['jornada'] >= 18)} partidos")
    if fix_segunda:
        js = jornadas_de(fix_segunda)
        print(f"  Segunda División: {len(fix_segunda)} partidos, jornadas distribuidas en {len(js)} rondas")
        print(f"    Vuelta 1  (J1-J7):          {sum(1 for f in fix_segunda if f['jornada'] <= 7)} partidos")
        print(f"    Vuelta 2  (J8-11, J18-20):  {sum(1 for f in fix_segunda if 8 <= f['jornada'] <= 11 or 18 <= f['jornada'] <= 20)} partidos")
        print(f"    Vuelta 3  (J24-J30, neutral):{sum(1 for f in fix_segunda if f['jornada'] >= 24)} partidos")

    id_a_nombre = {p["id"]: p["nombre"] for p in participantes}
    if fix_primera:
        mostrar_muestra(fix_primera, id_a_nombre, "Primera División — muestra")
    if fix_segunda:
        mostrar_muestra(fix_segunda, id_a_nombre, "Segunda División — muestra")

    if args.prueba:
        print("\n[PRUEBA] Simulación completa — no se ha guardado nada.")
        return

    divs = {d["nombre"]: d["id"] for d in (
        sb.table("divisiones").select("id, nombre").execute().data or []
    )}

    if args.reset:
        print("\nBorrando calendario existente...")
        sb.table("calendario").delete().gt("id", 0).execute()
        print("  Borrado.")

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
# ESTRUCTURA DE JORNADAS
# ═══════════════════════════════════════════════════════════════
#
# Primera División (14 equipos):
#   Ida:    jornadas  1-13  (13 partidos por equipo)
#   Vuelta: jornadas 18-30  (13 partidos por equipo)
#
# Segunda División (8 equipos):
#   Vuelta 1:  jornadas  1-7  (7 partidos, con localía)
#   Vuelta 2:  jornadas  8-11 + 18-20  (7 partidos, invertida)
#   Vuelta 3:  jornadas 24-30  (7 partidos, campo neutral)
#
# Torneo de Navidad: jornadas 14-17 (sin partidos de liga)
# Copa de la Liga:   jornadas 31-37
# Liga Fantástica:   suma de las 38 jornadas (sin H2H)
# ═══════════════════════════════════════════════════════════════
