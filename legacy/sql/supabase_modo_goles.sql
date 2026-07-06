-- ═══════════════════════════════════════════════════════════════
-- FILFA — Modo goles por competición y por partido
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Modo goles por competición ───────────────────────────────
-- true  = resultado en goles (baremo pts→goles)
-- false = resultado en puntos directos (ganador = más pts)
alter table competiciones
  add column if not exists modo_goles boolean not null default true;

-- ─── 2. Modo goles por partido (override del de la competición) ──
-- null  = usar el de la competición
-- true  = forzar goles para este partido
-- false = forzar puntos para este partido
alter table fase_partidos
  add column if not exists modo_goles boolean;
