"""
Fase 1 - Scraper de Transfermarkt para LaLiga
Obtiene jugadores, posiciones y valores de mercado y los vuelca a Google Sheets.
"""

import sys
import io
import time
import re
import requests
from bs4 import BeautifulSoup

# Forzar UTF-8 en la salida para evitar errores en Windows con emojis
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

# ── Configuracion ──────────────────────────────────────────────
CREDENTIALS_FILE = "credentials.json"
SPREADSHEET_NAME = "Fantasy LaLiga"      # Nombre exacto de tu Google Sheet
WORKSHEET_NAME   = "Jugadores"           # Pestana donde se escriben los datos

# Transfermarkt bloquea User-Agents genericos; este imita un navegador real
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept-Language":  "es-ES,es;q=0.9,en;q=0.8",
    "Accept":           "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Encoding":  "gzip, deflate, br",
    "Referer":          "https://www.transfermarkt.es/",
    "Connection":       "keep-alive",
}

# Equipos de LaLiga 2024-25
# Formato: (slug-en-la-url, id-numerico-de-transfermarkt, nombre-para-mostrar)
EQUIPOS_LALIGA = [
    ("fc-barcelona",           131,  "FC Barcelona"),
    ("real-madrid",            418,  "Real Madrid"),
    ("atletico-de-madrid",     13,   "Atletico de Madrid"),
    ("athletic-club",          621,  "Athletic Club"),
    ("real-sociedad",          681,  "Real Sociedad"),
    ("villarreal-cf",          1050, "Villarreal CF"),
    ("real-betis-balompie",    150,  "Real Betis"),
    ("rc-celta-de-vigo",       940,  "Celta de Vigo"),
    ("rcd-mallorca",           237,  "RCD Mallorca"),
    ("sevilla-fc",             368,  "Sevilla FC"),
    ("girona-fc",              12321,"Girona FC"),
    ("real-oviedo",          2497,  "Real Oviedo"),
    ("deportivo-alaves",       1108, "Deportivo Alaves"),
    ("rayo-vallecano",         367,  "Rayo Vallecano"),
    ("getafe-cf",              3709, "Getafe CF"),
    ("osasuna",                331,  "Osasuna"),
    ("ud-levante",             3368, "Levante UD"),
    ("fc-elche",     1531,  "Elche FC"),
    ("rcd-espanyol-barcelona", 714,  "RCD Espanyol"),
    ("valencia-cf",            1049, "Valencia CF"),
]

# Mapa de posiciones de Transfermarkt a abreviatura del fantasy
POSICIONES = {
    # Porteros
    "Portero":                  "POR",
    # Defensas
    "Defensa central":          "DEF",
    "Lateral derecho":          "DEF",
    "Lateral izquierdo":        "DEF",
    "Libero":                   "DEF",
    # Centrocampistas
    "Mediocentro": "MED",
    "Mediocentro ofensivo":           "MED",
    "Pivote":  "MED",
    "Interior derecho":         "MED",
    "Interior izquierdo":       "MED",
    # Delanteros
    "Extremo derecho":          "DEL",
    "Extremo izquierdo":        "DEL",
    "Mediapunta":               "DEL",
    "Delantero centro":         "DEL",
    "Segundo delantero":        "DEL",
    "Delantero":                "DEL",
}


# ── Scraping ───────────────────────────────────────────────────

def scrape_equipo(slug: str, tm_id: int, nombre: str) -> list[dict]:
    """Descarga la plantilla de un equipo desde Transfermarkt."""
    url = (
        f"https://www.transfermarkt.es/{slug}/kader/verein/{tm_id}"
        f"/saison_id/2025/plus/1"
    )
    try:
        resp = requests.get(url, headers=HEADERS, timeout=20)
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"  ERROR al descargar {nombre}: {e}")
        return []

    soup = BeautifulSoup(resp.text, "html.parser")

    # Transfermarkt puede servir una pagina de captcha/error
    if "Bitte beweise" in resp.text or "captcha" in resp.text.lower():
        print(f"  CAPTCHA detectado para {nombre} - omitiendo")
        return []

    tabla = soup.find("table", class_="items")
    if not tabla:
        print(f"  Tabla no encontrada para {nombre} (estructura HTML distinta)")
        return []

    jugadores = []
    for fila in tabla.find_all("tr", class_=["odd", "even"]):
        celdas = fila.find_all("td")
        if len(celdas) < 5:
            continue

        # Nombre: celda con clase 'hauptlink' dentro de la fila
        td_nombre = fila.find("td", class_="hauptlink")
        if not td_nombre:
            continue
        enlace = td_nombre.find("a", href=True)
        if not enlace:
            continue
        nombre_jugador = enlace.get_text(strip=True)
        if not nombre_jugador:
            continue
        url_jugador = "https://www.transfermarkt.es" + enlace["href"]

        # Posicion: texto de la segunda celda con clase 'zentriert' o la celda inline
        posicion = "N/D"
        for td in celdas:
            texto = td.get_text(strip=True)
            if texto in POSICIONES:
                posicion = POSICIONES[texto]
                break

        # Valor de mercado: ultima celda relevante con simbolo de moneda
        valor_raw = ""
        for td in reversed(celdas):
            texto = td.get_text(strip=True)
            if "mill" in texto or "Mil" in texto or "€" in texto:
                valor_raw = texto
                break
        valor = normalizar_valor(valor_raw) if valor_raw else "N/D"

        jugadores.append({
            "nombre":   nombre_jugador,
            "equipo":   nombre,
            "posicion": posicion,
            "valor":    valor,
            "url":      url_jugador,
        })

    print(f"  OK {nombre}: {len(jugadores)} jugadores")
    return jugadores


