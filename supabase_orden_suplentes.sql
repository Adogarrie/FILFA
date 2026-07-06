-- ═══════════════════════════════════════════════════════════════
-- FILFA — Orden de suplentes en alineaciones
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table alineaciones
  add column if not exists orden_suplente int;
