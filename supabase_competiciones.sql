-- ═══════════════════════════════════════════════════════════════
-- FILFA — Competiciones (Copa, Grupos, Eliminatorias, Liga)
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Tabla competiciones ──────────────────────────────────────
create table if not exists competiciones (
  id            serial primary key,
  federacion_id uuid not null references federaciones(id) on delete cascade,
  nombre        text not null,
  created_at    timestamptz default now()
);
create index if not exists competiciones_fed_idx on competiciones(federacion_id);

-- ─── 2. Tabla fases (fases dentro de una competición) ────────────
create table if not exists fases (
  id             serial primary key,
  competicion_id int  not null references competiciones(id) on delete cascade,
  nombre         text not null,
  tipo           text not null check (tipo in ('liga', 'grupos', 'eliminatoria')),
  orden          int  not null default 0
);

-- ─── 3. Asignación de equipos a grupos ───────────────────────────
create table if not exists fase_grupos (
  id              serial primary key,
  fase_id         int  not null references fases(id) on delete cascade,
  grupo           text not null,
  participante_id uuid not null references participantes(id) on delete cascade,
  unique(fase_id, participante_id)
);

-- ─── 4. Partidos de cada fase ─────────────────────────────────────
create table if not exists fase_partidos (
  id            serial primary key,
  fase_id       int  not null references fases(id) on delete cascade,
  jornada       int  not null,
  grupo         text,          -- solo para tipo='grupos'
  ronda         text,          -- solo para tipo='eliminatoria'
  local_id      uuid not null references participantes(id),
  visitante_id  uuid not null references participantes(id),
  es_neutral    boolean not null default false
);
create index if not exists fase_partidos_fase_idx on fase_partidos(fase_id);

-- ─── 5. RLS ───────────────────────────────────────────────────────
alter table competiciones  enable row level security;
alter table fases          enable row level security;
alter table fase_grupos    enable row level security;
alter table fase_partidos  enable row level security;

-- Todos pueden ver
drop policy if exists "Ver competiciones"  on competiciones;
drop policy if exists "Ver fases"          on fases;
drop policy if exists "Ver fase_grupos"    on fase_grupos;
drop policy if exists "Ver fase_partidos"  on fase_partidos;

create policy "Ver competiciones" on competiciones for select using (true);
create policy "Ver fases"         on fases         for select using (true);
create policy "Ver fase_grupos"   on fase_grupos   for select using (true);
create policy "Ver fase_partidos" on fase_partidos for select using (true);

-- Admin de la federación puede crear / borrar
drop policy if exists "Admin gestiona competiciones" on competiciones;
create policy "Admin gestiona competiciones" on competiciones for all
  using   (federacion_id in (select id from federaciones where admin_user_id = auth.uid()))
  with check (federacion_id in (select id from federaciones where admin_user_id = auth.uid()));

drop policy if exists "Admin gestiona fases" on fases;
create policy "Admin gestiona fases" on fases for all
  using (competicion_id in (
    select c.id from competiciones c
    join   federaciones f on f.id = c.federacion_id
    where  f.admin_user_id = auth.uid()
  ))
  with check (competicion_id in (
    select c.id from competiciones c
    join   federaciones f on f.id = c.federacion_id
    where  f.admin_user_id = auth.uid()
  ));

drop policy if exists "Admin gestiona fase_grupos" on fase_grupos;
create policy "Admin gestiona fase_grupos" on fase_grupos for all
  using (fase_id in (
    select f.id from fases f
    join   competiciones c on c.id = f.competicion_id
    join   federaciones  fed on fed.id = c.federacion_id
    where  fed.admin_user_id = auth.uid()
  ))
  with check (fase_id in (
    select f.id from fases f
    join   competiciones c on c.id = f.competicion_id
    join   federaciones  fed on fed.id = c.federacion_id
    where  fed.admin_user_id = auth.uid()
  ));

drop policy if exists "Admin gestiona fase_partidos" on fase_partidos;
create policy "Admin gestiona fase_partidos" on fase_partidos for all
  using (fase_id in (
    select f.id from fases f
    join   competiciones c on c.id = f.competicion_id
    join   federaciones  fed on fed.id = c.federacion_id
    where  fed.admin_user_id = auth.uid()
  ))
  with check (fase_id in (
    select f.id from fases f
    join   competiciones c on c.id = f.competicion_id
    join   federaciones  fed on fed.id = c.federacion_id
    where  fed.admin_user_id = auth.uid()
  ));

-- ─── 6. Grants ────────────────────────────────────────────────────
grant select, insert, update, delete on competiciones to authenticated;
grant select, insert, update, delete on fases         to authenticated;
grant select, insert, update, delete on fase_grupos   to authenticated;
grant select, insert, update, delete on fase_partidos to authenticated;

grant usage, select on sequence competiciones_id_seq  to authenticated;
grant usage, select on sequence fases_id_seq          to authenticated;
grant usage, select on sequence fase_grupos_id_seq    to authenticated;
grant usage, select on sequence fase_partidos_id_seq  to authenticated;
