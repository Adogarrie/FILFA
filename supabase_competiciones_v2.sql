-- ═══════════════════════════════════════════════════════════════
-- FILFA — Competiciones v2: añadir columnas de resultado
--
-- goles_local / goles_visitante se guardan solo cuando el admin
-- pulsa "Calcular" en el panel de torneos. Los partidos sin
-- resultado calculado no se cuentan en la clasificación de grupo.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table partidos_competicion
  add column if not exists goles_local     int,   -- null = no calculado aún
  add column if not exists goles_visitante int;