def normalizar_valor(texto: str) -> str:
    """Convierte '15,00 mill. EUR' o '500 mil EUR' a '15.000.000 EUR'."""
    texto = texto.replace("\xa0", "").replace(" ", "").strip()
    mill = re.search(r"([\d,]+)mill", texto, re.IGNORECASE)
    mil  = re.search(r"([\d,]+)[Mm]il[^l]", texto)
    if mill:
        num = float(mill.group(1).replace(",", "."))
        return f"{int(num * 1_000_000):,} EUR".replace(",", ".")
    if mil:
        num = float(mil.group(1).replace(",", "."))
        return f"{int(num * 1_000):,} EUR".replace(",", ".")
    return texto


# ── Google Sheets ──────────────────────────────────────────────

def conectar_sheets():
    """Devuelve la hoja de calculo configurada, creandola si no existe."""
    try:
        import gspread
        from google.oauth2.service_account import Credentials
    except ImportError:
        raise SystemExit("Instala las dependencias: pip install -r requirements.txt")

    scopes = [
        "https://www.googleapis.com/auth/spreadsheets",
        "https://www.googleapis.com/auth/drive",
    ]
    creds  = Credentials.from_service_account_file(CREDENTIALS_FILE, scopes=scopes)
    client = gspread.authorize(creds)

    # Intentar abrir; si no existe, crearla automaticamente
    try:
        spreadsheet = client.open(SPREADSHEET_NAME)
        print(f"  Hoja encontrada: '{SPREADSHEET_NAME}'")
    except gspread.exceptions.SpreadsheetNotFound:
        print(f"  Hoja '{SPREADSHEET_NAME}' no encontrada. Creandola...")
        spreadsheet = client.create(SPREADSHEET_NAME)
        # Compartir con el propio usuario para que pueda verla en Drive
        service_email = creds.service_account_email
        print(f"  Creada. Compartela con tu cuenta de Google si aun no puedes verla.")
        print(f"  (La cuenta de servicio es: {service_email})")

    # Obtener o crear la pestana
    try:
        ws = spreadsheet.worksheet(WORKSHEET_NAME)
    except gspread.exceptions.WorksheetNotFound:
        print(f"  Pestana '{WORKSHEET_NAME}' no encontrada. Creandola...")
        ws = spreadsheet.add_worksheet(title=WORKSHEET_NAME, rows=1000, cols=10)

    return ws


def volcar_a_sheets(ws, jugadores: list[dict]):
    ws.clear()
    cabecera = ["Nombre", "Equipo", "Posicion", "Valor de Mercado", "URL Transfermarkt"]
    filas = [cabecera] + [
        [j["nombre"], j["equipo"], j["posicion"], j["valor"], j["url"]]
        for j in jugadores
    ]
    ws.update("A1", filas)
    ws.format("A1:E1", {"textFormat": {"bold": True}})
    print(f"\nJugadores escritos en Google Sheets: {len(jugadores)}")


# ── Modo prueba (sin Google Sheets) ───────────────────────────

def modo_prueba(jugadores: list[dict]):
    """Imprime los primeros resultados en pantalla para verificar el scraping."""
    print(f"\n{'='*60}")
    print(f"RESULTADOS (primeros 20 de {len(jugadores)} jugadores)")
    print(f"{'='*60}")
    print(f"{'Nombre':<25} {'Equipo':<20} {'Pos':<5} {'Valor'}")
    print("-" * 60)
    for j in jugadores[:20]:
        print(f"{j['nombre']:<25} {j['equipo']:<20} {j['posicion']:<5} {j['valor']}")
    print(f"{'='*60}\n")


# ── Main ───────────────────────────────────────────────────────

def main():
    import argparse
    import json
    import os

    parser = argparse.ArgumentParser(description="Scraper de Transfermarkt para LaLiga")
    parser.add_argument("--prueba", action="store_true",
                        help="Modo prueba: muestra resultados en pantalla sin escribir en Sheets")
    parser.add_argument("--equipos", type=int, default=len(EQUIPOS_LALIGA),
                        help="Numero de equipos a procesar (por defecto: todos)")
    parser.add_argument("--solo-subir", action="store_true",
                        help="Salta el scraping y sube directamente el cache local a Sheets")
    args = parser.parse_args()

    CACHE_FILE = "jugadores_cache.json"

    # -- Scraping (se omite si --solo-subir) -----------------------
    if args.solo_subir and os.path.exists(CACHE_FILE):
        with open(CACHE_FILE, encoding="utf-8") as f:
            todos = json.load(f)
        print(f"Cache cargado: {len(todos)} jugadores")
    else:
        print("Scrapeando Transfermarkt...\n")
        todos = []
        for slug, tm_id, nombre in EQUIPOS_LALIGA[:args.equipos]:
            jugadores = scrape_equipo(slug, tm_id, nombre)
            todos.extend(jugadores)
            time.sleep(3)
        print(f"\nTotal jugadores recogidos: {len(todos)}")
        # Guardar cache para no tener que volver a scrapear si falla Sheets
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(todos, f, ensure_ascii=False, indent=2)
        print(f"Cache guardado en {CACHE_FILE}")

    if args.prueba or not todos:
        modo_prueba(todos)
        return

    # -- Subir a Google Sheets -------------------------------------
    print("\nConectando con Google Sheets...")
    try:
        ws = conectar_sheets()
        volcar_a_sheets(ws, todos)
    except FileNotFoundError:
        print(f"No se encontro '{CREDENTIALS_FILE}'.")
        print("Ejecuta con --prueba para ver los datos, o coloca el credentials.json en esta carpeta.")
        modo_prueba(todos)


if __name__ == "__main__":
    main()
