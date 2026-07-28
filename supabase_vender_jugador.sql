-- ═══════════════════════════════════════════════════════════════
-- FILFA — vender_jugador
--
-- Atomiza la venta de un jugador al mercado:
--   · DELETE plantillas
--   · UPDATE presupuesto
--   · UPDATE sustituciones_lesion (si lesionado y mercado cerrado)
-- Todo en una sola transacción: si cualquier paso falla, nada cambia.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

create or replace function vender_jugador(
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
  v_valor      numeric;
  v_lesionado  boolean;
  v_pct        int;
  v_ventas_hab boolean;
  v_refund     numeric;
  v_inc_sust   boolean := false;
begin
  -- 1. Autorización: propietario del equipo o admin de la federación
  if not (
    p_participante_id in (select id from participantes where user_id = auth.uid())
    or exists (select 1 from federaciones where id = p_federacion_id and admin_user_id = auth.uid())
  ) then
    raise exception 'no_autorizado';
  end if;

  -- 2. Leer datos del jugador y verificar que pertenece al participante
  select coalesce(j.valor_mercado, 0), coalesce(j.lesionado, false)
    into v_valor, v_lesionado
    from plantillas pl
    join jugadores  j on j.id = pl.jugador_id
   where pl.id              = p_plantilla_id
     and pl.participante_id = p_participante_id;

  if not found then raise exception 'jugador_no_en_plantilla'; end if;

  -- 3. Datos de la federación
  select coalesce(pct_venta_mercado, 100), coalesce(ventas_habilitadas, true)
    into v_pct, v_ventas_hab
    from federaciones where id = p_federacion_id;

  -- 4. Calcular reembolso: lesionado → 100%; sano → pct_venta_mercado%
  v_refund := case
    when v_lesionado then v_valor
    else round(v_valor * v_pct / 100.0, 2)
  end;

  -- 5. Eliminar de la plantilla
  delete from plantillas where id = p_plantilla_id;

  -- 6. Abonar reembolso al presupuesto
  update participantes
     set presupuesto = presupuesto + v_refund
   where id = p_participante_id;

  -- 7. Si lesionado y mercado cerrado: contar sustitución por lesión
  if v_lesionado and not v_ventas_hab then
    update participantes
       set sustituciones_lesion = coalesce(sustituciones_lesion, 0) + 1
     where id = p_participante_id;
    v_inc_sust := true;
  end if;

  return jsonb_build_object(
    'ok',          true,
    'valor_venta', v_refund,
    'lesionado',   v_lesionado,
    'sust_lesion', v_inc_sust
  );
end;
$$;

grant execute on function vender_jugador(int, uuid, uuid) to authenticated;
