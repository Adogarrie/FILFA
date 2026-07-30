-- ═══════════════════════════════════════════════════════════════
-- FILFA — Mensajes de usuarios en el tablón
--
-- Añade la columna que controla si los usuarios (no admin/moderador)
-- pueden enviar mensajes al tablón pendientes de aprobación.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table federaciones
  add column if not exists mensajes_tablon_habilitados boolean default true;
