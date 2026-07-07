-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fix: moderadores pueden usar las pestañas que les corresponden
--
-- Problema: las políticas RLS y las RPCs solo comprueban si el caller
-- es admin de la federación (federaciones.admin_user_id = auth.uid()).
-- Los moderadores tienen un participante_id en la tabla moderadores
-- pero no son admin, así que todas sus escrituras fallaban en silencio.
--
-- Solución:
--   1. Función auxiliar es_admin_o_mod(federacion_id) — reutilizable.
--   2. Actualizar las 3 políticas de escritura afectadas.
--   3. Actualizar las 3 RPCs afectadas.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Función auxiliar ────────────────────────────────────────
-- Devuelve true si el usuario actual es admin o moderador de la federación.
-- security definer para que pueda leer moderadores/participantes sin
-- que el caller necesite grant directo.
create or replace function es_admin_o_mod(p_federacion_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    exists (
      select 1 from federaciones
      where id = p_federacion_id and admin_user_id = auth.uid()
    )
    or exists (
      select 1 from moderadores m
      join  participantes pa on pa.id = m.participante_id
      where m.federacion_id = p_federacion_id
        and pa.user_id      = auth.uid()
    )
$$;

grant execute on function es_admin_o_mod(uuid) to authenticated;

-- ─── 2. puntos_jugador ──────────────────────────────────────────
-- Admin siempre puede. Moderador puede solo si puntos_mod_habilitado=true.
drop policy if exists "Admin escribe puntos_jugador" on puntos_jugador;

create policy "Admin o mod escribe puntos_jugador"
  on puntos_jugador for all
  using (
    exists (
      select 1 from federaciones f
      where f.id = puntos_jugador.federacion_id
        and (
          f.admin_user_id = auth.uid()
          or (
            f.puntos_mod_habilitado = true
            and exists (
              select 1 from moderadores m
              join  participantes pa on pa.id = m.participante_id
              where m.federacion_id = f.id
                and pa.user_id      = auth.uid()
            )
          )
        )
    )
  )
  with check (
    exists (
      select 1 from federaciones f
      where f.id = puntos_jugador.federacion_id
        and (
          f.admin_user_id = auth.uid()
          or (
            f.puntos_mod_habilitado = true
            and exists (
              select 1 from moderadores m
              join  participantes pa on pa.id = m.participante_id
              where m.federacion_id = f.id
                and pa.user_id      = auth.uid()
            )
          )
        )
    )
  );

-- ─── 3. participantes.presupuesto ───────────────────────────────
drop policy if exists "Actualizar presupuesto propio o admin" on participantes;

create policy "Actualizar presupuesto propio o admin" on participantes for update
  using (
    user_id = auth.uid()
    or es_admin_o_mod(federacion_id)
  )
  with check (
    user_id = auth.uid()
    or es_admin_o_mod(federacion_id)
  );

-- ─── 4. jornadas_cierre ─────────────────────────────────────────
drop policy if exists "Escritura admin federación jornadas_cierre" on jornadas_cierre;

create policy "Escritura admin o mod jornadas_cierre"
  on jornadas_cierre for all
  using   ( es_admin_o_mod(jornadas_cierre.federacion_id) )
  with check ( es_admin_o_mod(jornadas_cierre.federacion_id) );

-- ─── 5. resolver_puja ───────────────────────────────────────────
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
  if not es_admin_o_mod(p_federacion_id) then
    raise exception 'no_autorizado';
  end if;

  select p.*, pa.federacion_id as fed_id
    into v_puja
    from pujas p
    join participantes pa on pa.id = p.participante_id
   where p.id = p_puja_id
     and pa.federacion_id = p_federacion_id
     for update;

  if not found then raise exception 'puja_no_encontrada'; end if;
  if v_puja.resuelta then raise exception 'puja_ya_resuelta'; end if;

  select presupuesto into v_presupuesto
    from participantes where id = v_puja.participante_id;
  if v_presupuesto < v_puja.cantidad then raise exception 'presupuesto_insuficiente'; end if;

  select posicion, equipo into v_jug_posicion, v_jug_equipo
    from jugadores where id = p_jugador_id;

  if v_jug_posicion = 'POR' then
    select division_id into v_div_ganador
      from participantes where id = v_puja.participante_id;
    if exists (
      select 1 from plantillas pl
      join participantes pa on pa.id = pl.participante_id
      join jugadores     ju on ju.id = pl.jugador_id
      where ju.posicion = 'POR' and ju.equipo = v_jug_equipo
        and pa.division_id = v_div_ganador and pa.federacion_id = p_federacion_id
    ) then raise exception 'porteria_ocupada'; end if;
  end if;

  select count(*) into v_planta_cnt
    from plantillas where participante_id = v_puja.participante_id;

  if v_planta_cnt < 14 then
    insert into plantillas (participante_id, jugador_id, precio_compra)
    values (v_puja.participante_id, p_jugador_id, v_puja.cantidad);
    v_pendiente := false;
  else
    if exists (
      select 1 from fichajes_pendientes
      where participante_id = v_puja.participante_id and jugador_id = p_jugador_id
    ) then raise exception 'ya_en_pendientes'; end if;
    insert into fichajes_pendientes (participante_id, jugador_id, precio_compra)
    values (v_puja.participante_id, p_jugador_id, v_puja.cantidad);
    v_pendiente := true;
  end if;

  update participantes set presupuesto = presupuesto - v_puja.cantidad
   where id = v_puja.participante_id;

  update pujas p set resuelta = true, ganadora = false
    from participantes pa
   where p.jugador_id = p_jugador_id and p.participante_id = pa.id
     and pa.federacion_id = p_federacion_id;

  update pujas set ganadora = true where id = p_puja_id;

  return jsonb_build_object('ok', true, 'pendiente', v_pendiente);
end;
$$;

grant execute on function resolver_puja(uuid, int, uuid) to authenticated;

-- ─── 6. activar_fichaje_pendiente ───────────────────────────────
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
  v_fp  record;
  v_cnt int;
begin
  select fp.*, pa.user_id, pa.federacion_id as fed_id
    into v_fp
    from fichajes_pendientes fp
    join participantes pa on pa.id = fp.participante_id
   where fp.id = p_pendiente_id
     for update;

  if not found then raise exception 'fichaje_no_encontrado'; end if;

  if v_fp.user_id is distinct from auth.uid()
     and not es_admin_o_mod(v_fp.fed_id)
  then raise exception 'no_autorizado'; end if;

  select count(*) into v_cnt from plantillas where participante_id = v_fp.participante_id;

  if v_cnt >= 14 then
    if p_liberar_jugador_id is null then raise exception 'plantilla_llena_indica_baja'; end if;
    delete from plantillas
     where participante_id = v_fp.participante_id and jugador_id = p_liberar_jugador_id;
    if not found then raise exception 'jugador_a_liberar_no_encontrado'; end if;
  end if;

  insert into plantillas (participante_id, jugador_id, precio_compra)
  values (v_fp.participante_id, v_fp.jugador_id, v_fp.precio_compra);

  delete from fichajes_pendientes where id = p_pendiente_id;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function activar_fichaje_pendiente(int, uuid, uuid) to authenticated;

-- ─── 7. anular_fichaje_pendiente ────────────────────────────────
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
  if not es_admin_o_mod(p_federacion_id) then raise exception 'no_autorizado'; end if;

  select fp.*
    into v_fp
    from fichajes_pendientes fp
    join participantes pa on pa.id = fp.participante_id
   where fp.id = p_pendiente_id and pa.federacion_id = p_federacion_id
     for update;

  if not found then raise exception 'fichaje_no_encontrado'; end if;

  update participantes set presupuesto = presupuesto + v_fp.precio_compra
   where id = v_fp.participante_id;

  delete from fichajes_pendientes where id = p_pendiente_id;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function anular_fichaje_pendiente(int, uuid) to authenticated;
