-- ═══════════════════════════════════════════════════════════
-- Fantasy LaLiga — Schema completo para Supabase
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════

-- Extensiones
create extension if not exists "uuid-ossp";

-- ─── Configuración global ───────────────────────────────────
create table if not exists config (
  id              int primary key default 1,
  jornada_actual  int not null default 1,
  presupuesto_inicial numeric(10,2) not null default 100000000,  -- 100M €
  check (id = 1)  -- solo 1 fila
);
insert into config (id) values (1) on conflict do nothing;

-- ─── Divisiones ─────────────────────────────────────────────
create table if not exists divisiones (
  id     serial primary key,
  nombre text not null unique  -- 'Primera', 'Segunda'
);
insert into divisiones (nombre) values ('Primera'), ('Segunda') on conflict do nothing;

-- ─── Participantes ──────────────────────────────────────────
create table if not exists participantes (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid references auth.users(id) on delete cascade,
  nombre       text not null,
  division_id  int  references divisiones(id) not null,
  presupuesto  numeric(10,2) not null default 100000000,
  created_at   timestamptz default now()
);

-- ─── Jugadores ──────────────────────────────────────────────
create type posicion_tipo as enum ('POR', 'DEF', 'MED', 'DEL');

create table if not exists jugadores (
  id            uuid primary key default uuid_generate_v4(),
  nombre        text not null,
  equipo        text not null,
  posicion      posicion_tipo not null,
  valor_mercado numeric(12,2) not null default 0,
  url_tm        text,          -- URL Transfermarkt
  activo        boolean not null default true,
  updated_at    timestamptz default now()
);
create unique index if not exists jugadores_nombre_equipo on jugadores(nombre, equipo);
create index on jugadores(posicion);
create index on jugadores(equipo);

-- ─── Plantillas (jugadores fichados por cada participante) ──
create table if not exists plantillas (
  id               serial primary key,
  participante_id  uuid references participantes(id) on delete cascade,
  jugador_id       uuid references jugadores(id),
  precio_compra    numeric(12,2) not null,
  fecha_fichaje    date not null default current_date,
  unique (participante_id, jugador_id)
);

-- ─── Puntuaciones por jugador y jornada ─────────────────────
create table if not exists puntuaciones_jornada (
  jugador_id  uuid references jugadores(id),
  jornada     int not null,
  puntos      int not null default 0,
  primary key (jugador_id, jornada)
);

-- ─── Clasificación (puntos acumulados por participante) ─────
create table if not exists clasificacion (
  participante_id  uuid references participantes(id) on delete cascade,
  jornada          int not null,
  puntos_jornada   int not null default 0,
  primary key (participante_id, jornada)
);

-- ═══════════════════════════════════════════════════════════
-- VISTAS
-- ═══════════════════════════════════════════════════════════

-- Clasificación total por división
create or replace view vista_clasificacion as
select
  p.id,
  p.nombre,
  d.nombre as division,
  coalesce(sum(c.puntos_jornada), 0) as puntos_totales,
  coalesce(max(c.puntos_jornada), 0) as mejor_jornada,
  rank() over (
    partition by p.division_id
    order by coalesce(sum(c.puntos_jornada), 0) desc
  ) as posicion
from participantes p
join divisiones d on d.id = p.division_id
left join clasificacion c on c.participante_id = p.id
group by p.id, p.nombre, d.nombre, p.division_id;

-- Jugadores libres (no fichados por nadie)
create or replace view vista_jugadores_libres as
select j.*
from jugadores j
where j.activo = true
  and j.id not in (select jugador_id from plantillas);

-- ═══════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY (RLS)
-- ═══════════════════════════════════════════════════════════

alter table participantes      enable row level security;
alter table plantillas         enable row level security;

-- ═══════════════════════════════════════════════════════════
-- PERMISOS PARA EL CLIENTE WEB (rol anon)
-- ═══════════════════════════════════════════════════════════
grant select on jugadores             to anon;
grant select on divisiones            to anon;
grant select on clasificacion         to anon;
grant select on puntuaciones_jornada  to anon;
grant select on vista_clasificacion   to anon;
grant select on vista_jugadores_libres to anon;

-- Cada usuario ve todos los participantes (clasificación pública)
create policy "Lectura pública participantes"
  on participantes for select using (true);

-- Solo el propio usuario puede editar su participante
create policy "Edición propia participante"
  on participantes for update
  using (auth.uid() = user_id);

-- Cada usuario ve todas las plantillas (mercado abierto)
create policy "Lectura pública plantillas"
  on plantillas for select using (true);

-- Solo el propietario puede modificar su plantilla
create policy "Gestión propia plantilla"
  on plantillas for all
  using (
    participante_id in (
      select id from participantes where user_id = auth.uid()
    )
  );

