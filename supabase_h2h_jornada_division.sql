-- ═══════════════════════════════════════════════════════════════
-- FILFA — Jornada fantasy por división en Liga FILFA
--
-- Permite asignar una jornada fantasy distinta a cada jornada H2H
-- de cada división, en lugar de una única por jornada.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Eliminar constraint antigua ─────────────────────────────
alter table h2h_jornada_config
  drop constraint if exists h2h_jornada_config_federacion_id_jornada_h2h_key;

-- ─── 2. Nueva columna ────────────────────────────────────────────
alter table h2h_jornada_config
  add column if not exists division_id int references divisiones(id) on delete cascade;

-- ─── 3. Índices únicos parciales ────────────────────────────────
-- Federaciones sin divisiones: unicidad por (federacion_id, jornada_h2h) cuando division_id es null
create unique index if not exists h2h_jornada_config_no_div_idx
  on h2h_jornada_config (federacion_id, jornada_h2h)
  where division_id is null;

-- Federaciones con divisiones: unicidad por (federacion_id, jornada_h2h, division_id)
create unique index if not exists h2h_jornada_config_div_idx
  on h2h_jornada_config (federacion_id, jornada_h2h, division_id)
  where division_id is not null;
