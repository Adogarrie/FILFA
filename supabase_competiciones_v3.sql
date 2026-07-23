-- ═══════════════════════════════════════════════════════════════
-- FILFA — Competiciones v3: ventaja local por fase
--
-- pts_local: puntos de ventaja que se suman al equipo local
-- antes de aplicar el baremo para convertir a goles.
-- Configurable por fase; 0 = sin ventaja (default).
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table fases_competicion
  add column if not exists pts_local int not null default 0;
