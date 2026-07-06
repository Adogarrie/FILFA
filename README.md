# Fantasy LaLiga — Guía de instalación y uso

App para gestionar tu liga fantasy de LaLiga: mercado de jugadores, plantillas, clasificación y puntuaciones manuales por jornada.

---

## Estado actual del proyecto

| Fase | Descripción | Estado |
|---|---|---|
| 1 | Scraper de jugadores y valores (Transfermarkt) | ✅ Funcionando |
| 2 | Puntuaciones por jornada | ✅ Manual desde la app (Admin → Pts Jugadores) |
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
├── cargar_jugadores.py        # Sube el resultado del scraper a Supabase
├── actualizar_temporada.py    # Refresca valores/activos en cada ventana de mercado
├── supabase_schema.sql        # Base de datos (ejecutar en Supabase)
├── requirements.txt           # Dependencias Python
├── .env.example               # Plantilla de configuración
└── legacy/                    # Scripts y SQL de features descontinuadas (ver legacy/README.md)
```

Los puntos por jornada se introducen ahora directamente desde la app, en
**Admin → Pts Jugadores** (puntos por jugador → recalcula la clasificación de
cada equipo según su alineación de titulares). El antiguo flujo por CSV
(`importar_puntos.py`) ha quedado obsoleto y se movió a `legacy/python/`.

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

## Paso 2.1 — Seguridad: login real con Supabase Auth (obligatorio en producción)

Antes de abrir la app a tus amigos, ejecuta `supabase_seguridad.sql` en el
**SQL Editor** de Supabase. Esto cierra el login con contraseñas en texto
plano y las políticas RLS abiertas, sustituyéndolas por Supabase Auth
(email + contraseña, o Google) y reglas donde cada equipo solo puede
modificar sus propios datos.

1. Pega y ejecuta `supabase_seguridad.sql`.
2. (Opcional) Para permitir "Continuar con Google": en el panel de Supabase
   ve a **Authentication → Providers → Google**, crea unas credenciales
   OAuth en [Google Cloud Console](https://console.cloud.google.com)
   (Client ID + Secret) y pégalas ahí. En **Authentication → URL
   Configuration**, añade la URL donde tengas desplegada la app (la de
   Vercel, por ejemplo) a *Redirect URLs*.
3. Comparte la app con tus amigos. Cada uno se registra solo desde la
   pantalla de login (email + contraseña, o Google) — no necesitas
   recopilar emails ni ejecutar ningún script.
4. Al entrar por primera vez, cada amigo elige:
   - **"Ya jugaba antes"** → reclama su equipo de la lista de equipos sin
     dueño (mantiene su plantilla y presupuesto de antes del cambio).
   - **"Soy nuevo"** → crea un equipo nuevo con el nombre y división que
     elija.
5. Para convertirte en admin: regístrate igual que cualquier amigo y luego,
   en el SQL Editor, ejecuta:
   ```sql
   select id, email from auth.users where email = 'tu_email@aqui.com';
   insert into administradores (user_id) values ('<el id de arriba>');
   ```
6. Cuando todos confirmen que entran bien, borra la tabla antigua desde el
   SQL Editor: `drop table usuarios;`

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

## Paso 5 — Fase 2: Puntuaciones por jornada

La API de LaLiga Fantasy requiere autenticación y no es pública, así que los
puntos se introducen a mano tras cada jornada — pero directamente en la app,
sin CSV ni scripts:

1. Entra como admin (o moderador, si el admin activó ese permiso en
   Admin → Mercado) y ve a **Admin → Pts Jugadores**.
2. Elige la jornada y escribe los puntos de cada jugador (los datos de
   [fantasy.laliga.com](https://fantasy.laliga.com) → Estadísticas →
   Jugadores son la fuente más rápida).
3. Pulsa **Guardar**. La app recalcula automáticamente los puntos de cada
   equipo fantasy a partir de los titulares que cada uno alineó esa jornada.

> **Cuándo hacerlo:** el lunes o martes tras cada jornada, cuando los puntos estén definitivos.

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
  └─> Admin → Pts Jugadores en la app: puntos de cada jugador
        └─> La app recalcula la clasificación de cada equipo automáticamente

Ventana de mercado (enero/verano)
  └─> python transfermarkt_scraper.py
        └─> python cargar_jugadores.py / actualizar_temporada.py
              └─> Valores de mercado actualizados en la BD
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
