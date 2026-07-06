-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fix permisos tabla pujas para usuarios autenticados
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- La tabla pujas solo tenía grant a 'anon'. Los usuarios autenticados
-- (admin y equipos) usan el rol 'authenticated', por lo que las
-- operaciones UPDATE/DELETE fallaban silenciosamente.

grant select, insert, update, delete on pujas to authenticated;
grant usage, select on sequence pujas_id_seq to authenticated;
