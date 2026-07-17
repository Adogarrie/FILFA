-- ═══════════════════════════════════════════════════════════════
-- FILFA — Liga H2H
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Columna en federaciones ──────────────────────────────────
alter table federaciones
  add column if not exists h2h_habilitado boolean not null default false;

-- ─── 2. Tabla de partidos H2H ────────────────────────────────────
create table if not exists h2h_partidos (
  id              serial primary key,
  federacion_id   uuid    not null references federaciones(id)  on delete cascade,
  division_id     int     references divisiones(id)             on delete set null,
  jornada         int     not null,
  local_id        uuid    not null references participantes(id) on delete cascade,
  visitante_id    uuid    not null references participantes(id) on delete cascade,
  pts_local       numeric default null,
  pts_visitante   numeric default null,
  check (local_id <> visitante_id)
);

alter table h2h_partidos enable row level security;

-- Cualquier miembro de la federación puede leer
drop policy if exists "Ver H2H" on h2h_partidos;
create policy "Ver H2H"
  on h2h_partidos for select
  using (
    exists (
      select 1 from participantes
       where federacion_id = h2h_partidos.federacion_id
         and user_id = auth.uid()
    )
    or exists (
      select 1 from federaciones
       where id = h2h_partidos.federacion_id
         and admin_user_id = auth.uid()
    )
  );

-- Admin: control total
drop policy if exists "Admin H2H" on h2h_partidos;
create policy "Admin H2H"
  on h2h_partidos for all
  using  (exists (select 1 from federaciones where id = federacion_id and admin_user_id = auth.uid()))
  with check (exists (select 1 from federaciones where id = federacion_id and admin_user_id = auth.uid()));

grant all   on h2h_partidos            to authenticated;
grant usage, select on sequence h2h_partidos_id_seq to authenticated;
