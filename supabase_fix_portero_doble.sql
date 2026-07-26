-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fix: portero doble
--
-- Problema A: resolver_puja (versión antigua en Supabase) solo
--   bloqueaba si el mismo club ya estaba en la división (otro equipo).
--   No comprobaba si el MISMO equipo ya tenía cualquier portero.
--   Resultado: segunda portería entraba directo a plantillas.
--
-- Problema B: activar_fichaje_pendiente tampoco tenía guarda de
--   portero a nivel de equipo. Aunque resolver_puja enrutara bien
--   a fichajes_pendientes, al activar entraba igualmente.
--
-- Este archivo reemplaza ambas funciones de una sola vez.
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════


-- ── 1. resolver_puja ─────────────────────────────────────────────

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
  v_planta_cnt   int;
  v_max_jug      int;
  v_jug_posicion text;
  v_jug_equipo   text;
  v_div_ganador  int;
  v_pendiente    boolean := false;
begin
  -- 0. Verificar que el caller es admin de esta federación
  if not exists (
    select 1 from federaciones
    where  id = p_federacion_id
      and  admin_user_id = auth.uid()
  ) then
    raise exception 'no_autorizado';
  end if;

  -- 1. Bloquear la puja ganadora (serializa adjudicaciones concurrentes)
  select p.*, pa.federacion_id as fed_id
    into v_puja
    from pujas p
    join participantes pa on pa.id = p.participante_id
   where p.id = p_puja_id
     and pa.federacion_id = p_federacion_id
     for update;

  if not found then raise exception 'puja_no_encontrada'; end if;
  if v_puja.resuelta then raise exception 'puja_ya_resuelta'; end if;

  -- 2. Verificar límite de plantilla usando max_jugadores de la federación
  select coalesce(max_jugadores, 14) into v_max_jug
    from federaciones where id = p_federacion_id;

  select count(*) into v_planta_cnt
    from plantillas where participante_id = v_puja.participante_id;

  if v_planta_cnt >= v_max_jug then
    v_pendiente := true;
  end if;

  -- 3. Verificar portería (solo para POR)
  select posicion, equipo
    into v_jug_posicion, v_jug_equipo
    from jugadores where id = p_jugador_id;

  if v_jug_posicion = 'POR' then
    select division_id into v_div_ganador
      from participantes where id = v_puja.participante_id;

    -- Bloqueo duro: mismo club ya en la misma división (otro equipo)
    if exists (
      select 1
        from plantillas pl
        join participantes pa on pa.id = pl.participante_id
        join jugadores     ju on ju.id = pl.jugador_id
       where ju.posicion      = 'POR'
         and ju.equipo        = v_jug_equipo
         and pa.division_id   = v_div_ganador
         and pa.federacion_id = p_federacion_id
    ) then
      raise exception 'porteria_ocupada';
    end if;

    -- Bloqueo suave: el equipo ya tiene cualquier portero → pendiente
    if exists (
      select 1
        from plantillas pl
        join jugadores   ju on ju.id = pl.jugador_id
       where pl.participante_id = v_puja.participante_id
         and ju.posicion        = 'POR'
    ) then
      v_pendiente := true;
    end if;
  end if;

  -- 4a. Fichaje pendiente de plaza
  if v_pendiente then
    insert into fichajes_pendientes (participante_id, jugador_id, precio_compra)
    values (v_puja.participante_id, p_jugador_id, v_puja.cantidad)
    on conflict (participante_id, jugador_id) do update
      set precio_compra = excluded.precio_compra;

    update participantes
       set presupuesto = presupuesto - v_puja.cantidad
     where id = v_puja.participante_id;

    update pujas p
       set resuelta = true, ganadora = false
      from participantes pa
     where p.jugador_id      = p_jugador_id
       and p.participante_id = pa.id
       and pa.federacion_id  = p_federacion_id;

    update pujas set ganadora = true where id = p_puja_id;

    return jsonb_build_object('ok', true, 'pendiente', true);
  end if;

  -- 4b. Fichar al jugador directamente
  insert into plantillas (participante_id, jugador_id, precio_compra)
  values (v_puja.participante_id, p_jugador_id, v_puja.cantidad);

  update participantes
     set presupuesto = presupuesto - v_puja.cantidad
   where id = v_puja.participante_id;

  update pujas p
     set resuelta = true, ganadora = false
    from participantes pa
   where p.jugador_id      = p_jugador_id
     and p.participante_id = pa.id
     and pa.federacion_id  = p_federacion_id;

  update pujas set ganadora = true where id = p_puja_id;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function resolver_puja(uuid, int, uuid) to authenticated;


