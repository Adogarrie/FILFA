-- ═══════════════════════════════════════════════════════════════
-- FILFA — Palmarés histórico
--
-- Historial permanente de cada federación: clasificaciones finales,
-- rondas alcanzadas en torneos y récords de cada temporada. Lo rellena
-- el admin de dos formas:
--   · Al cerrar la temporada (cerrar_temporada): la app calcula el
--     palmarés de la temporada que termina, el admin lo revisa y se
--     guarda en la misma transacción que el reinicio.
--   · A mano: temporadas anteriores que no se jugaron en la app o en
--     esta federación (con equipos de nombre libre).
--
-- La clasificación histórica por puntos se calcula en el navegador con
-- las tablas de puntos que fija el admin:
--   · federaciones.palmares_puntos: {clave_competicion: {puesto: puntos}},
--     reutilizable entre temporadas (clave = 'fantasy', 'quiniela',
--     'liga:<división>', 'torneo:<nombre>' u 'otra:<nombre>', en minúsculas).
--   · palmares_competiciones.puntos: la misma tabla, fijada solo para esa
--     temporada (si no es null, sustituye a la general).
--   · palmares.puntos_manual: puntos de una entrada concreta (sustituyen
--     a los de la tabla).
--
-- En los torneos el "puesto" es la ronda alcanzada:
--   1 Campeón · 2 Subcampeón · 3 Semifinales · 4 Cuartos · 5 Octavos ·
--   6 Dieciseisavos · 7 Fase de grupos · 8 Participante
--
-- El reinicio de temporada NO borra estas tablas.
-- Todos los miembros leen; solo el admin escribe.
--
-- Requiere: supabase_quiniela.sql (es_miembro_federacion) y
-- supabase_reiniciar_temporada.sql (reiniciar_federacion).
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Tablas de puntos ─────────────────────────────────────────
alter table federaciones
  add column if not exists palmares_puntos jsonb not null default '{}'::jsonb;

-- ─── 2. Tablas ──────────────────────────────────────────────────
create table if not exists palmares_temporadas (
  id             bigserial primary key,
  federacion_id  uuid not null references federaciones(id) on delete cascade,
  nombre         text not null check (length(trim(nombre)) between 1 and 40),
  origen         text not null default 'manual' check (origen in ('app', 'manual')),
  created_at     timestamptz not null default now(),
  unique (federacion_id, nombre)
);

create table if not exists palmares_competiciones (
  id              bigserial primary key,
  temporada_id    bigint not null references palmares_temporadas(id) on delete cascade,
  federacion_id   uuid not null references federaciones(id) on delete cascade,
  tipo            text not null check (tipo in ('fantasy', 'liga', 'torneo', 'quiniela', 'otra')),
  nombre          text not null check (length(trim(nombre)) between 1 and 60),
  orden           int not null default 0,
  participantes   int check (participantes is null or participantes between 0 and 500),
  puntos          jsonb check (puntos is null or jsonb_typeof(puntos) = 'object'),
  unique (temporada_id, tipo, nombre)
);
create index if not exists palmares_competiciones_fed on palmares_competiciones(federacion_id);

create table if not exists palmares (
  id               bigserial primary key,
  competicion_id   bigint not null references palmares_competiciones(id) on delete cascade,
  federacion_id    uuid not null references federaciones(id) on delete cascade,
  puesto           int not null check (puesto between 1 and 500),
  -- Equipo actual de la liga (si lo hay) y nombre copiado: si el equipo se
  -- borra o cambia de nombre, el palmarés conserva el de aquella temporada.
  participante_id  uuid references participantes(id) on delete set null,
  equipo           text not null check (length(trim(equipo)) between 1 and 60),
  puntos_comp      numeric,          -- puntos en la competición (informativo)
  movimiento       text check (movimiento in ('ascenso', 'descenso')),
  puntos_manual    numeric,          -- sustituye a la tabla de puntos
  detalle          text check (detalle is null or length(detalle) <= 120)
);
create index if not exists palmares_fed  on palmares(federacion_id);
create index if not exists palmares_comp on palmares(competicion_id);

create table if not exists palmares_records (
  id               bigserial primary key,
  temporada_id     bigint not null references palmares_temporadas(id) on delete cascade,
  federacion_id    uuid not null references federaciones(id) on delete cascade,
  tipo             text not null check (tipo in ('mejor_jornada', 'mas_puntos_temporada', 'mayor_goleada',
                                                 'mas_goles_partido', 'mas_aciertos_quiniela')),
  valor            numeric not null,
  participante_id  uuid references participantes(id) on delete set null,
  equipo           text not null check (length(trim(equipo)) between 1 and 130),
  detalle          text check (detalle is null or length(detalle) <= 120)
);
create index if not exists palmares_records_fed on palmares_records(federacion_id);

-- ─── 3. Coherencia ───────────────────────────────────────────────
-- federacion_id de cada fila = el de su temporada/competición, y el
-- equipo enlazado (si lo hay) pertenece a la federación.
create or replace function palmares_validar()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare v_fed uuid;
begin
  if tg_table_name = 'palmares_competiciones' or tg_table_name = 'palmares_records' then
    select federacion_id into v_fed from palmares_temporadas where id = new.temporada_id;
  else
    select federacion_id into v_fed from palmares_competiciones where id = new.competicion_id;
  end if;
  if v_fed is null or v_fed <> new.federacion_id then
    raise exception 'palmares_federacion_distinta';
  end if;
  -- (anidado: plpgsql no corta el "and" y palmares_competiciones no tiene participante_id)
  if tg_table_name in ('palmares', 'palmares_records') then
    if new.participante_id is not null
       and not exists (select 1 from participantes where id = new.participante_id and federacion_id = v_fed) then
      raise exception 'palmares_equipo_ajeno';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists palmares_competiciones_validar on palmares_competiciones;
