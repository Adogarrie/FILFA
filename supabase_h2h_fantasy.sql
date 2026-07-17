-- ═══════════════════════════════════════════════════════════════
-- FILFA — Conexión puntos fantasy ↔ jornadas Liga H2H
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Columnas en federaciones ────────────────────────────────
-- Baremo de puntos (JSON): array de [minPts, maxPts, goles]
-- Ventaja local por vuelta (int, 0 = deshabilitado)

alter table federaciones
  add column if not exists h2h_baremo jsonb not null
    default '[[0,35,0],[36,44,1],[45,53,2],[54,62,3],[63,71,4],[72,80,5],[81,89,6],[90,98,7],[99,107,8]]',
  add column if not exists h2h_pts_local_v1 int not null default 5,
  add column if not exists h2h_pts_local_v2 int not null default 5;

-- ─── 2. Tabla de asignación jornada H2H → jornada fantasy ───────
create table if not exists h2h_jornada_config (
  id              serial primary key,
  federacion_id   uuid  not null references federaciones(id) on delete cascade,
  jornada_h2h     int   not null,
  jornada_fantasy int,           -- null = sin asignar
  unique (federacion_id, jornada_h2h)
);

alter table h2h_jornada_config enable row level security;

drop policy if exists "Admin gestiona h2h_jornada_config" on h2h_jornada_config;
create policy "Admin gestiona h2h_jornada_config"
  on h2h_jornada_config for all
  using  (exists (select 1 from federaciones where id = federacion_id and admin_user_id = auth.uid()))
  with check (exists (select 1 from federaciones where id = federacion_id and admin_user_id = auth.uid()));

drop policy if exists "Participantes ven h2h_jornada_config" on h2h_jornada_config;
create policy "Participantes ven h2h_jornada_config"
  on h2h_jornada_config for select
  using (
    exists (
      select 1 from participantes
       where federacion_id = h2h_jornada_config.federacion_id
         and user_id = auth.uid()
    )
  );

grant all   on h2h_jornada_config            to authenticated;
grant usage, select on sequence h2h_jornada_config_id_seq to authenticated;
