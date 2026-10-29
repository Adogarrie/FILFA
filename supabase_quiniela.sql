-- ═══════════════════════════════════════════════════════════════
-- FILFA — Quiniela de la jornada
--
-- Cada jornada de la Liga Fantástica tiene una quiniela con los partidos
-- asociados a ella: los de la Liga FILFA cuya jornada H2H está asignada a
-- esa jornada fantasy (h2h_jornada_config) y los de torneos con
-- jornada_fantasy = jornada. Cada partido es 1·X·2 (por defecto) o
-- resultado exacto (goles), y el admin puede excluirlo.
--
-- · La quiniela se crea sola (preparar_quiniela) la primera vez que alguien
--   la abre y se sincroniza con los partidos mientras siga abierta.
-- · Los pronósticos se pueden enviar/cambiar hasta el cierre de
--   alineaciones de la jornada (jornadas_cierre) o, si no hay cierre, hasta
--   que se cierra y archiva la jornada. Antes de ese momento solo los ve su
--   equipo, el admin y los delegados de quinielas; después, todos.
-- · resolver_quiniela cuenta los aciertos cuando la jornada está archivada
--   y todos los partidos tienen resultado: cobra el coste a quien la envió,
--   reparte el premio entre los que más aciertan, guarda el resultado de
--   cada equipo (quiniela_resultados) y publica el resumen en el Tablón.
--   Se resuelve una única vez (idempotente).
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Configuración por federación ────────────────────────────
alter table federaciones
  add column if not exists quiniela_habilitada boolean not null default false,
  add column if not exists quiniela_premio     numeric not null default 1000000,
  add column if not exists quiniela_coste      numeric not null default 0;

-- ─── 2. Tablas ──────────────────────────────────────────────────
create table if not exists quinielas (
  id            bigserial primary key,
  federacion_id uuid not null references federaciones(id) on delete cascade,
  jornada       int  not null,                       -- jornada de la Liga Fantástica
  estado        text not null default 'abierta' check (estado in ('abierta', 'resuelta')),
  premio        numeric,                             -- premio y coste aplicados al resolver
  coste         numeric,
  resuelta_at   timestamptz,
  created_at    timestamptz not null default now(),
  unique (federacion_id, jornada)
);

create table if not exists quiniela_partidos (
  id              bigserial primary key,
  quiniela_id     bigint not null references quinielas(id) on delete cascade,
  origen          text   not null check (origen in ('h2h', 'torneo')),
  partido_id      text   not null,                   -- h2h_partidos.id o partidos_competicion.id
  tipo            text   not null default '1x2' check (tipo in ('1x2', 'exacto')),
  excluido        boolean not null default false,
  competicion     text   not null,                   -- 'Primera', 'Segunda', nombre del torneo…
  orden           int    not null default 0,
  goles_local     int,                               -- resultado copiado al resolver
  goles_visitante int,
  unique (quiniela_id, origen, partido_id)
);

create table if not exists quiniela_pronosticos (
  quiniela_partido_id bigint not null references quiniela_partidos(id) on delete cascade,
  participante_id     uuid   not null references participantes(id) on delete cascade,
  quiniela_id         bigint not null references quinielas(id) on delete cascade,
  signo               text check (signo in ('1', 'X', '2')),
  goles_local         smallint check (goles_local between 0 and 30),
  goles_visitante     smallint check (goles_visitante between 0 and 30),
  acertado            boolean,                       -- lo rellena resolver_quiniela
  updated_at          timestamptz not null default now(),
  primary key (quiniela_partido_id, participante_id)
);
create index if not exists quiniela_pronosticos_q_idx on quiniela_pronosticos(quiniela_id);

-- Resultado de cada equipo en cada quiniela resuelta (clasificación).
create table if not exists quiniela_resultados (
  quiniela_id     bigint not null references quinielas(id) on delete cascade,
  federacion_id   uuid   not null references federaciones(id) on delete cascade,
  participante_id uuid   not null references participantes(id) on delete cascade,
  jornada         int    not null,
  aciertos        int    not null default 0,
  exactos         int    not null default 0,         -- aciertos de resultado exacto (desempate)
  por_competicion jsonb  not null default '{}',      -- { "Primera": 3, "Torneo X": 1 }
  ganador         boolean not null default false,
  premio          numeric not null default 0,
  coste           numeric not null default 0,
  primary key (quiniela_id, participante_id)
);
create index if not exists quiniela_resultados_fed_idx on quiniela_resultados(federacion_id);

