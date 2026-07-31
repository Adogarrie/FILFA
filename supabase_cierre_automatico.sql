-- ═══════════════════════════════════════════════════════════════
-- FILFA — Cierre automático diario de pujas
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Columnas ────────────────────────────────────────────────
alter table federaciones
  add column if not exists hora_cierre_pujas time default null;

alter table pujas
  add column if not exists created_at timestamptz default now();
update pujas set created_at = now() where created_at is null;

-- ─── 2. Tabla de registro de cierres ────────────────────────────
create table if not exists log_cierres_pujas (
  id            serial primary key,
  federacion_id uuid not null references federaciones(id) on delete cascade,
  fecha_cierre  date not null,
  hora_cierre   time not null,
  procesado_en  timestamptz not null default now(),
  firmados      int not null default 0,
  unique(federacion_id, fecha_cierre, hora_cierre)
);

-- ─── Migración idempotente para instalaciones previas ───────────
-- 1. Añadir columna si falta (antes de usarla en los siguientes pasos)
alter table log_cierres_pujas
  add column if not exists hora_cierre time;

-- 2. Eliminar duplicados bajo el constraint definitivo de 3 columnas
delete from log_cierres_pujas a
using log_cierres_pujas b
where a.federacion_id = b.federacion_id
  and a.fecha_cierre  = b.fecha_cierre
  and a.hora_cierre   = b.hora_cierre
  and a.id < b.id;

-- 3. Reemplazar cualquier constraint previo (2 o 3 columnas) por el definitivo
alter table log_cierres_pujas
  drop constraint if exists log_cierres_pujas_federacion_id_fecha_cierre_key;
alter table log_cierres_pujas
  drop constraint if exists log_cierres_pujas_federacion_id_fecha_cierre_hora_cierre_key;
alter table log_cierres_pujas
  add constraint log_cierres_pujas_federacion_id_fecha_cierre_hora_cierre_key
  unique (federacion_id, fecha_cierre, hora_cierre);

alter table log_cierres_pujas enable row level security;
grant select on log_cierres_pujas to authenticated;

drop policy if exists "Ver log cierres" on log_cierres_pujas;
create policy "Ver log cierres"
  on log_cierres_pujas for select using (true);

-- ─── 3. Función principal ────────────────────────────────────────
drop function if exists procesar_cierre_pujas(uuid);
drop function if exists procesar_cierre_pujas(uuid, boolean);

