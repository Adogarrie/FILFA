-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fichajes pendientes de incorporación
--
-- Un equipo puede ganar pujas aunque tenga 14 jugadores.
-- El jugador va a "fichajes_pendientes" hasta que el equipo
-- libere una ficha o venda un jugador.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Nueva tabla ─────────────────────────────────────────────
create table if not exists fichajes_pendientes (
  id              serial primary key,
  participante_id uuid not null references participantes(id) on delete cascade,
  jugador_id      uuid not null references jugadores(id)     on delete cascade,
  precio_compra   numeric(12,2) not null,
  created_at      timestamptz default now(),
  unique (participante_id, jugador_id)
);

alter table fichajes_pendientes enable row level security;

grant select, insert, delete on fichajes_pendientes to authenticated;
grant usage, select on sequence fichajes_pendientes_id_seq to authenticated;

-- ─── 2. RLS ─────────────────────────────────────────────────────
-- El equipo ve sus propios fichajes pendientes.
-- El admin de la federación ve todos los de su federación.
drop policy if exists "Ver fichajes pendientes" on fichajes_pendientes;
create policy "Ver fichajes pendientes"
  on fichajes_pendientes for select
  using (
    participante_id in (select id from participantes where user_id = auth.uid())
    or exists (
      select 1 from participantes pa
      join  federaciones f on f.id = pa.federacion_id
      where pa.id = fichajes_pendientes.participante_id
        and f.admin_user_id = auth.uid()
    )
  );

-- ─── 3. resolver_puja actualizado ───────────────────────────────
-- Cuando el equipo tiene 14 jugadores, inserta en fichajes_pendientes
-- en lugar de plantillas.  Devuelve { ok: true, pendiente: bool }.
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
begin
  -- ── 0. Verificar que el caller es admin de esta federación ─────
  if not exists (
    select 1 from federaciones
    where  id = p_federacion_id
      and  admin_user_id = auth.uid()
  ) then
    raise exception 'no_autorizado';
  end if;

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

  if v_planta_cnt < 14 then
    -- Plaza libre → incorporación inmediata
    insert into plantillas (participante_id, jugador_id, precio_compra)
    values (v_puja.participante_id, p_jugador_id, v_puja.cantidad);
    v_pendiente := false;
  else
    -- Sin plaza → va a fichajes_pendientes
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

-- ─── 4. activar_fichaje_pendiente ───────────────────────────────
-- Incorpora un fichaje pendiente a la plantilla activa.
-- Si el equipo está lleno, p_liberar_jugador_id es obligatorio
-- (ese jugador se elimina de la plantilla sin compensación económica).
drop function if exists activar_fichaje_pendiente(int, uuid, uuid);
create or replace function activar_fichaje_pendiente(
  p_pendiente_id       int,
  p_liberar_jugador_id uuid default null,
  p_federacion_id      uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fp   record;
  v_cnt  int;
begin
  -- Cargar el fichaje pendiente bloqueando la fila
  select fp.*, pa.user_id, pa.federacion_id as fed_id
    into v_fp
    from fichajes_pendientes fp
    join participantes pa on pa.id = fp.participante_id
   where fp.id = p_pendiente_id
     for update;

  if not found then raise exception 'fichaje_no_encontrado'; end if;

  -- Auth: dueño del equipo o admin de la federación
  if v_fp.user_id is distinct from auth.uid()
     and not exists (
       select 1 from federaciones
       where  id = v_fp.fed_id
         and  admin_user_id = auth.uid()
     )
  then
    raise exception 'no_autorizado';
  end if;

  -- Contar plantilla actual
  select count(*) into v_cnt
    from plantillas where participante_id = v_fp.participante_id;

  if v_cnt >= 14 then
    -- Equipo lleno: debe indicar quién sale
    if p_liberar_jugador_id is null then
      raise exception 'plantilla_llena_indica_baja';
    end if;
    delete from plantillas
     where participante_id = v_fp.participante_id
       and jugador_id      = p_liberar_jugador_id;
    if not found then raise exception 'jugador_a_liberar_no_encontrado'; end if;
  end if;

  -- Incorporar a la plantilla activa
  insert into plantillas (participante_id, jugador_id, precio_compra)
  values (v_fp.participante_id, v_fp.jugador_id, v_fp.precio_compra);

  -- Limpiar de pendientes
  delete from fichajes_pendientes where id = p_pendiente_id;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function activar_fichaje_pendiente(int, uuid, uuid) to authenticated;

-- ─── 5. anular_fichaje_pendiente (solo admin) ───────────────────
-- El admin cancela un fichaje pendiente: el jugador vuelve al
-- mercado libre y el equipo recupera el presupuesto.
drop function if exists anular_fichaje_pendiente(int, uuid);
create or replace function anular_fichaje_pendiente(
  p_pendiente_id   int,
  p_federacion_id  uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fp record;
begin
  if not exists (
    select 1 from federaciones
    where  id = p_federacion_id
      and  admin_user_id = auth.uid()
  ) then
    raise exception 'no_autorizado';
  end if;

  select fp.*
    into v_fp
    from fichajes_pendientes fp
    join participantes pa on pa.id = fp.participante_id
   where fp.id            = p_pendiente_id
     and pa.federacion_id = p_federacion_id
     for update;

  if not found then raise exception 'fichaje_no_encontrado'; end if;

  -- Devolver presupuesto
  update participantes
     set presupuesto = presupuesto + v_fp.precio_compra
   where id = v_fp.participante_id;

  delete from fichajes_pendientes where id = p_pendiente_id;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function anular_fichaje_pendiente(int, uuid) to authenticated;
