-- ═══════════════════════════════════════════════════════════════
-- FILFA — Cierre automático de pujas v2 (reimplementación limpia)
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 0. Limpiar implementación anterior ─────────────────────────
drop function if exists procesar_cierre_pujas(uuid);
drop function if exists procesar_cierre_pujas(uuid, boolean);
drop function if exists procesar_cierre_pujas(uuid, boolean, boolean);
drop table   if exists log_cierres_pujas;

-- ─── 1. Columna hora_cierre_pujas en federaciones ────────────────
alter table federaciones
  add column if not exists hora_cierre_pujas time default null;

-- ─── 2. Tabla de registro de cierres ─────────────────────────────
-- Clave: (federacion, fecha, hora) — permite múltiples cierres por día
-- si el admin cambia la hora, sin bloquear el nuevo cierre.
create table log_cierres_pujas (
  id            serial      primary key,
  federacion_id uuid        not null references federaciones(id) on delete cascade,
  fecha_cierre  date        not null,
  hora_cierre   time        not null,
  procesado_en  timestamptz not null default now(),
  firmados      int         not null default 0,
  unique (federacion_id, fecha_cierre, hora_cierre)
);

alter table log_cierres_pujas enable row level security;

create policy "Ver log cierres"
  on log_cierres_pujas for select
  using (
    federacion_id in (
      select id            from federaciones  where admin_user_id = auth.uid()
      union
      select federacion_id from participantes where user_id       = auth.uid()
    )
  );

grant select on log_cierres_pujas to authenticated;

