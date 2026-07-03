-- ═══════════════════════════════════════════════════════════════
-- FILFA — Puntos por jugador real y jornada fantasy en partidos
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Puntos individuales por jugador y jornada ────────────────
create table if not exists puntos_jugador (
  id         serial primary key,
  jugador_id uuid not null references jugadores(id) on delete cascade,
  jornada    int  not null check (jornada between 1 and 38),
  pts        numeric(7,2) not null default 0,
  unique(jugador_id, jornada)
);
create index if not exists puntos_jugador_jornada_idx on puntos_jugador(jornada);

alter table puntos_jugador enable row level security;

drop policy if exists "Ver puntos_jugador" on puntos_jugador;
create policy "Ver puntos_jugador" on puntos_jugador for select using (true);

drop policy if exists "Admin escribe puntos_jugador" on puntos_jugador;
create policy "Admin escribe puntos_jugador" on puntos_jugador for all
  using   (exists (select 1 from federaciones where admin_user_id = auth.uid()))
  with check (exists (select 1 from federaciones where admin_user_id = auth.uid()));

grant select, insert, update, delete on puntos_jugador to authenticated;
grant usage, select on sequence puntos_jugador_id_seq to authenticated;

-- ─── 2. Jornada fantasy en partidos de competición ───────────────
-- Permite vincular un partido de competición a una jornada fantasy diferente.
-- NULL = usa la jornada del propio partido (comportamiento anterior).
alter table fase_partidos
  add column if not exists jornada_fantasy int;
