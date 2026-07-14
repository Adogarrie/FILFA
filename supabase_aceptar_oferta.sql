-- ═══════════════════════════════════════════════════════════════
-- FILFA — RPC aceptar_oferta
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

drop function if exists aceptar_oferta(int);

create function aceptar_oferta(p_oferta_id int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_oferta    record;
  v_jug       record;
  v_ofertante record;
  v_prop      record;
  v_nom_jug   text;
begin
  -- 1. Leer y bloquear la oferta
  select * into v_oferta from ofertas_jugadores where id = p_oferta_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'oferta_no_encontrada'); end if;
  if v_oferta.estado <> 'pendiente' then return jsonb_build_object('ok', false, 'error', 'oferta_no_pendiente'); end if;

  -- 2. Solo el propietario o admin de la federación pueden aceptar
  if not (
    v_oferta.propietario_id in (select id from participantes where user_id = auth.uid())
    or exists (select 1 from federaciones where id = v_oferta.federacion_id and admin_user_id = auth.uid())
  ) then return jsonb_build_object('ok', false, 'error', 'sin_permiso'); end if;

  -- 3. Cargar datos relacionados
  select * into v_jug       from jugadores     where id = v_oferta.jugador_id;
  select * into v_ofertante from participantes where id = v_oferta.ofertante_id;
  select * into v_prop      from participantes where id = v_oferta.propietario_id;

  -- 4. Verificar presupuesto del ofertante
  if v_ofertante.presupuesto < v_oferta.cantidad then
    return jsonb_build_object('ok', false, 'error', 'presupuesto_insuficiente');
  end if;

  -- 5. Quitar de la plantilla del vendedor
  delete from plantillas
   where participante_id = v_oferta.propietario_id
     and jugador_id      = v_oferta.jugador_id;

  -- 6. Siempre va a fichajes_pendientes — el admin decidirá cuándo activar o descartar.
  --    traspaso_de_id guarda quién vendió para poder devolver el jugador si se descarta.
  insert into fichajes_pendientes (participante_id, jugador_id, precio_compra, traspaso_de_id)
  values (v_oferta.ofertante_id, v_oferta.jugador_id, v_oferta.cantidad, v_oferta.propietario_id)
  on conflict (participante_id, jugador_id) do update
    set precio_compra  = excluded.precio_compra,
        traspaso_de_id = excluded.traspaso_de_id;

  -- 7. Transferencia de dinero inmediata
  update participantes set presupuesto = presupuesto - v_oferta.cantidad where id = v_oferta.ofertante_id;
  update participantes set presupuesto = presupuesto + v_oferta.cantidad where id = v_oferta.propietario_id;

  -- 8. Cerrar esta oferta y rechazar las demás pendientes del mismo jugador
  update ofertas_jugadores set estado = 'aceptada' where id = p_oferta_id;
  update ofertas_jugadores
     set estado = 'rechazada'
   where jugador_id    = v_oferta.jugador_id
     and federacion_id = v_oferta.federacion_id
     and estado        = 'pendiente'
     and id            <> p_oferta_id;

  -- 9. Anuncio en el tablón
  v_nom_jug := case when v_jug.posicion = 'POR' then 'Portería ' || v_jug.equipo else v_jug.nombre end;
  insert into anuncios (federacion_id, tipo, texto)
  values (
    v_oferta.federacion_id,
    'fichaje',
    v_ofertante.nombre || ' acuerda el traspaso de ' || v_nom_jug
    || ' de ' || v_prop.nombre
    || ' por ' || to_char(v_oferta.cantidad, 'FM999G999G999') || ' €'
    || ' — pendiente de activar plaza'
  );

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function aceptar_oferta(int) to authenticated;
