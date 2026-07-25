-- ═══════════════════════════════════════════════════════════════
-- FILFA — Presupuesto negativo + max_jugadores dinámico
--
-- Cambios en resolver_puja:
--   · Elimina el check presupuesto_insuficiente (deuda permitida)
--   · Usa federacion.max_jugadores en vez del 14 hardcodeado
--   · plantilla_completa → fichajes_pendientes (no excepción)
--   · Portero: bloqueo duro si mismo club ya en la división (otro equipo)
--   · Portero: fichajes_pendientes si el equipo ya tiene cualquier portero
--
-- Cambios en aceptar_oferta:
--   · Elimina el check presupuesto_insuficiente (deuda permitida)
--
-- El equipo en deuda verá su presupuesto en rojo en la app y
-- recibirá 0 puntos en cualquier jornada que empiece en negativo.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════


-- ── 1. resolver_puja ──────────────────────────────────────────

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

  -- ── 2. Verificar límite de plantilla usando max_jugadores de la federación ─
  select coalesce(max_jugadores, 14) into v_max_jug
    from federaciones
   where id = p_federacion_id;

  select count(*) into v_planta_cnt
    from plantillas
   where participante_id = v_puja.participante_id;

  if v_planta_cnt >= v_max_jug then
    v_pendiente := true;
  end if;

  -- ── 3. Verificar portería (solo para POR) ──────────────────────
  select posicion, equipo
    into v_jug_posicion, v_jug_equipo
    from jugadores
   where id = p_jugador_id;

  if v_jug_posicion = 'POR' then
    select division_id into v_div_ganador
      from participantes
     where id = v_puja.participante_id;

    -- Bloqueo duro: mismo club ya en la misma división (en otro equipo)
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

    -- Pendiente: el equipo ganador ya tiene cualquier portero
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

  -- ── 4a. Fichaje pendiente de plaza ─────────────────────────────
  if v_pendiente then
    insert into fichajes_pendientes (participante_id, jugador_id, precio_compra)
    values (v_puja.participante_id, p_jugador_id, v_puja.cantidad)
    on conflict (participante_id, jugador_id) do update
      set precio_compra = excluded.precio_compra;

    update participantes
       set presupuesto = presupuesto - v_puja.cantidad
     where id = v_puja.participante_id;

    update pujas p
       set resuelta = true,
           ganadora = false
      from participantes pa
     where p.jugador_id      = p_jugador_id
       and p.participante_id = pa.id
       and pa.federacion_id  = p_federacion_id;

    update pujas
       set ganadora = true
     where id = p_puja_id;

    return jsonb_build_object('ok', true, 'pendiente', true);
  end if;

  -- ── 4b. Fichar al jugador directamente ─────────────────────────
  insert into plantillas (participante_id, jugador_id, precio_compra)
  values (v_puja.participante_id, p_jugador_id, v_puja.cantidad);

  -- ── 5. Descontar presupuesto (puede quedar negativo) ───────────
  update participantes
     set presupuesto = presupuesto - v_puja.cantidad
   where id = v_puja.participante_id;

  -- ── 6. Resolver todas las pujas del jugador en esta federación ──
  update pujas p
     set resuelta = true,
         ganadora = false
    from participantes pa
   where p.jugador_id      = p_jugador_id
     and p.participante_id = pa.id
     and pa.federacion_id  = p_federacion_id;

  -- ── 7. Marcar la puja ganadora ──────────────────────────────────
  update pujas
     set ganadora = true
   where id = p_puja_id;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function resolver_puja(uuid, int, uuid) to authenticated;


-- ── 2. aceptar_oferta ─────────────────────────────────────────

drop function if exists aceptar_oferta(int);

create function aceptar_oferta(p_oferta_id int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_oferta    record;
  v_jug       record;
  v_ofertante record;
  v_prop      record;
  v_nom_jug   text;
begin
  -- 1. Leer y bloquear la oferta
  select * into v_oferta from ofertas_jugadores where id = p_oferta_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'oferta_no_encontrada'); end if;
  if v_oferta.estado <> 'pendiente' then return jsonb_build_object('ok', false, 'error', 'oferta_no_pendiente'); end if;

  -- 2. Solo el propietario o admin de la federación pueden aceptar
  if not (
    v_oferta.propietario_id in (select id from participantes where user_id = auth.uid())
    or exists (select 1 from federaciones where id = v_oferta.federacion_id and admin_user_id = auth.uid())
  ) then return jsonb_build_object('ok', false, 'error', 'sin_permiso'); end if;

  -- 3. Cargar datos relacionados
  select * into v_jug       from jugadores     where id = v_oferta.jugador_id;
  select * into v_ofertante from participantes where id = v_oferta.ofertante_id;
  select * into v_prop      from participantes where id = v_oferta.propietario_id;

  -- 4. Quitar de la plantilla del vendedor
  delete from plantillas
   where participante_id = v_oferta.propietario_id
     and jugador_id      = v_oferta.jugador_id;

  -- 5. Siempre va a fichajes_pendientes — el admin decidirá cuándo activar o descartar.
  insert into fichajes_pendientes (participante_id, jugador_id, precio_compra, traspaso_de_id)
  values (v_oferta.ofertante_id, v_oferta.jugador_id, v_oferta.cantidad, v_oferta.propietario_id)
  on conflict (participante_id, jugador_id) do update
    set precio_compra  = excluded.precio_compra,
        traspaso_de_id = excluded.traspaso_de_id;

  -- 6. Transferencia de dinero (ofertante puede quedar en negativo)
  update participantes set presupuesto = presupuesto - v_oferta.cantidad where id = v_oferta.ofertante_id;
  update participantes set presupuesto = presupuesto + v_oferta.cantidad where id = v_oferta.propietario_id;

  -- 7. Cerrar esta oferta y rechazar las demás pendientes del mismo jugador
  update ofertas_jugadores set estado = 'aceptada' where id = p_oferta_id;
  update ofertas_jugadores
     set estado = 'rechazada'
   where jugador_id    = v_oferta.jugador_id
     and federacion_id = v_oferta.federacion_id
     and estado        = 'pendiente'
     and id            <> p_oferta_id;

  -- 8. Anuncio en el tablón
  v_nom_jug := case when v_jug.posicion = 'POR' then 'Portería ' || v_jug.equipo else v_jug.nombre end;
  insert into anuncios (federacion_id, tipo, texto)
  values (
    v_oferta.federacion_id,
    'fichaje',
    v_ofertante.nombre || ' acuerda el traspaso de ' || v_nom_jug
    || ' de ' || v_prop.nombre
    || ' por ' || to_char(v_oferta.cantidad, 'FM999G999G999') || ' €'
    || ' — pendiente de activar plaza'
  );

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function aceptar_oferta(int) to authenticated;
