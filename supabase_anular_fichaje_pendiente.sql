-- ═══════════════════════════════════════════════════════════════
-- FILFA — anular_fichaje_pendiente (versión definitiva)
--
-- Consolida todas las versiones anteriores en una sola correcta:
--   · Puede cancelar: el propietario del equipo O admin/mod
--   · Reembolso: pct_venta_mercado% del precio pagado
--   · Devuelve jsonb para manejo de errores en el frontend
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

drop function if exists anular_fichaje_pendiente(int, uuid);

create or replace function anular_fichaje_pendiente(
  p_pendiente_id  int,
  p_federacion_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fp     record;
  v_pct    int;
  v_refund numeric;
begin
  -- 1. Cargar y bloquear el fichaje pendiente
  select fp.*
    into v_fp
    from fichajes_pendientes fp
    join participantes pa on pa.id = fp.participante_id
   where fp.id            = p_pendiente_id
     and pa.federacion_id = p_federacion_id
     for update;

  if not found then raise exception 'fichaje_no_encontrado'; end if;

  -- 2. Autorización: propietario del equipo o admin/moderador
  if not (
    v_fp.participante_id in (select id from participantes where user_id = auth.uid())
    or es_admin_o_mod(p_federacion_id)
  ) then
    raise exception 'no_autorizado';
  end if;

  -- 3. Porcentaje de reembolso de la federación
  select coalesce(pct_venta_mercado, 100) into v_pct
    from federaciones where id = p_federacion_id;

  -- 4. Calcular y abonar reembolso
  v_refund := round(v_fp.precio_compra * v_pct / 100.0, 2);

  update participantes
     set presupuesto = presupuesto + v_refund
   where id = v_fp.participante_id;

  -- 5. Eliminar el fichaje pendiente
  delete from fichajes_pendientes where id = p_pendiente_id;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function anular_fichaje_pendiente(int, uuid) to authenticated;
