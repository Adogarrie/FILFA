-- ═══════════════════════════════════════════════════════════════
-- FILFA — Jugadores duplicados (varios equipos, mismo jugador)
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════
-- Cuando está habilitado, los jugadores (no porteros) cuyo valor
-- de mercado supere el umbral configurado pueden ser fichados por
-- hasta N equipos simultáneamente.
-- Si duplicados_valor_min = 0, aplica a TODOS los jugadores no-POR.
-- ═══════════════════════════════════════════════════════════════

alter table federaciones
  add column if not exists duplicados_habilitado boolean not null default false,
  add column if not exists duplicados_valor_min  numeric not null default 0,
  add column if not exists duplicados_max        int     not null default 2;

-- Garantía de BD: un equipo nunca puede tener al mismo jugador dos veces.
-- Esto es independiente de si duplicados_habilitado está activo o no.
alter table plantillas
  drop constraint if exists plantillas_participante_jugador_unique,
  add  constraint         plantillas_participante_jugador_unique
    unique (participante_id, jugador_id);
