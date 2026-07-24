-- ═══════════════════════════════════════════════════════════════
-- FILFA — Colores de clasificación por puesto
--
-- Añade columna jsonb en federaciones para guardar reglas de color
-- independientes por tipo de clasificación.
--
-- Estructura esperada:
--   {
--     "fantasia": [{"pos": 1, "bg": "#ffd700", "text": "#000000"}],
--     "h2h":      [{"pos": 1, "bg": "#ffd700", "text": "#000000"}],
--     "grupos":   [{"pos": 1, "bg": "#d4edda", "text": "#155724"}]
--   }
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table federaciones
  add column if not exists clasif_colores jsonb;