-- ─── 3. Función principal ─────────────────────────────────────────
create function procesar_cierre_pujas(p_federacion_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
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
begin

  -- ── 1. Verificar mercado activo y hora configurada ────────────
  select hora_cierre_pujas
    into v_hora
    from federaciones
   where id = p_federacion_id
     and ventas_habilitadas = true;

  if not found or v_hora is null then
    return jsonb_build_object('ok', true, 'skip', true,
                              'razon', 'mercado_cerrado_o_sin_hora');
  end if;

  -- ── 2. Calcular el timestamp exacto del cierre (Madrid → UTC) ─
  v_fecha := (now() at time zone 'Europe/Madrid')::date;
  v_ts    := (v_fecha::text || ' ' || v_hora::text)::timestamp
               at time zone 'Europe/Madrid';

  -- Si la hora de hoy aún no llegó, miramos si ayer hay un cierre pendiente
  if now() < v_ts then
    v_fecha := v_fecha - 1;
    v_ts    := (v_fecha::text || ' ' || v_hora::text)::timestamp
                 at time zone 'Europe/Madrid';
  end if;

  -- Si aún así está en el futuro → nada que hacer todavía
  if now() < v_ts then
    return jsonb_build_object('ok', true, 'skip', true,
                              'razon', 'sin_cierre_pendiente');
  end if;

  -- ── 3. Idempotencia: ¿ya procesamos ESTA hora en ESTA fecha? ─
  -- La clave incluye hora_cierre para permitir múltiples cierres el mismo
  -- día si el admin cambia la hora (cada combinación fecha+hora es única).
  if exists (
    select 1 from log_cierres_pujas
     where federacion_id = p_federacion_id
       and fecha_cierre  = v_fecha
       and hora_cierre   = v_hora
  ) then
    return jsonb_build_object('ok', true, 'skip', true,
                              'razon', 'ya_procesado',
                              'fecha', v_fecha, 'hora', v_hora);
  end if;

  -- ── 4. Lock de fila para serializar llamadas concurrentes ─────
  perform 1 from federaciones where id = p_federacion_id for update;

  -- Segunda comprobación post-lock
  if exists (
    select 1 from log_cierres_pujas
     where federacion_id = p_federacion_id
       and fecha_cierre  = v_fecha
       and hora_cierre   = v_hora
  ) then
    return jsonb_build_object('ok', true, 'skip', true,
                              'razon', 'ya_procesado_concurrente',
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

    -- Puja ganadora: mayor cantidad; empate → más antigua
    select
        p.id               as puja_id,
        p.participante_id,
        p.cantidad,
        pa.presupuesto     as presupuesto,
        pa.nombre          as nombre_equipo,
        pa.division_id     as division_id,
        ju.posicion        as jugador_posicion,
        ju.equipo          as jugador_equipo,
        ju.nombre          as jugador_nombre
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

    -- ── 5a. Jugador ya fichado en esta federación? ────────────
    if exists (
      select 1 from plantillas pl
        join participantes pa on pa.id = pl.participante_id
       where pl.jugador_id    = v_jug_id
         and pa.federacion_id = p_federacion_id
    ) or exists (
      select 1 from fichajes_pendientes fp
        join participantes pa on pa.id = fp.participante_id
       where fp.jugador_id    = v_jug_id
         and pa.federacion_id = p_federacion_id
    ) then
      update pujas set resuelta = true, ganadora = false
       where jugador_id = v_jug_id and resuelta = false
         and participante_id in (
           select id from participantes where federacion_id = p_federacion_id);
      continue;
    end if;

    -- ── 5b. Presupuesto insuficiente ──────────────────────────
    if v_ganadora.presupuesto < v_ganadora.cantidad then
      update pujas set resuelta = true, ganadora = false
       where jugador_id = v_jug_id and resuelta = false
         and participante_id in (
           select id from participantes where federacion_id = p_federacion_id);
      continue;
    end if;

    -- ── 5c. Portería única por división ───────────────────────
    if v_ganadora.jugador_posicion = 'POR' then
      if exists (
        select 1 from plantillas pl
          join participantes pa on pa.id = pl.participante_id
          join jugadores     ju on ju.id = pl.jugador_id
         where ju.posicion = 'POR' and ju.equipo = v_ganadora.jugador_equipo
           and pa.division_id = v_ganadora.division_id
           and pa.federacion_id = p_federacion_id
      ) or exists (
        select 1 from fichajes_pendientes fp
          join participantes pa on pa.id = fp.participante_id
          join jugadores     ju on ju.id = fp.jugador_id
         where ju.posicion = 'POR' and ju.equipo = v_ganadora.jugador_equipo
           and pa.division_id = v_ganadora.division_id
           and pa.federacion_id = p_federacion_id
      ) then
        update pujas set resuelta = true, ganadora = false
         where jugador_id = v_jug_id and resuelta = false
           and participante_id in (
             select id from participantes where federacion_id = p_federacion_id);
        continue;
      end if;
    end if;

    -- ── 5d. Plantilla activa o fichaje pendiente ──────────────
    select count(*) into v_cnt_plant
      from plantillas where participante_id = v_ganadora.participante_id;
    v_pendiente := (v_cnt_plant >= 14);

    -- ── 5e. Incorporar ────────────────────────────────────────
    if v_pendiente then
      insert into fichajes_pendientes (participante_id, jugador_id, precio_compra)
      values (v_ganadora.participante_id, v_jug_id, v_ganadora.cantidad)
      on conflict (participante_id, jugador_id) do nothing;
    else
      insert into plantillas (participante_id, jugador_id, precio_compra)
      values (v_ganadora.participante_id, v_jug_id, v_ganadora.cantidad)
      on conflict (participante_id, jugador_id) do nothing;
    end if;

    -- ── 5f. Descontar presupuesto ─────────────────────────────
    update participantes
       set presupuesto = presupuesto - v_ganadora.cantidad
     where id = v_ganadora.participante_id;

    -- ── 5g. Resolver pujas del jugador ────────────────────────
    update pujas set resuelta = true, ganadora = false
     where jugador_id = v_jug_id and resuelta = false
       and participante_id in (
         select id from participantes where federacion_id = p_federacion_id);

    update pujas set ganadora = true where id = v_ganadora.puja_id;

    -- ── 5h. Construir lista de pujas perdedoras ──────────────────
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

    -- ── 5i. Anuncio individual ────────────────────────────────────
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

  end loop;

  -- ── 6. Registrar el cierre (clave: federacion + fecha + hora) ─
  insert into log_cierres_pujas (federacion_id, fecha_cierre, hora_cierre, firmados)
  values (p_federacion_id, v_fecha, v_hora, v_firmados)
  on conflict (federacion_id, fecha_cierre, hora_cierre) do nothing;

  -- ── 7. Anuncio resumen ────────────────────────────────────────
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

  return jsonb_build_object(
    'ok',       true,
    'skip',     false,
    'fecha',    v_fecha::text,
    'hora',     v_hora::text,
    'firmados', v_firmados
  );

end;
$$;

grant execute on function procesar_cierre_pujas(uuid) to authenticated;