create function procesar_cierre_pujas(p_federacion_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_hora        time;
  v_fecha       date;
  v_ts          timestamptz;
  v_firmados    int := 0;
  v_jug_id      uuid;
  v_ganadora    record;
  v_cnt_plant   int;
  v_pendiente   boolean;
  v_resto_pujas text;
  v_max_jug     int;
begin

  -- ── 1. Verificar mercado activo y hora configurada ────────────
  select hora_cierre_pujas into v_hora
    from federaciones
   where id = p_federacion_id
     and ventas_habilitadas = true;

  if not found or v_hora is null then
    return jsonb_build_object('ok', true, 'skipped', true,
                              'reason', 'sin_hora_o_mercado_cerrado');
  end if;

  v_max_jug := get_max_jugadores(p_federacion_id);

  -- ── 2. Calcular timestamp del cierre (Madrid → UTC) ───────────
  v_fecha := (now() at time zone 'Europe/Madrid')::date;
  v_ts    := (v_fecha::text || ' ' || v_hora::text)::timestamp
               at time zone 'Europe/Madrid';

  if now() < v_ts then
    v_fecha := v_fecha - 1;
    v_ts    := (v_fecha::text || ' ' || v_hora::text)::timestamp
                 at time zone 'Europe/Madrid';
  end if;

  if now() < v_ts then
    return jsonb_build_object('ok', true, 'skipped', true,
                              'reason', 'sin_cierre_pendiente');
  end if;

  -- ── 3. Idempotencia ───────────────────────────────────────────
  if exists (
    select 1 from log_cierres_pujas
     where federacion_id = p_federacion_id
       and fecha_cierre  = v_fecha
       and hora_cierre   = v_hora
  ) then
    return jsonb_build_object('ok', true, 'skipped', true,
                              'reason', 'ya_procesado',
                              'fecha', v_fecha, 'hora', v_hora);
  end if;

  -- ── 4. Lock de fila para serializar llamadas concurrentes ─────
  perform 1 from federaciones where id = p_federacion_id for update;

  if exists (
    select 1 from log_cierres_pujas
     where federacion_id = p_federacion_id
       and fecha_cierre  = v_fecha
       and hora_cierre   = v_hora
  ) then
    return jsonb_build_object('ok', true, 'skipped', true,
                              'reason', 'ya_procesado',
                              'fecha', v_fecha, 'hora', v_hora);
  end if;

  -- ── 5. Procesar cada jugador con pujas sin resolver ───────────
  for v_jug_id in (
    select distinct p.jugador_id
      from pujas p
      join participantes pa on pa.id = p.participante_id
     where pa.federacion_id = p_federacion_id
       and p.resuelta       = false
       and p.created_at    <= v_ts
     order by p.jugador_id
  ) loop
    begin

      -- Puja ganadora: mayor cantidad; empate → más antigua
      select p.id            as puja_id,
             p.participante_id,
             p.cantidad,
             pa.presupuesto  as presupuesto,
             pa.nombre       as nombre_equipo,
             pa.division_id  as division_id,
             ju.posicion     as jugador_posicion,
             ju.equipo       as jugador_equipo,
             ju.nombre       as jugador_nombre
        into v_ganadora
        from pujas p
        join participantes pa on pa.id = p.participante_id
        join jugadores     ju on ju.id = p.jugador_id
       where p.jugador_id     = v_jug_id
         and pa.federacion_id = p_federacion_id
         and p.resuelta       = false
         and p.created_at    <= v_ts
       order by p.cantidad desc, p.created_at asc
       limit 1;

      if not found then continue; end if;

      -- ── 5a. Jugador ya fichado en la federación ────────────────
      if exists (
        select 1 from plantillas pl
          join participantes pa on pa.id = pl.participante_id
         where pl.jugador_id = v_jug_id and pa.federacion_id = p_federacion_id
      ) or exists (
        select 1 from fichajes_pendientes fp
          join participantes pa on pa.id = fp.participante_id
         where fp.jugador_id = v_jug_id and pa.federacion_id = p_federacion_id
      ) then
        update pujas set resuelta = true, ganadora = false
         where jugador_id = v_jug_id and resuelta = false
           and participante_id in (
             select id from participantes where federacion_id = p_federacion_id);
        continue;
      end if;

      -- ── 5b. Portería única por división ───────────────────────
      if v_ganadora.jugador_posicion = 'POR' then
        if exists (
          select 1 from plantillas pl
            join participantes pa on pa.id = pl.participante_id
            join jugadores     ju on ju.id = pl.jugador_id
           where ju.posicion = 'POR' and ju.equipo = v_ganadora.jugador_equipo
             and pa.division_id  = v_ganadora.division_id
             and pa.federacion_id = p_federacion_id
        ) or exists (
          select 1 from fichajes_pendientes fp
            join participantes pa on pa.id = fp.participante_id
            join jugadores     ju on ju.id = fp.jugador_id
           where ju.posicion = 'POR' and ju.equipo = v_ganadora.jugador_equipo
             and pa.division_id  = v_ganadora.division_id
             and pa.federacion_id = p_federacion_id
        ) then
          update pujas set resuelta = true, ganadora = false
           where jugador_id = v_jug_id and resuelta = false
             and participante_id in (
               select id from participantes where federacion_id = p_federacion_id);
          continue;
        end if;
      end if;

      -- ── 5c. Plantilla llena → fichaje pendiente ───────────────
      select count(*) into v_cnt_plant
        from plantillas where participante_id = v_ganadora.participante_id;
      v_pendiente := (v_cnt_plant >= v_max_jug);

      if v_pendiente then
        insert into fichajes_pendientes (participante_id, jugador_id, precio_compra)
        values (v_ganadora.participante_id, v_jug_id, v_ganadora.cantidad)
        on conflict (participante_id, jugador_id) do nothing;
      else
        insert into plantillas (participante_id, jugador_id, precio_compra)
        values (v_ganadora.participante_id, v_jug_id, v_ganadora.cantidad)
        on conflict (participante_id, jugador_id) do nothing;
      end if;

      -- ── 5d. Descontar presupuesto ─────────────────────────────
      update participantes
         set presupuesto = presupuesto - v_ganadora.cantidad
       where id = v_ganadora.participante_id;

      -- ── 5e. Resolver todas las pujas del jugador ──────────────
      update pujas set resuelta = true, ganadora = false
       where jugador_id = v_jug_id and resuelta = false
         and participante_id in (
           select id from participantes where federacion_id = p_federacion_id);

      update pujas set ganadora = true where id = v_ganadora.puja_id;

      -- ── 5f. Lista de pujas perdedoras ─────────────────────────
      select string_agg(
               '- ' || pa.nombre || ' pujó ' || to_char(p.cantidad, 'FM999G999G999') || ' €',
               chr(10) order by p.cantidad desc
             )
        into v_resto_pujas
        from pujas p
        join participantes pa on pa.id = p.participante_id
       where p.jugador_id     = v_jug_id
         and pa.federacion_id = p_federacion_id
         and p.created_at    <= v_ts
         and p.id             <> v_ganadora.puja_id;

      -- ── 5g. Anuncio individual en el tablón ───────────────────
      insert into anuncios (federacion_id, tipo, texto)
      values (
        p_federacion_id, 'fichaje',
        v_ganadora.nombre_equipo
          || case v_ganadora.jugador_posicion
               when 'POR' then ' ficha la Portería de ' || v_ganadora.jugador_equipo
               else ' ficha a ' || v_ganadora.jugador_nombre
                    || ' (' || v_ganadora.jugador_equipo || ')'
             end
          || ' por ' || to_char(v_ganadora.cantidad, 'FM999G999G999') || ' €'
          || case when v_pendiente then ' (pendiente de plaza)' else '' end
          || '.'
          || case when v_resto_pujas is not null
               then chr(10) || 'Resto de pujas:' || chr(10) || v_resto_pujas
               else ''
             end
      );

      v_firmados := v_firmados + 1;

    exception when others then
      null; -- saltar este jugador y continuar con el resto
    end;
  end loop;

  -- ── 6. Registrar el cierre ─────────────────────────────────────
  insert into log_cierres_pujas (federacion_id, fecha_cierre, hora_cierre, firmados)
  values (p_federacion_id, v_fecha, v_hora, v_firmados)
  on conflict (federacion_id, fecha_cierre, hora_cierre) do nothing;

  -- ── 7. Resumen en el tablón ───────────────────────────────────
  insert into anuncios (federacion_id, tipo, texto)
  values (
    p_federacion_id, 'admin',
    'Cierre de pujas ' || to_char(v_fecha, 'DD/MM/YYYY')
    || ' a las ' || to_char(v_hora, 'HH24:MI') || 'h — '
    || case
         when v_firmados = 0 then 'sin adjudicaciones'
         when v_firmados = 1 then '1 jugador adjudicado'
         else v_firmados || ' jugadores adjudicados'
       end
  );

  return jsonb_build_object('ok', true, 'fecha', v_fecha::text,
                            'hora', v_hora::text, 'firmados', v_firmados);
end;
$$;

grant execute on function procesar_cierre_pujas(uuid) to authenticated;