-- ── 2. activar_fichaje_pendiente ─────────────────────────────────

drop function if exists activar_fichaje_pendiente(int, uuid, uuid);

create or replace function activar_fichaje_pendiente(
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
  v_pend        record;
  v_cnt         int;
  v_max_jug     int;
  v_jug_pos     text;
  v_valor_lib   numeric := 0;
  v_lesionado   boolean := false;
  v_pct         int;
  v_refund      numeric := 0;
begin
  -- 1. Cargar fichaje pendiente
  select * into v_pend from fichajes_pendientes where id = p_pendiente_id;
  if not found then raise exception 'fichaje_no_encontrado'; end if;

  -- 2. Verificar permiso (equipo propietario o admin de la federación)
  if not (
    v_pend.participante_id in (select id from participantes where user_id = auth.uid())
    or exists (select 1 from federaciones where id = p_federacion_id and admin_user_id = auth.uid())
  ) then raise exception 'no_autorizado'; end if;

  -- 3. Verificar portero único por equipo
  select posicion into v_jug_pos from jugadores where id = v_pend.jugador_id;

  if v_jug_pos = 'POR' then
    if exists (
      select 1
        from plantillas pl
        join jugadores   ju on ju.id = pl.jugador_id
       where pl.participante_id = v_pend.participante_id
         and ju.posicion        = 'POR'
         and pl.jugador_id is distinct from p_liberar_jugador_id
    ) then
      raise exception 'portero_ya_en_plantilla';
    end if;
  end if;

  -- 4. Límite configurable por federación
  v_max_jug := get_max_jugadores(p_federacion_id);

  select count(*) into v_cnt from plantillas where participante_id = v_pend.participante_id;

  if v_cnt >= v_max_jug then
    if p_liberar_jugador_id is null then
      raise exception 'plantilla_llena_indica_baja';
    end if;
    if not exists (
      select 1 from plantillas
       where participante_id = v_pend.participante_id
         and jugador_id      = p_liberar_jugador_id
    ) then
      raise exception 'jugador_a_liberar_no_encontrado';
    end if;

    select coalesce(j.valor_mercado, 0), coalesce(j.lesionado, false)
      into v_valor_lib, v_lesionado
      from jugadores j where j.id = p_liberar_jugador_id;

    select coalesce(pct_venta_mercado, 100) into v_pct
      from federaciones where id = p_federacion_id;

    v_refund := case
      when v_lesionado then v_valor_lib
      else round(v_valor_lib * v_pct / 100.0, 2)
    end;

    delete from plantillas
     where participante_id = v_pend.participante_id
       and jugador_id      = p_liberar_jugador_id;

    update participantes
       set presupuesto = presupuesto + v_refund
     where id = v_pend.participante_id;

  elsif p_liberar_jugador_id is not null then
    -- Portero: plantilla no está llena pero hay que liberar el portero actual
    if not exists (
      select 1 from plantillas
       where participante_id = v_pend.participante_id
         and jugador_id      = p_liberar_jugador_id
    ) then
      raise exception 'jugador_a_liberar_no_encontrado';
    end if;

    select coalesce(j.valor_mercado, 0), coalesce(j.lesionado, false)
      into v_valor_lib, v_lesionado
      from jugadores j where j.id = p_liberar_jugador_id;

    select coalesce(pct_venta_mercado, 100) into v_pct
      from federaciones where id = p_federacion_id;

    v_refund := case
      when v_lesionado then v_valor_lib
      else round(v_valor_lib * v_pct / 100.0, 2)
    end;

    delete from plantillas
     where participante_id = v_pend.participante_id
       and jugador_id      = p_liberar_jugador_id;

    update participantes
       set presupuesto = presupuesto + v_refund
     where id = v_pend.participante_id;
  end if;

  -- 5. Mover fichaje pendiente a plantilla activa
  insert into plantillas (participante_id, jugador_id, precio_compra)
  values (v_pend.participante_id, v_pend.jugador_id, v_pend.precio_compra)
  on conflict (participante_id, jugador_id) do nothing;

  -- 6. Eliminar de pendientes
  delete from fichajes_pendientes where id = p_pendiente_id;
end;
$$;

grant execute on function activar_fichaje_pendiente(int, uuid, uuid) to authenticated;
