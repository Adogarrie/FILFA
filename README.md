# Fantasy LaLiga — Guía de instalación y uso

App para gestionar tu liga fantasy de LaLiga: mercado de jugadores, plantillas, clasificación y puntuaciones manuales por jornada.

---

## Estado actual del proyecto

| Fase | Descripción | Estado |
|---|---|---|
| 1 | Scraper de jugadores y valores (Transfermarkt) | ✅ Funcionando |
| 2 | Puntuaciones por jornada | ⏸ Manual via CSV (automático pendiente) |
| 3 | App web (clasificación, plantillas, mercado) | ✅ Funcionando |

---

## Requisitos previos

- Python 3.10 o superior
- Un navegador moderno (Chrome, Firefox, Edge)
- Cuenta gratuita en [Supabase](https://supabase.com)
- Cuenta de Google (para Google Sheets, solo Fase 1)

---

## Estructura del proyecto

```
FILFA/
├── index.html                 # App web (abrir en el navegador)
├── transfermarkt_scraper.py   # Fase 1: jugadores y valores de mercado
├── importar_puntos.py         # Fase 2: importar puntos desde CSV manual
├── supabase_schema.sql        # Base de datos (ejecutar en Supabase)
├── requirements.txt           # Dependencias Python
└── .env.example               # Plantilla de configuración
```

---

## Paso 1 — Ver la app en modo demo

No necesitas configurar nada. Abre `index.html` directamente en el navegador:

- En Windows: doble clic sobre `index.html`
- O arrastra el archivo a la barra de direcciones del navegador

Verás la app con datos de ejemplo: clasificación, plantillas y mercado.

---

## Paso 2 — Configurar Supabase (base de datos real)

1. Crea un proyecto gratuito en [supabase.com](https://supabase.com).

2. Ve a **SQL Editor** en el panel de Supabase y pega el contenido de `supabase_schema.sql`. Haz clic en **Run**.

3. Ve a **Settings → API** y copia:
   - **Project URL** → `SUPABASE_URL`
   - **anon public key** → `SUPABASE_KEY`
   - **service_role key** → `SUPABASE_SERVICE_KEY` (solo para los scripts Python)

4. Copia `.env.example` como `.env` y rellena los valores:

```bash
cp .env.example .env
```

```env
SUPABASE_URL=https://xxxxxxxxxxxx.supabase.co
SUPABASE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
SUPABASE_SERVICE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

5. Edita `index.html` y sustituye las dos constantes al inicio del `<script>`:

```js
const SUPABASE_URL = 'https://xxxxxxxxxxxx.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
```

---

## Paso 3 — Instalar dependencias Python

```bash
pip install -r requirements.txt
```

---

## Paso 4 — Fase 1: Scraper de jugadores (Transfermarkt)

Este script descarga todos los jugadores de LaLiga con su posición y valor de mercado.

### 4.1 Configurar Google Cloud (para volcar datos a Google Sheets)

1. Ve a [console.cloud.google.com](https://console.cloud.google.com) y crea un proyecto nuevo.
2. Activa las APIs: **Google Sheets API** y **Google Drive API**.
3. Ve a **Credenciales → Crear credenciales → Cuenta de servicio**.
4. Descarga el JSON y renómbralo `credentials.json`. Colócalo en la carpeta `FILFA/`.
5. Crea una hoja en Google Drive llamada `Fantasy LaLiga` y compártela con el email de la cuenta de servicio como **Editor**.

### 4.2 Ejecutar el scraper

```bash
# Scraping completo + subir a Google Sheets
python transfermarkt_scraper.py

# Solo probar el scraping (sin Google Sheets)
python transfermarkt_scraper.py --prueba

# Si ya tienes el cache y solo quieres subir a Sheets
python transfermarkt_scraper.py --solo-subir
```

El script tarda 2-3 minutos. Al terminar, la hoja tendrá todos los jugadores de LaLiga con nombre, equipo, posición, valor de mercado y URL de Transfermarkt.

> **Cuándo ejecutarlo:** al inicio de la temporada y tras cada ventana de mercado (enero, verano).

---

## Paso 5 — Fase 2: Puntuaciones por jornada (manual)

La API de LaLiga Fantasy requiere autenticación y no es pública. Los puntos se introducen manualmente mediante un CSV tras cada jornada.

### Formato del CSV

Crea un archivo `puntos_j15.csv` (o el nombre que quieras):

```csv
Nombre,Puntos
Bellingham,18
Vinicius,22
Lewandowski,15
Ter Stegen,10
```

### Cómo obtener los datos rápido

En [fantasy.laliga.com](https://fantasy.laliga.com):
1. Ve a **Estadísticas → Jugadores**
2. Filtra por la jornada
3. Selecciona toda la tabla (Ctrl+A) y copia (Ctrl+C)
4. Pega en Excel o Google Sheets y exporta como CSV

### Ejecutar la importación

```bash
# Importar y guardar en Supabase
python importar_puntos.py --jornada 15 --csv puntos_j15.csv

# Solo comprobar el CSV sin guardar
python importar_puntos.py --jornada 15 --csv puntos_j15.csv --prueba
```

> **Cuándo ejecutarlo:** el lunes o martes tras cada jornada, cuando los puntos estén definitivos.

---

## Paso 6 — Publicar la app (opcional)

Para que todos los participantes accedan desde su móvil o PC:

### Opción A — Netlify Drop (más fácil, 30 segundos)

1. Ve a [netlify.com/drop](https://netlify.com/drop).
2. Arrastra el archivo `index.html`.
3. Obtendrás una URL pública tipo `https://nombre-aleatorio.netlify.app`.

### Opción B — Vercel

```bash
npm install -g vercel
vercel
```

---

## Paso 5b — Cargar jugadores en Supabase

Una vez ejecutado el scraper de Transfermarkt y con el `.env` configurado:

```bash
# Comprobar antes de subir
python cargar_jugadores.py --prueba

# Cargar los 785 jugadores en Supabase
python cargar_jugadores.py
```

## Paso 5c — Dar de alta a los participantes

Ejecuta este SQL en el **SQL Editor de Supabase**, editando los nombres y divisiones:

```sql
insert into participantes (nombre, division_id) values
  ('Nombre1', 1),  -- 1 = Primera Division
  ('Nombre2', 1),
  ('Nombre3', 2),  -- 2 = Segunda Division
  ('Nombre4', 2);
```

Una vez dados de alta, aparecerán en el selector de participante de la app.

---

## Flujo de uso semanal

```
Lunes/Martes tras la jornada
  └─> Exportar puntos desde fantasy.laliga.com a CSV
        └─> python importar_puntos.py --jornada N --csv puntos_jN.csv
              └─> La app actualiza la clasificación automáticamente

Ventana de mercado (enero/verano)
  └─> python transfermarkt_scraper.py
        └─> Valores de mercado actualizados en Google Sheets y BD
```

---

## Solución de problemas

| Problema | Causa probable | Solución |
|---|---|---|
| La app muestra datos demo | `SUPABASE_URL` no configurada en `index.html` | Editar las constantes al inicio del `<script>` |
| Error 403 en Transfermarkt | IP bloqueada temporalmente | Esperar 10 minutos y reintentar |
| `credentials.json` no encontrado | Archivo en ubicación incorrecta | Colocarlo en la carpeta `FILFA/` |
| Hoja de Google no encontrada | No compartida con la cuenta de servicio | Compartir con el email del `credentials.json` |
| Jugadores sin coincidencia en BD | Nombre distinto entre Fantasy y Transfermarkt | Ajustar el nombre en el CSV |
| Error de autenticación Supabase | Clave incorrecta | Verificar `SUPABASE_SERVICE_KEY` en `.env` |
