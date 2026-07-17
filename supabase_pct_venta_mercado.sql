-- ═══════════════════════════════════════════════════════════════
-- FILFA — Porcentaje de recuperación al vender al mercado
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table federaciones
  add column if not exists pct_venta_mercado int not null default 100
  check (pct_venta_mercado between 1 and 100);
