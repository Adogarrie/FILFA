-- ═══════════════════════════════════════════════════════════════
-- FILFA — Traspaso pendiente: columna + RPC descartar
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- Columna para marcar fichajes pendientes que vienen de un traspaso
alter table fichajes_pendientes
  add column if not exists traspaso_de_id uuid default null
  references participantes(id) on delete set null;

-- ── RPC: descartar un traspaso pendiente ──────────────────────
-- Reembolsa el 80% al comprador (siempre, tomado del vendedor).
-- Si el vendedor tiene plaza libre (<14), el jugador vuelve a su plantilla.
-- Si no, el jugador queda libre en el mercado.
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
  v_refund     numeric;
  v_cnt        int;
  v_devuelto   boolean := false;
  v_nom_jug    text;
begin
  -- 1. Cargar fichaje pendiente
  select * into v_pend from fichajes_pendientes where id = p_pendiente_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'fichaje_no_encontrado');
  end if;
  if v_pend.traspaso_de_id is null then
    return jsonb_build_object('ok', false, 'error', 'no_es_traspaso');
  end if;

  -- 2. Verificar permiso (participante comprador o admin de la federación)
  if not (
    v_pend.participante_id in (select id from participantes where user_id = auth.uid())
    or exists (select 1 from federaciones where id = p_federacion_id and admin_user_id = auth.uid())
  ) then
    return jsonb_build_object('ok', false, 'error', 'no_autorizado');
  end if;

  -- 3. Cargar datos
  select * into v_comprador from participantes where id = v_pend.participante_id;
  select * into v_vendedor  from participantes where id = v_pend.traspaso_de_id;
  select * into v_jug       from jugadores     where id = v_pend.jugador_id;

  v_refund := round(v_pend.precio_compra * 0.8, 2);

  -- 4. ¿El vendedor tiene hueco en la plantilla?
  select count(*) into v_cnt from plantillas where participante_id = v_pend.traspaso_de_id;

  if v_cnt < 14 then
    -- Devolver jugador al vendedor
    insert into plantillas (participante_id, jugador_id, precio_compra)
    values (v_pend.traspaso_de_id, v_pend.jugador_id, v_pend.precio_compra)
    on conflict (participante_id, jugador_id) do nothing;
    v_devuelto := true;
  end if;
  -- Si la plantilla está llena el jugador queda libre (no se inserta en ninguna plantilla)

  -- 5. Transferencia: vendedor devuelve el 80% al comprador
  update participantes set presupuesto = presupuesto - v_refund where id = v_pend.traspaso_de_id;
  update participantes set presupuesto = presupuesto + v_refund where id = v_pend.participante_id;

  -- 6. Eliminar el fichaje pendiente
  delete from fichajes_pendientes where id = p_pendiente_id;

  -- 7. Anuncio en el tablón
  v_nom_jug := case when v_jug.posicion = 'POR' then 'Portería ' || v_jug.equipo else v_jug.nombre end;
  insert into anuncios (federacion_id, tipo, texto)
  values (
    p_federacion_id,
    'traspaso',
    v_comprador.nombre || ' descarta el traspaso de ' || v_nom_jug
    || case when v_devuelto
         then ' · Vuelve a ' || v_vendedor.nombre
         else ' · Queda libre (plantilla de ' || v_vendedor.nombre || ' llena)'
       end
    || ' · Reembolso: ' || to_char(v_refund, 'FM999G999G999') || ' €'
  );

  return jsonb_build_object(
    'ok',       true,
    'devuelto', v_devuelto,
    'refund',   v_refund
  );
end;
$$;

grant execute on function anular_traspaso_pendiente(int, uuid) to authenticated;
