-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fecha de nacimiento de los jugadores (para mostrar la edad)
--
-- Se guarda la fecha de nacimiento, NO la edad en sí — la edad se calcula
-- en la app a partir de esta fecha (ver calcularEdad en index.html), para
-- que no se quede desactualizada con el paso del tiempo.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table jugadores
  add column if not exists fecha_nacimiento date;
