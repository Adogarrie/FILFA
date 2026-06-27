-- ═══════════════════════════════════════════════════════════════
-- FILFA — Sorteo aleatorio de jugadores libres
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- Interruptor global: permite que los participantes usen el sorteo
alter table config add column if not exists sorteo_habilitado boolean not null default false;

grant select, update (sorteo_habilitado) on config to anon;
