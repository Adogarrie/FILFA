-- ═══════════════════════════════════════════════════════════════
-- FILFA — Baja lógica de jugadores
-- Problema: borrar un jugador con historial viola FK de alineaciones.
-- Solución: columna `baja` para marcarlo inactivo sin destruir datos.
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table jugadores
  add column if not exists baja boolean not null default false;

-- Actualizar vista para excluir también dados de baja
create or replace view vista_jugadores_libres as
select j.*
from jugadores j
where j.activo = true
  and j.baja   = false
  and j.id not in (select jugador_id from plantillas);
