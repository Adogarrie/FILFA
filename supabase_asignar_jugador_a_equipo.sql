-- ═══════════════════════════════════════════════════════════════
-- FILFA — asignar_jugador_a_equipo
--
-- Asigna un jugador ya creado a la plantilla de un equipo,
-- descontando el precio del presupuesto en una sola transacción.
-- Exclusivo para el admin de la federación.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

create or replace function asignar_jugador_a_equipo(
  p_jugador_id      uuid,
  p_participante_id uuid,
  p_precio          numeric,
  p_federacion_id   uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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

  -- 3. Insertar en plantillas
  insert into plantillas (participante_id, jugador_id, precio_compra)
  values (p_participante_id, p_jugador_id, p_precio);

  -- 4. Descontar presupuesto (leyendo desde la BD, no del frontend)
  update participantes
     set presupuesto = presupuesto - p_precio
   where id = p_participante_id;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function asignar_jugador_a_equipo(uuid, uuid, numeric, uuid) to authenticated;