create table if not exists quiniela_delegados (
  id              serial primary key,
  federacion_id   uuid not null references federaciones(id) on delete cascade,
  participante_id uuid not null references participantes(id) on delete cascade,
  created_at      timestamptz default now(),
  unique (federacion_id, participante_id)
);

-- ─── 3. Funciones auxiliares ────────────────────────────────────
create or replace function es_miembro_federacion(p_federacion_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from federaciones where id = p_federacion_id and admin_user_id = auth.uid())
      or exists (select 1 from participantes where federacion_id = p_federacion_id and user_id = auth.uid())
$$;

-- Admin de la federación o delegado de quinielas.
create or replace function es_delegado_quiniela(p_federacion_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from federaciones where id = p_federacion_id and admin_user_id = auth.uid())
      or exists (
        select 1 from quiniela_delegados d
        join participantes pa on pa.id = d.participante_id
        where d.federacion_id = p_federacion_id and pa.user_id = auth.uid()
      )
$$;

-- Plazo vencido: resuelta, pasado el cierre de alineaciones o jornada archivada.
create or replace function quiniela_cerrada(p_quiniela_id bigint)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((
    select q.estado <> 'abierta'
        or exists (select 1 from jornadas_cierre c
                    where c.federacion_id = q.federacion_id and c.jornada = q.jornada and c.cierre <= now())
        or exists (select 1 from alineaciones_snapshot s
                    where s.federacion_id = q.federacion_id and s.jornada = q.jornada)
      from quinielas q where q.id = p_quiniela_id), true)
$$;

-- Un pronóstico lo ve su equipo, el admin y los delegados; los demás
-- miembros, solo cuando ha vencido el plazo.
create or replace function quiniela_pronostico_visible(p_quiniela_id bigint, p_participante_id uuid)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare v_fed uuid;
begin
  select federacion_id into v_fed from quinielas where id = p_quiniela_id;
  if v_fed is null then return false; end if;
  return exists (select 1 from participantes where id = p_participante_id and user_id = auth.uid())
      or es_delegado_quiniela(v_fed)
      or (es_miembro_federacion(v_fed) and quiniela_cerrada(p_quiniela_id));
end;
$$;

grant execute on function es_miembro_federacion(uuid)                  to authenticated;
grant execute on function es_delegado_quiniela(uuid)                   to authenticated;
grant execute on function quiniela_cerrada(bigint)                     to authenticated;
grant execute on function quiniela_pronostico_visible(bigint, uuid)    to authenticated;

-- ─── 4. Triggers ────────────────────────────────────────────────
-- Pronósticos: solo dentro de plazo, coherentes con el tipo del partido y
-- sin poder tocar `acertado`. resolver_quiniela se salta la comprobación.
create or replace function quiniela_pronosticos_validar()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_qp  quiniela_partidos;
  v_fed uuid;
begin
  if current_setting('filfa.quiniela_resolviendo', true) = '1' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'DELETE' then
    -- Los borrados en cascada (quiniela o equipo eliminados) siempre se permiten.
    if exists (select 1 from quinielas where id = old.quiniela_id)
       and exists (select 1 from participantes where id = old.participante_id)
       and quiniela_cerrada(old.quiniela_id) then
      raise exception 'quiniela_cerrada';
    end if;
    return old;
  end if;
  select * into v_qp from quiniela_partidos where id = new.quiniela_partido_id;
  if not found or v_qp.excluido then raise exception 'partido_no_valido'; end if;
  new.quiniela_id := v_qp.quiniela_id;
  if quiniela_cerrada(new.quiniela_id) then raise exception 'quiniela_cerrada'; end if;
  select federacion_id into v_fed from quinielas where id = new.quiniela_id;
  if not exists (select 1 from participantes where id = new.participante_id and federacion_id = v_fed) then
    raise exception 'participante_no_valido';
  end if;
  if v_qp.tipo = '1x2' then
    if new.signo is null then raise exception 'falta_signo'; end if;
    new.goles_local := null; new.goles_visitante := null;
  else
    if new.goles_local is null or new.goles_visitante is null then raise exception 'faltan_goles'; end if;
    new.signo := null;
  end if;
  new.acertado   := null;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists quiniela_pronosticos_validar on quiniela_pronosticos;
