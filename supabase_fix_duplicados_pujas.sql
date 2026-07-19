-- ═══════════════════════════════════════════════════════════════
-- FILFA — Protección de duplicados en resolución de pujas
--
-- Actualiza resolver_puja y procesar_cierre_pujas para respetar
-- la configuración duplicados_habilitado / duplicados_valor_min /
-- duplicados_max de cada federación.
--
-- REQUISITO: ejecutar supabase_duplicados.sql primero.
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════


-- ─── 1. resolver_puja (adjudicación manual por admin) ────────────

create or replace function resolver_puja(
  p_jugador_id     uuid,
  p_puja_id        int,
  p_federacion_id  uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_puja              record;
  v_presupuesto       numeric;
  v_planta_cnt        int;
  v_jug_posicion      text;
  v_jug_equipo        text;
  v_jug_valor_mercado numeric;
  v_div_ganador       int;
  v_dupl_hab          boolean;
  v_dupl_min          numeric;
  v_dupl_max          int;
  v_dupl_cnt          int;
begin
  -- ── 0. Verificar que el caller es admin de esta federación ─────
  if not exists (
    select 1 from federaciones
    where  id = p_federacion_id
      and  admin_user_id = auth.uid()
  ) then
    raise exception 'no_autorizado';
  end if;

  -- ── 1. Bloquear la puja ganadora (serializa adjudicaciones concurrentes) ─
  select p.*, pa.federacion_id as fed_id
    into v_puja
    from pujas p
    join participantes pa on pa.id = p.participante_id
   where p.id = p_puja_id
     and pa.federacion_id = p_federacion_id
     for update;

  if not found then
    raise exception 'puja_no_encontrada';
  end if;

  if v_puja.resuelta then
    raise exception 'puja_ya_resuelta';
  end if;

  -- ── 2. Verificar presupuesto ────────────────────────────────────
  select presupuesto into v_presupuesto
    from participantes
   where id = v_puja.participante_id;

  if v_presupuesto < v_puja.cantidad then
    raise exception 'presupuesto_insuficiente';
  end if;

  -- ── 3. Verificar límite de plantilla (máx 14) ──────────────────
  select count(*) into v_planta_cnt
    from plantillas
   where participante_id = v_puja.participante_id;

  if v_planta_cnt >= 14 then
    raise exception 'plantilla_completa';
  end if;

  -- ── 4. Datos del jugador ────────────────────────────────────────
  select posicion, equipo, coalesce(valor_mercado, 0)
    into v_jug_posicion, v_jug_equipo, v_jug_valor_mercado
    from jugadores
   where id = p_jugador_id;

  -- ── 4a. Verificar portería única por división (solo POR) ───────
  if v_jug_posicion = 'POR' then
    select division_id into v_div_ganador
      from participantes
     where id = v_puja.participante_id;

    if exists (
      select 1
        from plantillas pl
        join participantes pa on pa.id = pl.participante_id
        join jugadores     ju on ju.id = pl.jugador_id
       where ju.posicion       = 'POR'
         and ju.equipo         = v_jug_equipo
         and pa.division_id    = v_div_ganador
         and pa.federacion_id  = p_federacion_id
    ) then
      raise exception 'porteria_ocupada';
    end if;
  end if;

  -- ── 4b. Verificar límite de duplicados (jugadores no-POR) ──────
  if v_jug_posicion <> 'POR' then

    -- Un equipo nunca puede tener el mismo jugador dos veces
    if exists (
      select 1 from plantillas
       where participante_id = v_puja.participante_id and jugador_id = p_jugador_id
    ) or exists (
      select 1 from fichajes_pendientes
       where participante_id = v_puja.participante_id and jugador_id = p_jugador_id
    ) then
      raise exception 'jugador_ya_en_equipo';
    end if;

    -- Leer configuración de duplicados de la federación
    select coalesce(duplicados_habilitado, false),
           coalesce(duplicados_valor_min, 0),
           coalesce(duplicados_max, 2)
      into v_dupl_hab, v_dupl_min, v_dupl_max
      from federaciones
     where id = p_federacion_id;

    -- Copias actuales del jugador en la federación (plantillas + pendientes)
    select count(*) into v_dupl_cnt
      from (
        select 1 from plantillas pl
          join participantes pa on pa.id = pl.participante_id
         where pl.jugador_id = p_jugador_id and pa.federacion_id = p_federacion_id
        union all
        select 1 from fichajes_pendientes fp
          join participantes pa on pa.id = fp.participante_id
         where fp.jugador_id = p_jugador_id and pa.federacion_id = p_federacion_id
      ) sub;

    if not v_dupl_hab or (v_dupl_min > 0 and v_jug_valor_mercado < v_dupl_min) then
      -- Duplicados no aplican: solo puede existir 0 copias
      if v_dupl_cnt > 0 then
        raise exception 'jugador_ya_fichado';
      end if;
    else
      -- Duplicados activos: respetar el máximo de copias
      if v_dupl_cnt >= v_dupl_max then
        raise exception 'limite_duplicados_alcanzado';
      end if;
    end if;

  end if;

  -- ── 5. Fichar al jugador ────────────────────────────────────────
  insert into plantillas (participante_id, jugador_id, precio_compra)
  values (v_puja.participante_id, p_jugador_id, v_puja.cantidad);

  -- ── 6. Descontar presupuesto ────────────────────────────────────
  update participantes
     set presupuesto = presupuesto - v_puja.cantidad
   where id = v_puja.participante_id;

  -- ── 7. Resolver todas las pujas del jugador en esta federación ──
  update pujas p
     set resuelta = true,
         ganadora = false
    from participantes pa
   where p.jugador_id      = p_jugador_id
     and p.participante_id = pa.id
     and pa.federacion_id  = p_federacion_id;

  -- ── 8. Marcar la puja ganadora ──────────────────────────────────
  update pujas
     set ganadora = true
   where id = p_puja_id;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function resolver_puja(uuid, int, uuid) to authenticated;


-- ─── 2. procesar_cierre_pujas (cierre automático) ────────────────

create or replace function procesar_cierre_pujas(p_federacion_id uuid)
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
  v_dupl_hab    boolean;
  v_dupl_min    numeric;
  v_dupl_max    int;
  v_dupl_cnt    int;
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

  if now() < v_ts then
    v_fecha := v_fecha - 1;
    v_ts    := (v_fecha::text || ' ' || v_hora::text)::timestamp
                 at time zone 'Europe/Madrid';
  end if;

  if now() < v_ts then
    return jsonb_build_object('ok', true, 'skip', true,
                              'razon', 'sin_cierre_pendiente');
  end if;

  -- ── 3. Idempotencia ──────────────────────────────────────────
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

  -- Leer configuración de duplicados una sola vez por ejecución
  select coalesce(duplicados_habilitado, false),
         coalesce(duplicados_valor_min, 0),
         coalesce(duplicados_max, 2)
    into v_dupl_hab, v_dupl_min, v_dupl_max
    from federaciones
   where id = p_federacion_id;

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
        p.id                               as puja_id,
        p.participante_id,
        p.cantidad,
        pa.presupuesto                     as presupuesto,
        pa.nombre                          as nombre_equipo,
        pa.division_id                     as division_id,
        ju.posicion                        as jugador_posicion,
        ju.equipo                          as jugador_equipo,
        ju.nombre                          as jugador_nombre,
        coalesce(ju.valor_mercado, 0)      as jugador_valor_mercado
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

    -- ── 5a. Verificar disponibilidad del jugador ──────────────────
    if v_ganadora.jugador_posicion = 'POR' then
      -- POR: nunca duplicable → si existe en cualquier equipo, descartar
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

    else
      -- No-POR: respetar configuración de duplicados

      -- El equipo ganador no puede tener el mismo jugador dos veces
      if exists (
        select 1 from plantillas
         where participante_id = v_ganadora.participante_id and jugador_id = v_jug_id
      ) or exists (
        select 1 from fichajes_pendientes
         where participante_id = v_ganadora.participante_id and jugador_id = v_jug_id
      ) then
        update pujas set resuelta = true, ganadora = false
         where jugador_id = v_jug_id and resuelta = false
           and participante_id in (
             select id from participantes where federacion_id = p_federacion_id);
        continue;
      end if;

      -- Copias actuales del jugador en la federación
      select count(*) into v_dupl_cnt
        from (
          select 1 from plantillas pl
            join participantes pa on pa.id = pl.participante_id
           where pl.jugador_id = v_jug_id and pa.federacion_id = p_federacion_id
          union all
          select 1 from fichajes_pendientes fp
            join participantes pa on pa.id = fp.participante_id
           where fp.jugador_id = v_jug_id and pa.federacion_id = p_federacion_id
        ) sub;

      if not v_dupl_hab
         or (v_dupl_min > 0 and v_ganadora.jugador_valor_mercado < v_dupl_min)
      then
        -- Duplicados no aplican: máximo 1 copia en la federación
        if v_dupl_cnt > 0 then
          update pujas set resuelta = true, ganadora = false
           where jugador_id = v_jug_id and resuelta = false
             and participante_id in (
               select id from participantes where federacion_id = p_federacion_id);
          continue;
        end if;
      else
        -- Duplicados activos: respetar el máximo de copias
        if v_dupl_cnt >= v_dupl_max then
          update pujas set resuelta = true, ganadora = false
           where jugador_id = v_jug_id and resuelta = false
             and participante_id in (
               select id from participantes where federacion_id = p_federacion_id);
          continue;
        end if;
      end if;

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

    -- ── 5d. Plantilla llena → fichaje pendiente ───────────────
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

    -- ── 5h. Lista de pujas perdedoras ─────────────────────────
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

    -- ── 5i. Anuncio ───────────────────────────────────────────
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

  -- ── 6. Registrar el cierre ────────────────────────────────────
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
