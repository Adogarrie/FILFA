# FILFA — Fantasy LaLiga

App de liga fantasy de fútbol (LaLiga): mercado de jugadores, plantillas, alineaciones,
clasificación (individual y H2H) y puntuaciones manuales por jornada. Multi-liga
(federaciones) con admins/moderadores por liga.

## Stack y arquitectura

- **Frontend**: React 18 + Babel standalone, **todo en un único archivo** `index.html`
  (~12.700 líneas). Sin build step: se abre directamente en el navegador o se sirve
  estático (Vercel, ver `vercel.json`). Librerías cargadas por CDN (unpkg/jsdelivr):
  React, ReactDOM, Babel standalone, xlsx, `@supabase/supabase-js`, `marked`.
- **Backend**: Supabase (PostgreSQL + Auth + Row Level Security). No hay servidor propio;
  la app habla directamente con Supabase desde el cliente con la clave `anon` (líneas
  ~227-228 de `index.html`). Una Edge Function en `supabase/functions/actualizar-jugadores`.
- **Scripts Python** (fuera del runtime de la app, se ejecutan manualmente):
  - `transfermarkt_scraper.py` — scrapea jugadores/valores de Transfermarkt.
  - `cargar_jugadores.py` — sube el resultado del scraper a Supabase.
  - `actualizar_temporada.py` — refresca jugadores activos en cada ventana de mercado
    (lee `jugadores_cache.json`, usa `SUPABASE_SERVICE_KEY`).
  - Dependencias en `requirements.txt`; configuración en `.env` (ver `.env.example`).
- **PWA**: `manifest.json`, `sw.js`, `icons/`.

## Estructura de `index.html`

Componentes React principales (búsqueda rápida por nombre de función):

- `App` — layout raíz, navegación entre vistas (`VALID_VISTAS`), sesión.
- `Login`, `FederacionOnboarding`, `SelectorFederacion` — auth y alta/selección de liga.
- `Plantilla`, `Alineacion`, `Mercado`, `Ofertas`, `Equipos`, `Cesiones` — flujo de usuario.
- `CalendarioFantasy`, `LigaH2H`, `PosHistorialTable`, `Competiciones`, `TorneosVista` — clasificaciones.
- `Tablon`, `FederacionInfo`, `Ayuda` — tablón de anuncios, info de liga, ayuda.
- `Admin*` (`AdminPanel`, `AdminPtsJugadores`, `AdminMercado`, `AdminFederacion`,
  `AdminEquipos`, `AdminJugadores`, `AdminPujas`, `AdminCierres`, `AdminCesiones`,
  `AdminNoJugo`, `AdminLigaH2H`, etc.) — todo el panel de administración/moderación,
  agrupado en subsecciones (`AdminPtsGroup`, `AdminAjustesGroup`, `AdminMercadoGroup`).

## Base de datos (Supabase)

- `supabase_schema.sql` es el esquema base. El resto de `supabase_*.sql` en la raíz son
  **migraciones incrementales** (una por feature/fix), pensadas para pegarse y ejecutarse
  en el SQL Editor de Supabase en orden cronológico según se fueron creando. No hay
  herramienta de migraciones automatizada: cada `.sql` nuevo es una migración manual.
- `supabase_seguridad.sql` activa Supabase Auth real + RLS (obligatorio antes de producción).
- `legacy/` — código y SQL de features descontinuadas, ya sin referencias en `index.html`.
  No tocar salvo que se retome explícitamente esa funcionalidad (ver `legacy/README.md`).

### Features no evidentes desde el código (contexto de negocio)

- **Lesiones**: columna `lesionado` en `jugadores`. Un jugador lesionado se puede vender al
  100% aunque el mercado esté cerrado, y no cuenta para el límite de 14 jugadores. Badge "LES".
- **Sustituciones por lesión**: `sustituciones_lesion` en `participantes`; se incrementa al
  vender un lesionado con mercado cerrado, se decrementa al fichar sustituto (botón "Fichar sust.").
- **Cesiones**: préstamos entre equipos (tabla `cesiones`), requieren aprobación del admin,
  sin límite de cupos, puntos al 100%. Los campos `_esCedido`/`_cedente` se inyectan en
  tiempo de consulta dentro de `Alineacion` (no vienen de la BD).

## Cómo trabajar en este repo

- Al editar `index.html`, mantener el estilo existente: componentes funcionales con hooks,
  sin TypeScript, sin JSX externo (todo vía Babel standalone in-browser). No introducir un
  build step ni dividir el archivo salvo que el usuario lo pida explícitamente.
- Cambios de esquema van en un `supabase_*.sql` nuevo y descriptivo (no editar
  `supabase_schema.sql` retroactivamente salvo que el usuario lo pida).
- Comentarios de UI y nombres de dominio están en español; mantener ese idioma en el código
  de la app (variables, textos, mensajes) para consistencia.
- No hay tests automatizados ni linter configurado; validar cambios manualmente en navegador
  (la skill `run` puede servir para levantar un servidor estático local).

## Git

**No hacer commits ni push.** El usuario gestiona el control de versiones él mismo.