create trigger quiniela_pronosticos_validar
  before insert or update or delete on quiniela_pronosticos
  for each row execute function quiniela_pronosticos_validar();

-- Partidos: el admin solo puede cambiar tipo/excluido mientras esté
-- abierta. Al cambiar de tipo se borran los pronósticos de ese partido
-- (ya no encajan: signo ↔ goles).
create or replace function quiniela_partidos_validar()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if current_setting('filfa.quiniela_resolviendo', true) = '1' then return new; end if;
  if (new.tipo, new.excluido) is distinct from (old.tipo, old.excluido) then
    if quiniela_cerrada(old.quiniela_id) then raise exception 'quiniela_cerrada'; end if;
    if new.tipo <> old.tipo then
      delete from quiniela_pronosticos where quiniela_partido_id = old.id;
    end if;
  end if;
  -- El resto de columnas no se pueden cambiar desde la app.
  new.quiniela_id := old.quiniela_id; new.origen := old.origen; new.partido_id := old.partido_id;
  new.competicion := old.competicion; new.orden := old.orden;
  new.goles_local := old.goles_local; new.goles_visitante := old.goles_visitante;
  return new;
end;
$$;

drop trigger if exists quiniela_partidos_validar on quiniela_partidos;
create trigger quiniela_partidos_validar
  before update on quiniela_partidos
  for each row execute function quiniela_partidos_validar();

-- ─── 5. RLS ─────────────────────────────────────────────────────
alter table quinielas            enable row level security;
alter table quiniela_partidos    enable row level security;
alter table quiniela_pronosticos enable row level security;
alter table quiniela_resultados  enable row level security;
alter table quiniela_delegados   enable row level security;

drop policy if exists "Ver quinielas" on quinielas;
create policy "Ver quinielas" on quinielas for select
  using (es_miembro_federacion(federacion_id));
-- Borrar (reinicio de temporada) solo el admin; se crean con preparar_quiniela.
drop policy if exists "Admin borra quinielas" on quinielas;
create policy "Admin borra quinielas" on quinielas for delete
  using (federacion_id in (select id from federaciones where admin_user_id = auth.uid()));

drop policy if exists "Ver partidos quiniela" on quiniela_partidos;
create policy "Ver partidos quiniela" on quiniela_partidos for select
  using (exists (select 1 from quinielas q where q.id = quiniela_id and es_miembro_federacion(q.federacion_id)));
drop policy if exists "Admin ajusta partidos quiniela" on quiniela_partidos;
create policy "Admin ajusta partidos quiniela" on quiniela_partidos for update
  using (exists (select 1 from quinielas q join federaciones f on f.id = q.federacion_id
                  where q.id = quiniela_id and f.admin_user_id = auth.uid()));

drop policy if exists "Ver pronosticos" on quiniela_pronosticos;
create policy "Ver pronosticos" on quiniela_pronosticos for select
  using (quiniela_pronostico_visible(quiniela_id, participante_id));
drop policy if exists "Equipo escribe sus pronosticos" on quiniela_pronosticos;
create policy "Equipo escribe sus pronosticos" on quiniela_pronosticos for all
  using      (participante_id in (select id from participantes where user_id = auth.uid()))
  with check (participante_id in (select id from participantes where user_id = auth.uid()));

drop policy if exists "Ver resultados quiniela" on quiniela_resultados;
create policy "Ver resultados quiniela" on quiniela_resultados for select
  using (es_miembro_federacion(federacion_id));

drop policy if exists "Ver delegados quiniela" on quiniela_delegados;
create policy "Ver delegados quiniela" on quiniela_delegados for select using (true);
drop policy if exists "Admin gestiona delegados quiniela" on quiniela_delegados;
create policy "Admin gestiona delegados quiniela" on quiniela_delegados for all
  using      (federacion_id in (select id from federaciones where admin_user_id = auth.uid()))
  with check (federacion_id in (select id from federaciones where admin_user_id = auth.uid()));

