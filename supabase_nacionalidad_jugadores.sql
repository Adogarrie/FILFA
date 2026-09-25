-- ═══════════════════════════════════════════════════════════════
-- FILFA — Nacionalidad de los jugadores
--
-- Columna nueva en `jugadores` con el nombre del país (tal cual lo
-- devuelve Transfermarkt, en español — ver transfermarkt_scraper.py).
-- La app la muestra como una bandera, cargada desde una carpeta local
-- `nations/` (no Supabase Storage, sin coste de BBDD): el nombre del
-- fichero se obtiene normalizando el país (minúsculas, sin acentos,
-- espacios → guion bajo), ej. "España" → nations/espana.png,
-- "Costa de Marfil" → nations/costa_de_marfil.png. Si falta el fichero
-- de un país, la bandera simplemente no se muestra (no rompe nada).
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table jugadores
  add column if not exists nacionalidad text;
