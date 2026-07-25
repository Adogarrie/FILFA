-- ═══════════════════════════════════════════════════════════════
-- FILFA — Jornada actual de Liga FILFA (H2H)
--
-- Añade columna jornada_h2h_actual en federaciones.
-- Controla la jornada por defecto en Calendario H2H y
-- Clasificación H2H > Por Jornada.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table federaciones
  add column if not exists jornada_h2h_actual int;