create trigger palmares_competiciones_validar before insert or update on palmares_competiciones
  for each row execute function palmares_validar();
drop trigger if exists palmares_validar on palmares;
create trigger palmares_validar before insert or update on palmares
  for each row execute function palmares_validar();
drop trigger if exists palmares_records_validar on palmares_records;
create trigger palmares_records_validar before insert or update on palmares_records
  for each row execute function palmares_validar();

-- ─── 4. RLS ──────────────────────────────────────────────────────
alter table palmares_temporadas    enable row level security;
alter table palmares_competiciones enable row level security;
alter table palmares               enable row level security;
alter table palmares_records       enable row level security;

do $$
declare t text;
begin
  foreach t in array array['palmares_temporadas', 'palmares_competiciones', 'palmares', 'palmares_records'] loop
    execute format('drop policy if exists %I on %I', t || '_select', t);
    execute format('drop policy if exists %I on %I', t || '_admin', t);
    execute format('create policy %I on %I for select to authenticated using (es_miembro_federacion(federacion_id))',
                   t || '_select', t);
    execute format('create policy %I on %I for all to authenticated
                      using (federacion_id in (select id from federaciones where admin_user_id = auth.uid()))
                      with check (federacion_id in (select id from federaciones where admin_user_id = auth.uid()))',
                   t || '_admin', t);
    execute format('revoke all on %I from anon', t);
    execute format('grant select, insert, update, delete on %I to authenticated', t);
  end loop;
end $$;

grant usage on sequence palmares_temporadas_id_seq, palmares_competiciones_id_seq,
                        palmares_id_seq, palmares_records_id_seq to authenticated;

-- ─── 5. Guardar una temporada completa ───────────────────────────
-- p_datos = { temporada, origen?, competiciones: [{tipo, nombre, orden?,
--   participantes?, puntos?, entradas: [{puesto, participante_id?, equipo,
--   puntos_comp?, movimiento?, puntos_manual?, detalle?}]}],
--   records: [{tipo, valor, participante_id?, equipo, detalle?}] }
-- Devuelve el id de la temporada. Falla entera si algo no es válido.
create or replace function guardar_palmares_temporada(p_federacion_id uuid, p_datos jsonb)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  v_temp bigint;
  v_comp bigint;
  c jsonb;
  e jsonb;
  r jsonb;
  i int := 0;
begin
  if not exists (select 1 from federaciones where id = p_federacion_id and admin_user_id = auth.uid()) then
    raise exception 'no_autorizado';
  end if;
  if coalesce(trim(p_datos->>'temporada'), '') = '' then
    raise exception 'palmares_sin_temporada';
  end if;
  if exists (select 1 from palmares_temporadas where federacion_id = p_federacion_id
                                                  and nombre = trim(p_datos->>'temporada')) then
    raise exception 'palmares_temporada_existe';
  end if;

  insert into palmares_temporadas (federacion_id, nombre, origen)
  values (p_federacion_id, trim(p_datos->>'temporada'), coalesce(p_datos->>'origen', 'manual'))
  returning id into v_temp;

  for c in select * from jsonb_array_elements(coalesce(p_datos->'competiciones', '[]'::jsonb)) loop
    i := i + 1;
    insert into palmares_competiciones (temporada_id, federacion_id, tipo, nombre, orden, participantes, puntos)
    values (v_temp, p_federacion_id, c->>'tipo', trim(c->>'nombre'), coalesce((c->>'orden')::int, i),
            (c->>'participantes')::int, nullif(c->'puntos', 'null'::jsonb))
    returning id into v_comp;
    for e in select * from jsonb_array_elements(coalesce(c->'entradas', '[]'::jsonb)) loop
      insert into palmares (competicion_id, federacion_id, puesto, participante_id, equipo,
                            puntos_comp, movimiento, puntos_manual, detalle)
      values (v_comp, p_federacion_id, (e->>'puesto')::int, (e->>'participante_id')::uuid, trim(e->>'equipo'),
              (e->>'puntos_comp')::numeric, e->>'movimiento', (e->>'puntos_manual')::numeric, e->>'detalle');
    end loop;
  end loop;

  for r in select * from jsonb_array_elements(coalesce(p_datos->'records', '[]'::jsonb)) loop
    insert into palmares_records (temporada_id, federacion_id, tipo, valor, participante_id, equipo, detalle)
    values (v_temp, p_federacion_id, r->>'tipo', (r->>'valor')::numeric, (r->>'participante_id')::uuid,
            trim(r->>'equipo'), r->>'detalle');
  end loop;

  return v_temp;
end;
$$;

-- ─── 6. Cerrar la temporada: palmarés + reinicio, todo o nada ────
-- Con p_datos null solo reinicia (igual que reiniciar_federacion).
create or replace function cerrar_temporada(p_federacion_id uuid, p_datos jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_temp bigint;
begin
  if p_datos is not null then
    v_temp := guardar_palmares_temporada(p_federacion_id, p_datos || '{"origen":"app"}'::jsonb);
  end if;
  perform reiniciar_federacion(p_federacion_id);
  return jsonb_build_object('ok', true, 'temporada_id', v_temp);
end;
$$;

revoke all on function guardar_palmares_temporada(uuid, jsonb) from public, anon;
revoke all on function cerrar_temporada(uuid, jsonb)           from public, anon;
grant execute on function guardar_palmares_temporada(uuid, jsonb) to authenticated;
grant execute on function cerrar_temporada(uuid, jsonb)           to authenticated;
