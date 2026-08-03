-- ═══════════════════════════════════════════════════════════════
-- FILFA — Columna draft_habilitado en federaciones
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table federaciones
  add column if not exists draft_habilitado boolean not null default false;
