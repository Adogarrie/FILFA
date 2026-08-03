-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fichaje directo de sustituto por lesión
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

drop function if exists fichar_sustituto_lesion(uuid, uuid, uuid);

create function fichar_sustituto_lesion(
  p_jugador_id      uuid,
  p_participante_id uuid,
  p_federacion_id   uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_valor    numeric;
  v_presp    numeric;
  v_cnt_sano int;
  v_max      int;
begin
  -- Autorización: el llamante es el propietario del equipo o el admin de la federación
  if not (
    exists (select 1 from participantes where id = p_participante_id and user_id = auth.uid())
    or exists (select 1 from federaciones where id = p_federacion_id and admin_user_id = auth.uid())
  ) then
    raise exception 'no_autorizado';
  end if;

  -- El equipo debe tener al menos un jugador lesionado (evita usar este atajo sin lesión)
  if not exists (
    select 1 from plantillas
     where participante_id = p_participante_id and lesionado = true
  ) then
    raise exception 'sin_lesionados';
  end if;

  -- El jugador debe estar libre en la federación (ni en plantilla ni en pendientes)
  if exists (
    select 1 from plantillas pl
      join participantes pa on pa.id = pl.participante_id
     where pl.jugador_id = p_jugador_id and pa.federacion_id = p_federacion_id
  ) or exists (
    select 1 from fichajes_pendientes fp
      join participantes pa on pa.id = fp.participante_id
     where fp.jugador_id = p_jugador_id and pa.federacion_id = p_federacion_id
  ) then
    raise exception 'jugador_ocupado';
  end if;

  -- Precio = valor de mercado actual
  select valor_mercado into v_valor from jugadores where id = p_jugador_id;
  if not found then raise exception 'jugador_no_encontrado'; end if;
  if v_valor is null then v_valor := 0; end if;

  -- Comprobar presupuesto
  select presupuesto into v_presp from participantes where id = p_participante_id;
  if coalesce(v_presp, 0) < v_valor then
    raise exception 'presupuesto_insuficiente';
  end if;

  -- Comprobar límite de jugadores activos (lesionados no cuentan)
  v_max := get_max_jugadores(p_federacion_id);
  select count(*) into v_cnt_sano
    from plantillas where participante_id = p_participante_id and not lesionado;
  if v_cnt_sano >= v_max then
    raise exception 'plantilla_llena';
  end if;

  -- Fichar: insertar en plantillas y descontar presupuesto
  insert into plantillas (participante_id, jugador_id, precio_compra)
  values (p_participante_id, p_jugador_id, v_valor)
  on conflict (participante_id, jugador_id) do nothing;

  update participantes
     set presupuesto = presupuesto - v_valor
   where id = p_participante_id;

  return jsonb_build_object('ok', true, 'precio', v_valor);
end;
$$;

grant execute on function fichar_sustituto_lesion(uuid, uuid, uuid) to authenticated;
