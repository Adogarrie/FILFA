-- ═══════════════════════════════════════════════════════════════
-- FILFA — Reinicio de temporada
--
-- Borra todo el estado de la temporada de una federación:
-- plantillas, alineaciones, clasificaciones, pujas, ofertas,
-- cesiones, puntos fantasy, cierres, H2H. Conserva los equipos
-- (participantes) y resetea su presupuesto al inicial.
-- Resetea jornada_actual a 1.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

create or replace function reiniciar_federacion(p_federacion_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Verificar que el caller es admin de la federación
  if not exists (
    select 1 from federaciones
    where id = p_federacion_id and admin_user_id = auth.uid()
  ) then
    raise exception 'no_autorizado';
  end if;

  -- ── 1. Tablas con federacion_id directo ──────────────────────
  delete from sustituciones_auto where federacion_id = p_federacion_id;
  delete from jornada_no_jugo    where federacion_id = p_federacion_id;
  delete from puntos_jugador     where federacion_id = p_federacion_id;
  delete from jornadas_cierre    where federacion_id = p_federacion_id;
  delete from h2h_jornada_config where federacion_id = p_federacion_id;
  delete from h2h_vueltas_extra  where federacion_id = p_federacion_id;
  delete from h2h_partidos       where federacion_id = p_federacion_id;

  -- ── 2. Tablas con participante_id (indirecto) ─────────────────
  delete from alineaciones
    where participante_id in (
      select id from participantes where federacion_id = p_federacion_id
    );

  delete from cesiones
    where federacion_id = p_federacion_id;

  delete from ofertas_jugadores
    where ofertante_id   in (select id from participantes where federacion_id = p_federacion_id)
       or propietario_id in (select id from participantes where federacion_id = p_federacion_id);

  delete from pujas
    where participante_id in (
      select id from participantes where federacion_id = p_federacion_id
    );

  delete from fichajes_pendientes
    where participante_id in (
      select id from participantes where federacion_id = p_federacion_id
    );

  delete from plantillas
    where participante_id in (
      select id from participantes where federacion_id = p_federacion_id
    );

  delete from clasificacion
    where participante_id in (
      select id from participantes where federacion_id = p_federacion_id
    );

  -- ── 3. Resetear presupuesto de todos los equipos ─────────────
  update participantes
    set presupuesto = (
      select presupuesto_inicial from federaciones where id = p_federacion_id
    )
    where federacion_id = p_federacion_id;

  -- ── 4. Resetear jornada_actual a 1 ───────────────────────────
  update federaciones
    set jornada_actual = 1
    where id = p_federacion_id;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function reiniciar_federacion(uuid) to authenticated;
