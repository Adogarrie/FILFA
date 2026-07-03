-- ═══════════════════════════════════════════════════════════════
-- FILFA — Resultados en partidos de competición
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table fase_partidos
  add column if not exists goles_local     int,
  add column if not exists goles_visitante int,
  add column if not exists finalizado      boolean not null default false;
