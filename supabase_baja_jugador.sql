-- ═══════════════════════════════════════════════════════════════
-- FILFA — Baja lógica de jugadores
-- Problema: borrar un jugador con historial viola FK de alineaciones.
-- Solución: columna `baja` para marcarlo inactivo sin destruir datos.
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table jugadores
  add column if not exists baja boolean not null default false;
