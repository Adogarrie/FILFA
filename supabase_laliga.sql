-- ═══════════════════════════════════════════════════════════════
-- FILFA — Vínculo con LaLiga Fantasy (importar los puntos de la jornada)
-- Ejecutar en: Supabase Dashboard → SQL Editor
--
-- Requiere supabase_seguridad.sql (tabla administradores y es_admin()).
--
-- Los puntos se descargan con la Edge Function puntos-laliga
-- (supabase/functions/puntos-laliga), que hace de intermediario con la
-- API pública de LaLiga Fantasy. Estas tablas guardan qué equipo y qué
-- jugador de LaLiga Fantasy corresponde a cada uno de la app. Son comunes
-- a todas las federaciones (como la tabla jugadores): las lee cualquier
-- usuario con sesión y solo las modifica el admin de la plataforma (quien
-- esté en la tabla administradores), desde Admin → 🛠️ Plataforma.
--
-- Para ser admin de la plataforma (si aún no lo eres):
--   select id, email from auth.users where email = 'tu_email@aqui.com';
--   insert into administradores (user_id) values ('<el id de arriba>');
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Equipos: teamId de LaLiga Fantasy ↔ jugadores.equipo ─────
create table if not exists equipos_laliga (
  team_id    text primary key,          -- teamId en LaLiga Fantasy
  equipo     text not null unique,      -- jugadores.equipo en la app
  updated_at timestamptz not null default now()
);

-- ─── 2. Jugadores: jugador de la app ↔ id de LaLiga Fantasy ──────
-- Las porterías (POR) no se vinculan: puntúan por equipo (suma de los
-- porteros del club en LaLiga Fantasy).
create table if not exists jugadores_laliga (
  jugador_id uuid primary key references jugadores(id) on delete cascade,
  lf_id      text not null unique,      -- id en LaLiga Fantasy
  lf_nombre  text,                      -- su nombre allí (para revisar)
  updated_at timestamptz not null default now()
);

-- ─── 3. RLS: lectura para usuarios con sesión, escritura solo admin de la plataforma ─
alter table equipos_laliga   enable row level security;
alter table jugadores_laliga enable row level security;

drop policy if exists "Leer equipos_laliga" on equipos_laliga;
create policy "Leer equipos_laliga" on equipos_laliga
  for select to authenticated using (true);
drop policy if exists "Admin plataforma escribe equipos_laliga" on equipos_laliga;
create policy "Admin plataforma escribe equipos_laliga" on equipos_laliga
  for all to authenticated using (es_admin()) with check (es_admin());

drop policy if exists "Leer jugadores_laliga" on jugadores_laliga;
create policy "Leer jugadores_laliga" on jugadores_laliga
  for select to authenticated using (true);
drop policy if exists "Admin plataforma escribe jugadores_laliga" on jugadores_laliga;
create policy "Admin plataforma escribe jugadores_laliga" on jugadores_laliga
  for all to authenticated using (es_admin()) with check (es_admin());

revoke all on equipos_laliga, jugadores_laliga from anon;
grant select, insert, update, delete on equipos_laliga, jugadores_laliga to authenticated;
