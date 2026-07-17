-- ═══════════════════════════════════════════════════════════════
-- FILFA — Descarte de fichajes pendientes usa pct_venta_mercado
-- Ejecutar DESPUÉS de supabase_pct_venta_mercado.sql
-- ═══════════════════════════════════════════════════════════════

-- ─── anular_fichaje_pendiente ─────────────────────────────────
drop function if exists anular_fichaje_pendiente(int, uuid);

create function anular_fichaje_pendiente(
  p_pendiente_id  int,
  p_federacion_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pend   record;
  v_pct    int;
  v_refund numeric;
begin
  select * into v_pend from fichajes_pendientes where id = p_pendiente_id;
  if not found then raise exception 'fichaje_no_encontrado'; end if;

  if not (
    v_pend.participante_id in (select id from participantes where user_id = auth.uid())
    or exists (select 1 from federaciones where id = p_federacion_id and admin_user_id = auth.uid())
  ) then raise exception 'no_autorizado'; end if;

  select coalesce(pct_venta_mercado, 100) into v_pct
    from federaciones where id = p_federacion_id;

  v_refund := round(v_pend.precio_compra * v_pct / 100.0, 2);

  update participantes
     set presupuesto = presupuesto + v_refund
   where id = v_pend.participante_id;

  delete from fichajes_pendientes where id = p_pendiente_id;
end;
$$;

grant execute on function anular_fichaje_pendiente(int, uuid) to authenticated;


-- ─── anular_traspaso_pendiente ────────────────────────────────
drop function if exists anular_traspaso_pendiente(int, uuid);

create function anular_traspaso_pendiente(
  p_pendiente_id  int,
  p_federacion_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pend       record;
  v_comprador  record;
  v_vendedor   record;
  v_jug        record;
  v_pct        int;
  v_refund     numeric;
  v_cnt        int;
  v_devuelto   boolean := false;
  v_nom_jug    text;
begin
  select * into v_pend from fichajes_pendientes where id = p_pendiente_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'fichaje_no_encontrado');
  end if;
  if v_pend.traspaso_de_id is null then
    return jsonb_build_object('ok', false, 'error', 'no_es_traspaso');
  end if;

  if not (
    v_pend.participante_id in (select id from participantes where user_id = auth.uid())
    or exists (select 1 from federaciones where id = p_federacion_id and admin_user_id = auth.uid())
  ) then
    return jsonb_build_object('ok', false, 'error', 'no_autorizado');
  end if;

  select * into v_comprador from participantes where id = v_pend.participante_id;
  select * into v_vendedor  from participantes where id = v_pend.traspaso_de_id;
  select * into v_jug       from jugadores     where id = v_pend.jugador_id;

  select coalesce(pct_venta_mercado, 100) into v_pct
    from federaciones where id = p_federacion_id;

  v_refund := round(v_pend.precio_compra * v_pct / 100.0, 2);

  select count(*) into v_cnt from plantillas where participante_id = v_pend.traspaso_de_id;

  if v_cnt < 14 then
    insert into plantillas (participante_id, jugador_id, precio_compra)
    values (v_pend.traspaso_de_id, v_pend.jugador_id, v_pend.precio_compra)
    on conflict (participante_id, jugador_id) do nothing;
    v_devuelto := true;
  end if;

  update participantes set presupuesto = presupuesto - v_refund where id = v_pend.traspaso_de_id;
  update participantes set presupuesto = presupuesto + v_refund where id = v_pend.participante_id;

  delete from fichajes_pendientes where id = p_pendiente_id;

  v_nom_jug := case when v_jug.posicion = 'POR' then 'Portería ' || v_jug.equipo else v_jug.nombre end;
  insert into anuncios (federacion_id, tipo, texto)
  values (
    p_federacion_id, 'traspaso',
    v_comprador.nombre || ' descarta el traspaso de ' || v_nom_jug
    || case when v_devuelto
         then ' · Vuelve a ' || v_vendedor.nombre
         else ' · Queda libre (plantilla de ' || v_vendedor.nombre || ' llena)'
       end
    || ' · Reembolso: ' || to_char(v_refund, 'FM999G999G999') || ' € (' || v_pct || '%)'
  );

  return jsonb_build_object('ok', true, 'devuelto', v_devuelto, 'refund', v_refund);
end;
$$;

grant execute on function anular_traspaso_pendiente(int, uuid) to authenticated;
