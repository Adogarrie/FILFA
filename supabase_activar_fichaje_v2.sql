-- ═══════════════════════════════════════════════════════════════
-- FILFA — activar_fichaje_pendiente v2
--
-- Cambios respecto a la versión anterior:
--   · Límite de plantilla usa get_max_jugadores() en lugar de 14
--   · Al liberar un jugador: devuelve pct_venta_mercado% de su
--     valor_mercado (en lugar del 100% anterior), excepto si el
--     jugador está lesionado, en cuyo caso se devuelve el 100%.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

drop function if exists activar_fichaje_pendiente(int, uuid, uuid);

create or replace function activar_fichaje_pendiente(
  p_pendiente_id       int,
  p_liberar_jugador_id uuid,
  p_federacion_id      uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pend      record;
  v_cnt       int;
  v_max_jug   int;
  v_valor_lib numeric := 0;
  v_lesionado boolean := false;
  v_pct       int;
  v_refund    numeric := 0;
begin
  -- 1. Cargar fichaje pendiente
  select * into v_pend from fichajes_pendientes where id = p_pendiente_id;
  if not found then raise exception 'fichaje_no_encontrado'; end if;

  -- 2. Verificar permiso (equipo propietario o admin de la federación)
  if not (
    v_pend.participante_id in (select id from participantes where user_id = auth.uid())
    or exists (select 1 from federaciones where id = p_federacion_id and admin_user_id = auth.uid())
  ) then raise exception 'no_autorizado'; end if;

  -- 3. Límite configurable por federación
  v_max_jug := get_max_jugadores(p_federacion_id);

  -- 4. Comprobar si la plantilla tiene hueco
  select count(*) into v_cnt from plantillas where participante_id = v_pend.participante_id;

  if v_cnt >= v_max_jug then
    if p_liberar_jugador_id is null then
      raise exception 'plantilla_llena_indica_baja';
    end if;
    if not exists (
      select 1 from plantillas
       where participante_id = v_pend.participante_id
         and jugador_id      = p_liberar_jugador_id
    ) then
      raise exception 'jugador_a_liberar_no_encontrado';
    end if;

    -- Valor de mercado y estado de lesión del jugador que sale
    select coalesce(j.valor_mercado, 0), coalesce(j.lesionado, false)
      into v_valor_lib, v_lesionado
      from jugadores j
     where j.id = p_liberar_jugador_id;

    -- Porcentaje configurado por la federación
    select coalesce(pct_venta_mercado, 100) into v_pct
      from federaciones where id = p_federacion_id;

    -- Lesionado → devuelve el 100%; sano → devuelve pct_venta_mercado%
    v_refund := case
      when v_lesionado then v_valor_lib
      else round(v_valor_lib * v_pct / 100.0, 2)
    end;

    -- Liberar de la plantilla
    delete from plantillas
     where participante_id = v_pend.participante_id
       and jugador_id      = p_liberar_jugador_id;

    -- Abonar al presupuesto
    update participantes
       set presupuesto = presupuesto + v_refund
     where id = v_pend.participante_id;
  end if;

  -- 5. Mover el fichaje pendiente a la plantilla activa
  insert into plantillas (participante_id, jugador_id, precio_compra)
  values (v_pend.participante_id, v_pend.jugador_id, v_pend.precio_compra)
  on conflict (participante_id, jugador_id) do nothing;

  -- 6. Eliminar de pendientes
  delete from fichajes_pendientes where id = p_pendiente_id;
end;
$$;

grant execute on function activar_fichaje_pendiente(int, uuid, uuid) to authenticated;
