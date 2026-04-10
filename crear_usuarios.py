"""
Crea un usuario en la tabla 'usuarios' por cada equipo (participante).
  - username  = nombre del equipo
  - password  = nombre del equipo  (el admin debe cambiarlas luego)

También crea el usuario administrador.

Uso:
    python crear_usuarios.py                  # crea usuarios nuevos
    python crear_usuarios.py --reset          # borra todos y los recrea
    python crear_usuarios.py --admin-pass X   # contraseña del admin (por defecto: admin1234)
"""

import sys, io, os, argparse
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from dotenv import load_dotenv
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")


def get_supabase():
    from supabase import create_client
    return create_client(SUPABASE_URL, SUPABASE_KEY)


def main():
    parser = argparse.ArgumentParser(description="Crea usuarios para cada equipo")
    parser.add_argument("--reset",      action="store_true", help="Borra todos los usuarios antes de crear")
    parser.add_argument("--admin-pass", default="admin1234",  help="Contraseña del admin (por defecto: admin1234)")
    args = parser.parse_args()

    sb = get_supabase()

    if args.reset:
        print("Borrando usuarios existentes…")
        sb.table("usuarios").delete().gt("id", 0).execute()
        print("  Borrado.\n")

    # Obtener participantes
    participantes = sb.table("participantes").select("id, nombre").order("nombre").execute().data or []
    if not participantes:
        print("No hay participantes en la BD. Añade equipos primero.")
        return

    registros = []

    # Un usuario por equipo
    for p in participantes:
        registros.append({
            "username":        p["nombre"],
            "password":        p["nombre"],   # contraseña inicial = nombre
            "participante_id": p["id"],
            "is_admin":        False,
        })

    # Usuario admin
    registros.append({
        "username":        "admin",
        "password":        args.admin_pass,
        "participante_id": None,
        "is_admin":        True,
    })

    print(f"Creando {len(registros)} usuarios…\n")
    print(f"  {'Usuario':<30} {'Contraseña inicial':<30} {'Admin'}")
    print(f"  {'-'*70}")
    for r in registros:
        print(f"  {r['username']:<30} {r['password']:<30} {'✓' if r['is_admin'] else ''}")

    # Insertar (upsert por si ya existen)
    sb.table("usuarios").upsert(registros, on_conflict="username").execute()

    print(f"\n✓ Usuarios creados correctamente.")
    print(f"\n  IMPORTANTE: Cambia las contraseñas desde el panel de admin")
    print(f"  o directamente en Supabase Dashboard → Table Editor → usuarios")
    print(f"\n  Acceso admin:")
    print(f"    Usuario:    admin")
    print(f"    Contraseña: {args.admin_pass}")


if __name__ == "__main__":
    main()
