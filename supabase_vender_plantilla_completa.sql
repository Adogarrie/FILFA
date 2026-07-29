-- ═══════════════════════════════════════════════════════════════
-- FILFA — vender_plantilla_completa
--
-- Vende todos los jugadores de un equipo en una sola transacción:
--   · Lesionados  → reembolso 100 % de su valor_mercado
--   · Sanos       → reembolso pct_venta_mercado % de su valor_mercado
--   · Si mercado cerrado, incrementa sustituciones_lesion por
--     cada jugador lesionado vendido (igual que vender_jugador)
--   · Acción exclusiva del admin de la federación
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

create or replace function vender_plantilla_completa(
  p_participante_id uuid,
  p_federacion_id   uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pct          int;
  v_ventas_hab   boolean;
  v_total        numeric := 0;
  v_sust         int     := 0;
  v_count        int     := 0;
  v_valor        numeric;
  v_lesionado    boolean;
  v_plantilla_id int;
  v_jugador_id   uuid;
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

  -- 3. Datos de la federación
  select coalesce(pct_venta_mercado, 100), coalesce(ventas_habilitadas, true)
    into v_pct, v_ventas_hab
    from federaciones where id = p_federacion_id;

  -- 4. Calcular reembolso total y acumular sustituciones por lesión
  for v_plantilla_id, v_jugador_id in
    select pl.id, pl.jugador_id from plantillas pl
    where pl.participante_id = p_participante_id
  loop
    select coalesce(j.valor_mercado, 0), coalesce(j.lesionado, false)
      into v_valor, v_lesionado
      from jugadores j where j.id = v_jugador_id;

    v_total := v_total + case
      when v_lesionado then v_valor
      else round(v_valor * v_pct / 100.0, 2)
    end;

    if v_lesionado and not v_ventas_hab then
      v_sust := v_sust + 1;
    end if;

    v_count := v_count + 1;
  end loop;

  if v_count = 0 then
    return jsonb_build_object('ok', true, 'total', 0, 'jugadores_count', 0);
  end if;

  -- 5. Eliminar toda la plantilla
  delete from plantillas where participante_id = p_participante_id;

  -- 6. Abonar reembolso total al presupuesto
  update participantes
     set presupuesto = presupuesto + v_total
   where id = p_participante_id;

  -- 7. Incrementar sustituciones_lesion si aplica
  if v_sust > 0 then
    update participantes
       set sustituciones_lesion = coalesce(sustituciones_lesion, 0) + v_sust
     where id = p_participante_id;
  end if;

  return jsonb_build_object(
    'ok',             true,
    'total',          v_total,
    'jugadores_count', v_count,
    'sust_lesion',    v_sust
  );
end;
$$;

grant execute on function vender_plantilla_completa(uuid, uuid) to authenticated;
