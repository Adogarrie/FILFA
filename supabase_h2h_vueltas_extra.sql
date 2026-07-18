-- ═══════════════════════════════════════════════════════════════
-- FILFA — Vueltas extra en la Liga H2H
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- Número de jornadas del calendario base (sin vueltas extra).
-- Se actualiza cada vez que el admin genera o regenera el calendario.
alter table federaciones
  add column if not exists h2h_jornadas_base int;

-- Vueltas extra añadidas por el admin más allá de las 2 iniciales.
-- Cada vuelta copia los enfrentamientos de la vuelta 1 o la vuelta 2.
create table if not exists h2h_vueltas_extra (
  id              serial  primary key,
  federacion_id   uuid    not null references federaciones(id) on delete cascade,
  vuelta_num      int     not null,   -- 3, 4, 5…
  basada_en       int     not null,   -- 1 (ida) o 2 (vuelta)
  pts_local       int     not null default 5,
  jornada_inicio  int     not null,   -- primer número de jornada de esta vuelta
  unique (federacion_id, vuelta_num)
);

alter table h2h_vueltas_extra enable row level security;

drop policy if exists "Admin gestiona h2h_vueltas_extra" on h2h_vueltas_extra;
create policy "Admin gestiona h2h_vueltas_extra"
  on h2h_vueltas_extra for all
  using  (exists (select 1 from federaciones where id = federacion_id and admin_user_id = auth.uid()))
  with check (exists (select 1 from federaciones where id = federacion_id and admin_user_id = auth.uid()));

drop policy if exists "Participantes ven h2h_vueltas_extra" on h2h_vueltas_extra;
create policy "Participantes ven h2h_vueltas_extra"
  on h2h_vueltas_extra for select
  using (
    exists (
      select 1 from participantes
       where federacion_id = h2h_vueltas_extra.federacion_id
         and user_id = auth.uid()
    )
  );

grant all   on h2h_vueltas_extra           to authenticated;
grant usage, select on sequence h2h_vueltas_extra_id_seq to authenticated;