grant select, delete                 on quinielas            to authenticated;
grant select, update (tipo, excluido) on quiniela_partidos   to authenticated;
grant select, insert, update, delete on quiniela_pronosticos to authenticated;
grant select                         on quiniela_resultados  to authenticated;
grant select, insert, delete         on quiniela_delegados   to authenticated;
grant usage, select on sequence quiniela_delegados_id_seq    to authenticated;

-- Partidos que corresponden a la quiniela de una jornada fantasy.
create or replace function quiniela_candidatos(p_federacion_id uuid, p_jornada int)
returns table (origen text, partido_id text, competicion text, orden int)
language sql stable security definer set search_path = public
as $$
  select 'h2h', hp.id::text, coalesce(d.nombre, 'Liga FILFA'), coalesce(hp.division_id, 0)
    from h2h_partidos hp
    join h2h_jornada_config c
      on c.federacion_id = hp.federacion_id and c.jornada_h2h = hp.jornada
     and c.division_id is not distinct from hp.division_id
    left join divisiones d on d.id = hp.division_id
   where hp.federacion_id = p_federacion_id and c.jornada_fantasy = p_jornada
  union all
  select 'torneo', pc.id::text, co.nombre, 1000
    from partidos_competicion pc
    join fases_competicion f on f.id = pc.fase_id
    join competiciones co    on co.id = f.competicion_id
   where co.federacion_id = p_federacion_id and pc.jornada_fantasy = p_jornada
     and pc.participante_local_id is not null and pc.participante_visitante_id is not null
$$;

-- ─── 6. preparar_quiniela ───────────────────────────────────────
-- Devuelve la quiniela de la jornada con sus partidos (nombres de equipo
-- por id y resultado si ya lo hay). Si no existe y hay partidos, la crea;
-- mientras siga abierta la sincroniza con los partidos asignados a la
-- jornada (añade los nuevos y quita los que ya no le corresponden).
-- Devuelve null si la quiniela no está habilitada o no hay partidos.
create or replace function preparar_quiniela(p_federacion_id uuid, p_jornada int)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_q    quinielas;
  v_cand int;
begin
  if not es_miembro_federacion(p_federacion_id) then raise exception 'no_autorizado'; end if;
  if not coalesce((select quiniela_habilitada from federaciones where id = p_federacion_id), false) then
    return null;
  end if;

  select count(*) into v_cand from quiniela_candidatos(p_federacion_id, p_jornada);

  select * into v_q from quinielas where federacion_id = p_federacion_id and jornada = p_jornada;
  if not found then
    -- No se crea para jornadas ya archivadas ni sin partidos.
    if v_cand = 0 or exists (select 1 from alineaciones_snapshot
                              where federacion_id = p_federacion_id and jornada = p_jornada) then
      return null;
    end if;
    insert into quinielas (federacion_id, jornada) values (p_federacion_id, p_jornada)
      on conflict (federacion_id, jornada) do nothing;
    select * into v_q from quinielas where federacion_id = p_federacion_id and jornada = p_jornada;
  end if;

  if not quiniela_cerrada(v_q.id) then
    insert into quiniela_partidos (quiniela_id, origen, partido_id, competicion, orden)
      select v_q.id, origen, partido_id, competicion, orden from quiniela_candidatos(p_federacion_id, p_jornada)
      on conflict (quiniela_id, origen, partido_id) do nothing;
    delete from quiniela_partidos qp
     where qp.quiniela_id = v_q.id
       and not exists (select 1 from quiniela_candidatos(p_federacion_id, p_jornada) c where c.origen = qp.origen and c.partido_id = qp.partido_id);
  end if;

  return jsonb_build_object(
    'quiniela', to_jsonb(v_q) || jsonb_build_object(
      'cerrada', quiniela_cerrada(v_q.id),
      'cierre',  (select cierre from jornadas_cierre where federacion_id = p_federacion_id and jornada = p_jornada),
      'archivada', exists (select 1 from alineaciones_snapshot where federacion_id = p_federacion_id and jornada = p_jornada)),
    'partidos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', qp.id, 'origen', qp.origen, 'tipo', qp.tipo, 'excluido', qp.excluido,
               'competicion', qp.competicion, 'orden', qp.orden,
               'nombre', pc.nombre,
               'local_id',     coalesce(hp.local_id, pc.participante_local_id),
               'visitante_id', coalesce(hp.visitante_id, pc.participante_visitante_id),
               'goles_local',     coalesce(qp.goles_local, hp.pts_local::int, pc.goles_local::int),
               'goles_visitante', coalesce(qp.goles_visitante, hp.pts_visitante::int, pc.goles_visitante::int))
             order by qp.orden, qp.competicion, qp.id)
        from quiniela_partidos qp
        left join h2h_partidos hp         on qp.origen = 'h2h'    and hp.id::text = qp.partido_id
        left join partidos_competicion pc on qp.origen = 'torneo' and pc.id::text = qp.partido_id
       where qp.quiniela_id = v_q.id), '[]'::jsonb));
