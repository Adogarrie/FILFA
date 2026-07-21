-- ═══════════════════════════════════════════════════════════════
-- FILFA — Puntos fantasy brutos en partidos H2H
--
-- Añade fantasy_local y fantasy_visitante a h2h_partidos para
-- almacenar los puntos fantasy de cada equipo antes de aplicar
-- el baremo. Se rellenan solo cuando se usa el auto-cálculo.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table h2h_partidos
  add column if not exists fantasy_local     numeric,
  add column if not exists fantasy_visitante numeric;
