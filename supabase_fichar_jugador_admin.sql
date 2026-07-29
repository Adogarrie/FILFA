-- ═══════════════════════════════════════════════════════════════
-- FILFA — fichar_jugador_admin
--
-- Fichaje directo por el admin desde el Mercado (sin puja).
-- Atomiza en una sola transacción:
--   · INSERT en plantillas
--   · UPDATE presupuesto del equipo
--   · Decremento de sustituciones_lesion si mercado cerrado y quedan
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

create or replace function fichar_jugador_admin(
  p_participante_id uuid,
  p_jugador_id      uuid,
  p_precio          numeric,
  p_federacion_id   uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ventas_hab boolean;
  v_sust       int;
  v_dec_sust   boolean := false;
begin
  -- 1. Autorización: solo admin de la federación
  if not exists (
    select 1 from federaciones
    where id = p_federacion_id and admin_user_id = auth.uid()
  ) then
    raise exception 'no_autorizado';
  end if;

  -- 2. Verificar que el participante pertenece a esta federación
  if not exists (
    select 1 from participantes
    where id = p_participante_id and federacion_id = p_federacion_id
  ) then
    raise exception 'participante_no_encontrado';
  end if;

  -- 3. Verificar que el jugador no está ya en la plantilla del equipo
  if exists (
    select 1 from plantillas
    where participante_id = p_participante_id and jugador_id = p_jugador_id
  ) then
    raise exception 'jugador_ya_en_plantilla';
  end if;

  -- 4. Datos de la federación
  select coalesce(ventas_habilitadas, true)
    into v_ventas_hab
    from federaciones where id = p_federacion_id;

  -- 5. ¿Cuenta como sustitución por lesión?
  --    Solo si mercado cerrado y el equipo tiene sustituciones disponibles
  if not v_ventas_hab then
    select coalesce(sustituciones_lesion, 0) into v_sust
      from participantes where id = p_participante_id;
    if v_sust > 0 then
      v_dec_sust := true;
    end if;
  end if;

  -- 6. Insertar en plantillas
  insert into plantillas (participante_id, jugador_id, precio_compra)
  values (p_participante_id, p_jugador_id, p_precio);

  -- 7. Descontar presupuesto (y sustituciones si aplica)
  update participantes
     set presupuesto         = presupuesto - p_precio,
         sustituciones_lesion = case
           when v_dec_sust then coalesce(sustituciones_lesion, 0) - 1
           else sustituciones_lesion
         end
   where id = p_participante_id;

  return jsonb_build_object(
    'ok',        true,
    'dec_sust',  v_dec_sust
  );
end;
$$;

grant execute on function fichar_jugador_admin(uuid, uuid, numeric, uuid) to authenticated;