end;
$$;

grant execute on function preparar_quiniela(uuid, int) to authenticated;

-- Formato del Tablón: escapa markdown en los nombres y muestra millones
-- como en la app (1M, 0,5M, 0,33M).
create or replace function quiniela_md(p text)
returns text language sql immutable
as $$ select regexp_replace(coalesce(p, '?'), '([\\`*_\[\]#<>|~])', '\\\1', 'g') $$;

create or replace function quiniela_millones(p numeric)
returns text language sql immutable
as $$ select replace(rtrim(rtrim(to_char(p / 1000000.0, 'FM999999990.00'), '0'), '.'), '.', ',') || 'M' $$;

-- ─── 7. resolver_quiniela ───────────────────────────────────────
-- Devuelve { estado }: 'resuelta' | 'ya_resuelta' | 'sin_quiniela' |
-- 'jornada_abierta' (aún no se ha cerrado y archivado) | 'pendiente'
-- (faltan resultados; incluye `faltan`).
create or replace function resolver_quiniela(p_federacion_id uuid, p_jornada int)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_q        quinielas;
  v_total    int;
  v_faltan   int;
  v_premio   numeric;
  v_coste    numeric;
  v_max      int;
  v_ganan    int;
  v_reparto  numeric := 0;
  v_texto    text;
  v_lineas   text;
  v_sin      text;
