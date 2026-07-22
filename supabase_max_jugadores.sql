-- ═══════════════════════════════════════════════════════════════
-- FILFA — Máximo de jugadores configurable por federación
--
-- Sustituye el límite fijo de 14 jugadores por un valor editable
-- por el admin en cada federación. El valor por defecto es 14,
-- por lo que las federaciones existentes no cambian su comportamiento.
--
-- Los equipos que ya superen el nuevo límite (si se reduce) mantienen
-- todos sus jugadores; simplemente no podrán fichar hasta que liberen
-- las fichas necesarias para quedar dentro del límite.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Nueva columna en federaciones ─────────────────────────────
alter table federaciones
  add column if not exists max_jugadores integer not null default 14;

-- ── 2. Helper: leer el límite de una federación ───────────────────
create or replace function get_max_jugadores(p_federacion_id uuid)
returns int
language sql
security definer
set search_path = public
as $$
  select coalesce(max_jugadores, 14) from federaciones where id = p_federacion_id;
$$;

grant execute on function get_max_jugadores(uuid) to authenticated;

-- ── 3. resolver_puja (actualizado) ───────────────────────────────
-- Cuando el equipo alcanza max_jugadores inserta en fichajes_pendientes.
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
  v_puja         record;
  v_presupuesto  numeric;
  v_planta_cnt   int;
  v_jug_posicion text;
  v_jug_equipo   text;
  v_div_ganador  int;
  v_pendiente    boolean := false;
  v_max_jug      int;
begin
  -- ── 0. Verificar que el caller es admin de esta federación ─────
  if not exists (
    select 1 from federaciones
    where  id = p_federacion_id
      and  admin_user_id = auth.uid()
  ) then
    raise exception 'no_autorizado';
  end if;

  v_max_jug := get_max_jugadores(p_federacion_id);

  -- ── 1. Bloquear la puja ganadora ────────────────────────────────
  select p.*, pa.federacion_id as fed_id
    into v_puja
    from pujas p
    join participantes pa on pa.id = p.participante_id
   where p.id = p_puja_id
     and pa.federacion_id = p_federacion_id
     for update;

  if not found then raise exception 'puja_no_encontrada'; end if;
  if v_puja.resuelta then raise exception 'puja_ya_resuelta'; end if;

  -- ── 2. Verificar presupuesto ────────────────────────────────────
  select presupuesto into v_presupuesto
    from participantes where id = v_puja.participante_id;

  if v_presupuesto < v_puja.cantidad then
    raise exception 'presupuesto_insuficiente';
  end if;

  -- ── 3. Portería única por división ─────────────────────────────
  select posicion, equipo
    into v_jug_posicion, v_jug_equipo
    from jugadores where id = p_jugador_id;

  if v_jug_posicion = 'POR' then
    select division_id into v_div_ganador
      from participantes where id = v_puja.participante_id;

    if exists (
      select 1
        from plantillas    pl
        join participantes pa on pa.id = pl.participante_id
        join jugadores     ju on ju.id = pl.jugador_id
       where ju.posicion      = 'POR'
         and ju.equipo        = v_jug_equipo
         and pa.division_id   = v_div_ganador
         and pa.federacion_id = p_federacion_id
    ) then
      raise exception 'porteria_ocupada';
    end if;
  end if;

  -- ── 4. Plantilla activa o pendientes ────────────────────────────
  select count(*) into v_planta_cnt
    from plantillas where participante_id = v_puja.participante_id;

  if v_planta_cnt < v_max_jug then
    insert into plantillas (participante_id, jugador_id, precio_compra)
    values (v_puja.participante_id, p_jugador_id, v_puja.cantidad);
    v_pendiente := false;
  else
    if exists (
      select 1 from fichajes_pendientes
      where participante_id = v_puja.participante_id
        and jugador_id      = p_jugador_id
    ) then
      raise exception 'ya_en_pendientes';
    end if;
    insert into fichajes_pendientes (participante_id, jugador_id, precio_compra)
    values (v_puja.participante_id, p_jugador_id, v_puja.cantidad);
    v_pendiente := true;
  end if;

  -- ── 5. Descontar presupuesto (siempre) ──────────────────────────
  update participantes
     set presupuesto = presupuesto - v_puja.cantidad
   where id = v_puja.participante_id;

  -- ── 6. Resolver todas las pujas del jugador en esta federación ──
  update pujas p
     set resuelta = true, ganadora = false
    from participantes pa
   where p.jugador_id      = p_jugador_id
     and p.participante_id = pa.id
     and pa.federacion_id  = p_federacion_id;

  -- ── 7. Marcar la puja ganadora ──────────────────────────────────
  update pujas set ganadora = true where id = p_puja_id;

  return jsonb_build_object('ok', true, 'pendiente', v_pendiente);
end;
$$;

grant execute on function resolver_puja(uuid, int, uuid) to authenticated;

-- ── 4. activar_fichaje_pendiente (actualizado) ────────────────────
drop function if exists activar_fichaje_pendiente(int, uuid, uuid);

