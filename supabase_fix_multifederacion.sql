-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fix multi-federación: un usuario puede tener un equipo
--         en cada federación (antes solo podía tener uno global)
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- 1. Eliminar la restricción antigua (1 usuario = 1 equipo global)
alter table participantes
  drop constraint if exists participantes_user_id_unique;

-- 2. Nueva restricción: 1 usuario = 1 equipo POR federación
--    (índice parcial para ignorar equipos sin usuario asignado)
drop index if exists participantes_user_fed_unique;

create unique index participantes_user_fed_unique
  on participantes(user_id, federacion_id)
  where user_id is not null;