begin
  if not (es_admin_o_mod(p_federacion_id) or es_delegado_quiniela(p_federacion_id)) then
    raise exception 'no_autorizado';
  end if;
  select * into v_q from quinielas
   where federacion_id = p_federacion_id and jornada = p_jornada for update;
  if not found then return jsonb_build_object('estado', 'sin_quiniela'); end if;
  if v_q.estado = 'resuelta' then return jsonb_build_object('estado', 'ya_resuelta'); end if;
  if not exists (select 1 from alineaciones_snapshot where federacion_id = p_federacion_id and jornada = p_jornada) then
    return jsonb_build_object('estado', 'jornada_abierta');
  end if;

  perform set_config('filfa.quiniela_resolviendo', '1', true);

  -- Resultados (goles) de cada partido.
  update quiniela_partidos qp
     set goles_local = hp.pts_local::int, goles_visitante = hp.pts_visitante::int
    from h2h_partidos hp
   where qp.quiniela_id = v_q.id and qp.origen = 'h2h' and hp.id::text = qp.partido_id;
  update quiniela_partidos qp
     set goles_local = pc.goles_local::int, goles_visitante = pc.goles_visitante::int
    from partidos_competicion pc
   where qp.quiniela_id = v_q.id and qp.origen = 'torneo' and pc.id::text = qp.partido_id;

  select count(*), count(*) filter (where goles_local is null or goles_visitante is null)
    into v_total, v_faltan
    from quiniela_partidos where quiniela_id = v_q.id and not excluido;
  if v_faltan > 0 then
    return jsonb_build_object('estado', 'pendiente', 'faltan', v_faltan);
  end if;

  -- Aciertos.
  update quiniela_pronosticos pr
     set acertado = case
           when qp.excluido then null
           when qp.tipo = 'exacto' then coalesce(pr.goles_local = qp.goles_local and pr.goles_visitante = qp.goles_visitante, false)
           else coalesce(pr.signo = case when qp.goles_local > qp.goles_visitante then '1'
                                         when qp.goles_local = qp.goles_visitante then 'X' else '2' end, false)
         end
    from quiniela_partidos qp
   where pr.quiniela_partido_id = qp.id and qp.quiniela_id = v_q.id;

  select coalesce(quiniela_premio, 0), coalesce(quiniela_coste, 0) into v_premio, v_coste
    from federaciones where id = p_federacion_id;

  -- Resultado por equipo (solo los que enviaron algún pronóstico).
  with base as (
    select pr.participante_id, qp.competicion, qp.tipo, coalesce(pr.acertado, false) as acierto
      from quiniela_pronosticos pr
      join quiniela_partidos qp on qp.id = pr.quiniela_partido_id
     where qp.quiniela_id = v_q.id and not qp.excluido
  ), por_comp as (
    select participante_id, competicion, count(*) filter (where acierto) as n
      from base group by participante_id, competicion
  ), tot as (
    select participante_id,
           count(*) filter (where acierto) as aciertos,
           count(*) filter (where acierto and tipo = 'exacto') as exactos
      from base group by participante_id
  )
  insert into quiniela_resultados
    (quiniela_id, federacion_id, participante_id, jornada, aciertos, exactos, por_competicion, coste)
  select v_q.id, p_federacion_id, t.participante_id, p_jornada, t.aciertos, t.exactos,
         coalesce((select jsonb_object_agg(pc.competicion, pc.n) from por_comp pc
                    where pc.participante_id = t.participante_id), '{}'::jsonb),
         v_coste
    from tot t
  on conflict (quiniela_id, participante_id) do nothing;

  -- Ganadores: los que más aciertan (con al menos uno); el premio se reparte.
  select max(aciertos) into v_max from quiniela_resultados where quiniela_id = v_q.id;
  if coalesce(v_max, 0) > 0 then
    select count(*) into v_ganan from quiniela_resultados where quiniela_id = v_q.id and aciertos = v_max;
    v_reparto := round(v_premio / v_ganan, 2);
    update quiniela_resultados set ganador = true, premio = v_reparto
     where quiniela_id = v_q.id and aciertos = v_max;
  end if;

  update participantes pa
     set presupuesto = pa.presupuesto - r.coste + r.premio
    from quiniela_resultados r
   where r.quiniela_id = v_q.id and pa.id = r.participante_id and (r.coste <> 0 or r.premio <> 0);

  update quinielas
     set estado = 'resuelta', resuelta_at = now(), premio = v_premio, coste = v_coste
   where id = v_q.id;

  -- Resumen en el Tablón (markdown, una línea por equipo).
  select string_agg(
           format('**%sº** %s — **%s acierto%s**%s%s',
                  r.rk, quiniela_md(pa.nombre), r.aciertos, case when r.aciertos = 1 then '' else 's' end,
                  case when r.exactos > 0 then format(' (%s exacto%s)', r.exactos, case when r.exactos = 1 then '' else 's' end) else '' end,
                  case when r.premio > 0 then ' 💰 ' || quiniela_millones(r.premio) else '' end),
           E'  \n' order by r.aciertos desc, r.exactos desc, pa.nombre)
    into v_lineas
    from (select *, rank() over (order by aciertos desc) as rk
            from quiniela_resultados where quiniela_id = v_q.id) r
    join participantes pa on pa.id = r.participante_id;

  select string_agg(quiniela_md(pa.nombre), ', ' order by pa.nombre) into v_sin
    from participantes pa
   where pa.federacion_id = p_federacion_id
     and not exists (select 1 from quiniela_resultados r where r.quiniela_id = v_q.id and r.participante_id = pa.id);

  v_texto := format('**🎯 Quiniela J%s** · %s partido%s', p_jornada, v_total, case when v_total = 1 then '' else 's' end)
          || E'  \n' || coalesce(v_lineas, 'Nadie ha enviado la quiniela.')
          || case when v_sin is not null and v_lineas is not null then E'  \nSin enviar: ' || v_sin else '' end
          || case when v_coste > 0 then E'  \nCoste por participar: ' || quiniela_millones(v_coste) else '' end;
  insert into anuncios (federacion_id, tipo, texto, actor_nombre, estado)
  values (p_federacion_id, 'quiniela', v_texto, null, 'aprobado');

  return jsonb_build_object('estado', 'resuelta', 'ganadores', coalesce(v_ganan, 0), 'max', coalesce(v_max, 0));
end;
$$;

grant execute on function resolver_quiniela(uuid, int) to authenticated;

-- Uso interno de preparar_quiniela (no se expone a la API).
revoke execute on function quiniela_candidatos(uuid, int) from public, anon, authenticated;
