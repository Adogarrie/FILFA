-- ═══════════════════════════════════════════════════════════════
-- FILFA — Clasificación de jugadores (precalculada)
--
-- Añade a `estadisticas_jugadores` (ver supabase_estadisticas_jugadores.sql,
-- que debe ejecutarse antes) la columna con la clasificación de puntos de
-- todos los jugadores con puntos en la liga: puntos totales, jornadas
-- puntuadas, jornadas titular y jornadas suplente, solo de jornadas cerradas.
--
-- Va en una columna aparte para que la pestaña Equipos, que solo pide
-- `datos`, no la descargue. La calcula recalcularEstadisticasJugadores()
-- (index.html) con los mismos datos que ya descarga para los jugadores
-- destacados, así que no añade descargas. Las políticas RLS de la tabla
-- cubren la nueva columna.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table estadisticas_jugadores
  add column if not exists ranking_jugadores jsonb not null default '{}'::jsonb;
