-- ═══════════════════════════════════════════════════════════════
-- FILFA — Torneos en modo Liga Fantástica (por puntos, sin baremo)
-- Ejecutar en: Supabase Dashboard → SQL Editor
--
-- Cada fase de un torneo puede jugarse:
--   modo 'goles'  → como hasta ahora: los puntos fantasy se convierten en
--                   goles con el baremo (H2H).
--   modo 'puntos' → Liga Fantástica, sin baremo:
--     · Partidos sueltos: gana quien hace más puntos; el resultado guardado
--       en goles_local/goles_visitante son los puntos (redondeados).
--     · Fase de grupos: sin partidos. Cada grupo se ordena por la suma de
--       puntos de sus equipos en las jornadas de la fase (`jornadas`);
--       desempate: jornadas ganadas dentro del grupo y mejor jornada.
--       `puntos` guarda lo calculado por el admin:
--       { participante_id: { jornada: pts } }.
-- Los comodines cuentan en un torneo solo si están asignados a él
-- (federaciones.comodin_*_en_torneo / comodin_*_torneo_ids).
-- Sin cambios de permisos: las columnas siguen las reglas de la tabla.
-- ═══════════════════════════════════════════════════════════════

alter table fases_competicion
  add column if not exists modo     text  not null default 'goles',
  add column if not exists jornadas int[] not null default '{}',
  add column if not exists puntos   jsonb not null default '{}';

alter table fases_competicion drop constraint if exists fases_competicion_modo_check;
alter table fases_competicion add constraint fases_competicion_modo_check
  check (modo in ('goles', 'puntos'));
