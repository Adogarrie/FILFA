-- ═══════════════════════════════════════════════════════════════
-- FILFA — Eliminación de imágenes de Supabase Storage
--
-- Propósito: reducir egress de Storage. Se elimina el uso de
--            escudos de equipos fantasy y logo de federación.
--
-- PASOS:
-- 1. Ejecutar este SQL en Supabase Dashboard → SQL Editor.
-- 2. Ir a Storage → bucket "escudos-participantes" → borrar todos los archivos.
-- 3. Ir a Storage → bucket "logos-federacion"      → borrar todos los archivos.
--    (Los buckets pueden dejarse vacíos o eliminarse).
-- ═══════════════════════════════════════════════════════════════

-- Poner a NULL los escudos de todos los equipos fantasy
UPDATE participantes SET escudo_url = NULL;

-- Poner a NULL el logo de todas las federaciones
UPDATE federaciones SET logo_url = NULL;
