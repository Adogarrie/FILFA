-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fase en formato suizo (parte D)
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- IMPORTANTE: ejecutar DESPUÉS de supabase_eliminatorias.sql y ANTES de
-- subir el index.html que lo usa.
--
-- Una clasificación única; cada equipo juega N rondas sin repetir rival.
--  · fases_competicion.equipos: participantes de la fase (array de ids).
--  · suizo_modo: 'previo' (todas las rondas se sortean al principio) o
--    'clasico' (cada ronda empareja a equipos con puntuación parecida,
--    según la clasificación del momento).
--  · suizo_rondas: nº de rondas (por defecto 3).
-- Los partidos son los de siempre (partidos_competicion, ronda = nº de
-- ronda). Con nº impar de equipos, en cada ronda uno descansa: se guarda
-- como partido sin visitante (no entra en la quiniela) y cuenta como
-- victoria (3 puntos, sin goles). Nadie descansa dos veces.
-- Clasificación: puntos, goles a favor, Buchholz (suma de los puntos de
-- los rivales) y diferencia de goles.
-- ═══════════════════════════════════════════════════════════════

alter table fases_competicion drop constraint if exists fases_competicion_tipo_check;
alter table fases_competicion add constraint fases_competicion_tipo_check
  check (tipo in ('grupos', 'sueltos', 'eliminatoria', 'suiza'));

alter table fases_competicion add column if not exists equipos      jsonb    not null default '[]'::jsonb;
alter table fases_competicion add column if not exists suizo_modo   text     not null default 'clasico';
alter table fases_competicion add column if not exists suizo_rondas smallint not null default 3;
alter table fases_competicion drop constraint if exists fases_competicion_equipos_check;
alter table fases_competicion add constraint fases_competicion_equipos_check check (jsonb_typeof(equipos) = 'array');
alter table fases_competicion drop constraint if exists fases_competicion_suizo_modo_check;
alter table fases_competicion add constraint fases_competicion_suizo_modo_check check (suizo_modo in ('previo', 'clasico'));
alter table fases_competicion drop constraint if exists fases_competicion_suizo_rondas_check;
alter table fases_competicion add constraint fases_competicion_suizo_rondas_check check (suizo_rondas between 1 and 30);
