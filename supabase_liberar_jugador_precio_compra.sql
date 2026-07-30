-- ═══════════════════════════════════════════════════════════════
-- FILFA — liberar_jugador_precio_compra
--
-- Libera un jugador de una plantilla devolviendo su precio de compra,
-- en una sola transacción atómica. Exclusivo para el admin.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

create or replace function liberar_jugador_precio_compra(
  p_plantilla_id    int,
  p_participante_id uuid,
  p_federacion_id   uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_precio numeric;
begin
  -- 1. Autorización: solo admin de la federación
  if not exists (
    select 1 from federaciones
    where id = p_federacion_id and admin_user_id = auth.uid()
  ) then
    raise exception 'no_autorizado';
  end if;

  -- 2. Leer precio_compra desde la BD
  select coalesce(precio_compra, 0) into v_precio
    from plantillas
   where id = p_plantilla_id and participante_id = p_participante_id;

  if not found then
    raise exception 'jugador_no_encontrado';
  end if;

  -- 3. Eliminar de plantillas
  delete from plantillas where id = p_plantilla_id;

  -- 4. Devolver precio de compra al presupuesto
  update participantes
     set presupuesto = presupuesto + v_precio
   where id = p_participante_id;

  return jsonb_build_object('ok', true, 'valor', v_precio);
end;
$$;

grant execute on function liberar_jugador_precio_compra(int, uuid, uuid) to authenticated;
