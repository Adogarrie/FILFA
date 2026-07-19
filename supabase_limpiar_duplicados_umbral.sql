-- ═══════════════════════════════════════════════════════════════
-- FILFA — Limpieza de duplicados por debajo de un nuevo umbral
--
-- Se llama cuando el admin sube duplicados_valor_min.
-- Elimina copias extra solo de jugadores cuyo valor_mercado
-- quede por debajo del nuevo umbral, conservando la más antigua.
-- Devuelve precio_compra al presupuesto de cada equipo afectado.
--
-- REQUISITO: ejecutar supabase_duplicados.sql primero.
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

create or replace function limpiar_duplicados_bajo_umbral(
  p_federacion_id   uuid,
  p_nuevo_valor_min numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_afectados   int     := 0;
  v_reembolsado numeric := 0;
  v_row         record;
begin
  -- ── 0. Auth ──────────────────────────────────────────────────
  if not exists (
    select 1 from federaciones
     where id = p_federacion_id and admin_user_id = auth.uid()
  ) then
    raise exception 'no_autorizado';
  end if;

  -- Umbral 0 = todos los jugadores siguen siendo duplicables: nada que limpiar
  if p_nuevo_valor_min <= 0 then
    return jsonb_build_object('ok', true, 'afectados', 0, 'reembolsado', 0);
  end if;

  -- ── 1. Limpiar plantillas ─────────────────────────────────────
  -- Jugadores no-POR con valor < nuevo umbral y >1 copia: conservar min(id)

  for v_row in (
    select pl.jugador_id, min(pl.id) as keep_id
      from plantillas    pl
      join participantes pa on pa.id = pl.participante_id
      join jugadores     ju on ju.id = pl.jugador_id
     where pa.federacion_id             = p_federacion_id
       and ju.posicion                  <> 'POR'
       and coalesce(ju.valor_mercado, 0) < p_nuevo_valor_min
     group by pl.jugador_id
    having count(*) > 1
  ) loop

    select v_reembolsado + coalesce(sum(pl.precio_compra), 0)
      into v_reembolsado
      from plantillas    pl
      join participantes pa on pa.id = pl.participante_id
     where pl.jugador_id    = v_row.jugador_id
       and pl.id           <> v_row.keep_id
       and pa.federacion_id = p_federacion_id;

    update participantes pa
       set presupuesto = pa.presupuesto + pl.precio_compra
      from plantillas pl
     where pl.participante_id = pa.id
       and pl.jugador_id      = v_row.jugador_id
       and pl.id             <> v_row.keep_id
       and pa.federacion_id   = p_federacion_id;

    delete from plantillas pl
     using participantes pa
     where pl.participante_id = pa.id
       and pl.jugador_id      = v_row.jugador_id
       and pl.id             <> v_row.keep_id
       and pa.federacion_id   = p_federacion_id;

    v_afectados := v_afectados + 1;
  end loop;

  -- ── 2. Limpiar fichajes_pendientes ────────────────────────────
  -- Caso A: jugador (valor < umbral) ya tiene copia en plantillas
  --         → eliminar todos sus pendientes

  for v_row in (
    select distinct fp.jugador_id
      from fichajes_pendientes fp
      join participantes pa on pa.id = fp.participante_id
      join jugadores     ju on ju.id = fp.jugador_id
     where pa.federacion_id             = p_federacion_id
       and ju.posicion                  <> 'POR'
       and coalesce(ju.valor_mercado, 0) < p_nuevo_valor_min
       and exists (
         select 1 from plantillas    pl2
           join participantes pa2 on pa2.id = pl2.participante_id
          where pl2.jugador_id    = fp.jugador_id
            and pa2.federacion_id = p_federacion_id
       )
  ) loop

    select v_reembolsado + coalesce(sum(fp.precio_compra), 0)
      into v_reembolsado
      from fichajes_pendientes fp
      join participantes pa on pa.id = fp.participante_id
     where fp.jugador_id    = v_row.jugador_id
       and pa.federacion_id = p_federacion_id;

    update participantes pa
       set presupuesto = pa.presupuesto + fp.precio_compra
      from fichajes_pendientes fp
     where fp.participante_id = pa.id
       and fp.jugador_id      = v_row.jugador_id
       and pa.federacion_id   = p_federacion_id;

    delete from fichajes_pendientes fp
     using participantes pa
     where fp.participante_id = pa.id
       and fp.jugador_id      = v_row.jugador_id
       and pa.federacion_id   = p_federacion_id;

  end loop;

  -- Caso B: jugador (valor < umbral) sin copia en plantillas pero con >1 pendiente
  --         → conservar el más antiguo (min id)

  for v_row in (
    select fp.jugador_id, min(fp.id) as keep_id
      from fichajes_pendientes fp
      join participantes pa on pa.id = fp.participante_id
      join jugadores     ju on ju.id = fp.jugador_id
     where pa.federacion_id             = p_federacion_id
       and ju.posicion                  <> 'POR'
       and coalesce(ju.valor_mercado, 0) < p_nuevo_valor_min
       and not exists (
         select 1 from plantillas    pl2
           join participantes pa2 on pa2.id = pl2.participante_id
          where pl2.jugador_id    = fp.jugador_id
            and pa2.federacion_id = p_federacion_id
       )
     group by fp.jugador_id
    having count(*) > 1
  ) loop

    select v_reembolsado + coalesce(sum(fp.precio_compra), 0)
      into v_reembolsado
      from fichajes_pendientes fp
      join participantes pa on pa.id = fp.participante_id
     where fp.jugador_id    = v_row.jugador_id
       and fp.id           <> v_row.keep_id
       and pa.federacion_id = p_federacion_id;

    update participantes pa
       set presupuesto = pa.presupuesto + fp.precio_compra
      from fichajes_pendientes fp
     where fp.participante_id = pa.id
       and fp.jugador_id      = v_row.jugador_id
       and fp.id             <> v_row.keep_id
       and pa.federacion_id   = p_federacion_id;

    delete from fichajes_pendientes fp
     using participantes pa
     where fp.participante_id = pa.id
       and fp.jugador_id      = v_row.jugador_id
       and fp.id             <> v_row.keep_id
       and pa.federacion_id   = p_federacion_id;

    v_afectados := v_afectados + 1;
  end loop;

  return jsonb_build_object(
    'ok',          true,
    'afectados',   v_afectados,
    'reembolsado', v_reembolsado
  );
end;
$$;

grant execute on function limpiar_duplicados_bajo_umbral(uuid, numeric) to authenticated;