create function activar_fichaje_pendiente(
  p_pendiente_id       int,
  p_liberar_jugador_id uuid,
  p_federacion_id      uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pend      record;
  v_cnt       int;
  v_valor_lib numeric := 0;
  v_max_jug   int;
begin
  -- 1. Cargar fichaje pendiente
  select * into v_pend from fichajes_pendientes where id = p_pendiente_id;
  if not found then raise exception 'fichaje_no_encontrado'; end if;

  -- 2. Verificar permiso (equipo propietario o admin de la federación)
  if not (
    v_pend.participante_id in (select id from participantes where user_id = auth.uid())
    or exists (select 1 from federaciones where id = p_federacion_id and admin_user_id = auth.uid())
  ) then raise exception 'no_autorizado'; end if;

  v_max_jug := get_max_jugadores(p_federacion_id);

  -- 3. Comprobar si la plantilla tiene hueco
  select count(*) into v_cnt from plantillas where participante_id = v_pend.participante_id;
  if v_cnt >= v_max_jug then
    if p_liberar_jugador_id is null then
      raise exception 'plantilla_llena_indica_baja';
    end if;
    if not exists (
      select 1 from plantillas
       where participante_id = v_pend.participante_id
         and jugador_id = p_liberar_jugador_id
    ) then
      raise exception 'jugador_a_liberar_no_encontrado';
    end if;
    select coalesce(j.valor_mercado, 0) into v_valor_lib
      from jugadores j where j.id = p_liberar_jugador_id;
    delete from plantillas
     where participante_id = v_pend.participante_id
       and jugador_id      = p_liberar_jugador_id;
    update participantes
       set presupuesto = presupuesto + v_valor_lib
     where id = v_pend.participante_id;
  end if;

  -- 4. Mover el fichaje pendiente a la plantilla activa
  insert into plantillas (participante_id, jugador_id, precio_compra)
  values (v_pend.participante_id, v_pend.jugador_id, v_pend.precio_compra)
  on conflict (participante_id, jugador_id) do nothing;

  -- 5. Eliminar de pendientes
  delete from fichajes_pendientes where id = p_pendiente_id;
end;
$$;

grant execute on function activar_fichaje_pendiente(int, uuid, uuid) to authenticated;

-- ── 5. procesar_cierre_pujas (actualizado) ────────────────────────
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
  v_max_jug     int;
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

  v_max_jug := get_max_jugadores(p_federacion_id);

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

  -- ── 3. Idempotencia ───────────────────────────────────────────
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

    -- ── 5d. Plantilla llena? ──────────────────────────────────
    select count(*) into v_cnt_plant
      from plantillas where participante_id = v_ganadora.participante_id;
    v_pendiente := (v_cnt_plant >= v_max_jug);

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

  -- ── 6. Registrar el cierre ─────────────────────────────────────
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

-- ── 6. anular_traspaso_pendiente (actualizado) ────────────────────
drop function if exists anular_traspaso_pendiente(int, uuid);

create function anular_traspaso_pendiente(
  p_pendiente_id  int,
  p_federacion_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pend       record;
  v_comprador  record;
  v_vendedor   record;
  v_jug        record;
  v_refund     numeric;
  v_cnt        int;
  v_devuelto   boolean := false;
  v_nom_jug    text;
  v_max_jug    int;
begin
  -- 1. Cargar fichaje pendiente
  select * into v_pend from fichajes_pendientes where id = p_pendiente_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'fichaje_no_encontrado');
  end if;
  if v_pend.traspaso_de_id is null then
    return jsonb_build_object('ok', false, 'error', 'no_es_traspaso');
  end if;

  -- 2. Verificar permiso (participante comprador o admin de la federación)
  if not (
    v_pend.participante_id in (select id from participantes where user_id = auth.uid())
    or exists (select 1 from federaciones where id = p_federacion_id and admin_user_id = auth.uid())
  ) then
    return jsonb_build_object('ok', false, 'error', 'no_autorizado');
  end if;

  v_max_jug := get_max_jugadores(p_federacion_id);

  -- 3. Cargar datos
  select * into v_comprador from participantes where id = v_pend.participante_id;
  select * into v_vendedor  from participantes where id = v_pend.traspaso_de_id;
  select * into v_jug       from jugadores     where id = v_pend.jugador_id;

  v_refund := round(v_pend.precio_compra * 0.8, 2);

  -- 4. ¿El vendedor tiene hueco en la plantilla?
  select count(*) into v_cnt from plantillas where participante_id = v_pend.traspaso_de_id;

  if v_cnt < v_max_jug then
    insert into plantillas (participante_id, jugador_id, precio_compra)
    values (v_pend.traspaso_de_id, v_pend.jugador_id, v_pend.precio_compra)
    on conflict (participante_id, jugador_id) do nothing;
    v_devuelto := true;
  end if;

  -- 5. Transferencia: vendedor devuelve el 80% al comprador
  update participantes set presupuesto = presupuesto - v_refund where id = v_pend.traspaso_de_id;
  update participantes set presupuesto = presupuesto + v_refund where id = v_pend.participante_id;

  -- 6. Eliminar el fichaje pendiente
  delete from fichajes_pendientes where id = p_pendiente_id;

  -- 7. Anuncio en el tablón
  v_nom_jug := case when v_jug.posicion = 'POR' then 'Portería ' || v_jug.equipo else v_jug.nombre end;
  insert into anuncios (federacion_id, tipo, texto)
  values (
    p_federacion_id,
    'traspaso',
    v_comprador.nombre || ' descarta el traspaso de ' || v_nom_jug
    || case when v_devuelto
         then ' · Vuelve a ' || v_vendedor.nombre
         else ' · Queda libre (plantilla de ' || v_vendedor.nombre || ' llena)'
       end
    || ' · Reembolso: ' || to_char(v_refund, 'FM999G999G999') || ' €'
  );

  return jsonb_build_object(
    'ok',       true,
    'devuelto', v_devuelto,
    'refund',   v_refund
  );
end;
$$;

grant execute on function anular_traspaso_pendiente(int, uuid) to authenticated;
