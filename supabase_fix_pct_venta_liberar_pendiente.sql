-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fix: pct_venta_mercado no se aplicaba al liberar jugador
--             para activar un fichaje pendiente
--
-- Problema: activar_fichaje_pendiente (rama "plantilla llena, libera
--   un jugador") abonaba el 100% del valor_mercado del jugador
--   liberado, ignorando el pct_venta_mercado configurado en la
--   federación. La venta normal (vender_jugador) sí lo aplicaba
--   correctamente, generando inconsistencia entre ambos caminos.
--
-- Fix: se replica en activar_fichaje_pendiente el mismo cálculo que
--   usa vender_jugador — reembolso = valor_mercado * pct_venta_mercado
--   / 100, salvo que el jugador liberado esté lesionado (plantillas.
--   lesionado), en cuyo caso se mantiene el reembolso al 100%, igual
--   que en vender_jugador.
--
-- Reemplaza la función definida en supabase_lesiones.sql.
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

drop function if exists activar_fichaje_pendiente(int, uuid, uuid);

create function activar_fichaje_pendiente(
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
  v_pend           record;
  v_cnt            int;
  v_max_jug        int;
  v_valor_lib      numeric := 0;
  v_lesionado_lib  boolean := false;
  v_pct            numeric := 100;
begin
  select * into v_pend from fichajes_pendientes where id = p_pendiente_id;
  if not found then raise exception 'fichaje_no_encontrado'; end if;

  if not (
    v_pend.participante_id in (select id from participantes where user_id = auth.uid())
    or exists (select 1 from federaciones where id = p_federacion_id and admin_user_id = auth.uid())
  ) then raise exception 'no_autorizado'; end if;

  v_max_jug := get_max_jugadores(p_federacion_id);

  -- Contar solo jugadores NO lesionados (plantillas.lesionado, por federación)
  select count(*) into v_cnt
    from plantillas
   where participante_id = v_pend.participante_id
     and not lesionado;

  if v_cnt >= v_max_jug then
    if p_liberar_jugador_id is null then
      raise exception 'plantilla_llena_indica_baja';
    end if;

    select coalesce(j.valor_mercado, 0), coalesce(pl.lesionado, false)
      into v_valor_lib, v_lesionado_lib
      from plantillas pl
      join jugadores j on j.id = pl.jugador_id
     where pl.participante_id = v_pend.participante_id
       and pl.jugador_id      = p_liberar_jugador_id;

    if not found then
      raise exception 'jugador_a_liberar_no_encontrado';
    end if;

    -- Reembolso: lesionado → 100%; sano → pct_venta_mercado% (igual que vender_jugador)
    select coalesce(pct_venta_mercado, 100) into v_pct
      from federaciones where id = p_federacion_id;

    v_valor_lib := case
      when v_lesionado_lib then v_valor_lib
      else round(v_valor_lib * v_pct / 100.0, 2)
    end;

    delete from plantillas
     where participante_id = v_pend.participante_id
       and jugador_id      = p_liberar_jugador_id;
    update participantes
       set presupuesto = presupuesto + v_valor_lib
     where id = v_pend.participante_id;
  end if;

  insert into plantillas (participante_id, jugador_id, precio_compra)
  values (v_pend.participante_id, v_pend.jugador_id, v_pend.precio_compra)
  on conflict (participante_id, jugador_id) do nothing;

  delete from fichajes_pendientes where id = p_pendiente_id;
end;
$$;

grant execute on function activar_fichaje_pendiente(int, uuid, uuid) to authenticated;
