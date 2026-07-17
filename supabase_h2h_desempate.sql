-- ═══════════════════════════════════════════════════════════════
-- FILFA — Orden de criterios de desempate H2H (configurable por admin)
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table federaciones
  add column if not exists h2h_desempate_orden text not null
  default '["h2h","gf","dif"]';
