-- ═══════════════════════════════════════════════════════════════
-- FILFA — Vueltas extra por división en H2H
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table h2h_vueltas_extra
  add column if not exists division_id integer references divisiones(id) on delete set null;

-- Las vueltas extra existentes quedan con division_id = NULL
-- lo que significa "aplica a todas las divisiones" (retrocompatible).
