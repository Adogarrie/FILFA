-- ═══════════════════════════════════════════════════════════════
-- FILFA — RPC: resolver_puja
--
-- Adjudica una puja de forma atómica:
--   · Valida presupuesto, límite de plantilla y portería única
--   · Inserta en plantillas
--   · Descuenta presupuesto
--   · Marca todas las pujas del jugador como resueltas
--   · Marca la puja ganadora
--
-- Todo ocurre en una sola transacción. Si cualquier paso falla,
-- PostgreSQL deshace todo automáticamente.
--
-- El FOR UPDATE en la puja ganadora bloquea la fila hasta que la
-- transacción termina, impidiendo que dos admins adjudiquen el
-- mismo jugador de forma concurrente.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

create or replace function resolver_puja(
  p_jugador_id     uuid,
  p_puja_id        int,
  p_federacion_id  uuid
)
returns jsonb
language plpgsql
security definer          -- necesario para escribir plantillas/presupuesto
set search_path = public  -- evita search_path injection
as $$
declare
  v_puja         record;
  v_presupuesto  numeric;
  v_planta_cnt   int;
  v_jug_posicion text;
  v_jug_equipo   text;
  v_div_ganador  int;
begin
  -- ── 0. Verificar que el caller es admin de esta federación ─────
  if not exists (
    select 1 from federaciones
    where  id = p_federacion_id
      and  admin_user_id = auth.uid()
  ) then
    raise exception 'no_autorizado';
  end if;

  -- ── 1. Bloquear la puja ganadora (serializa adjudicaciones concurrentes) ─
  select p.*, pa.federacion_id as fed_id
    into v_puja
    from pujas p
    join participantes pa on pa.id = p.participante_id
   where p.id = p_puja_id
     and pa.federacion_id = p_federacion_id
     for update;

  if not found then
    raise exception 'puja_no_encontrada';
  end if;

  if v_puja.resuelta then
    raise exception 'puja_ya_resuelta';
  end if;

  -- ── 2. Verificar presupuesto ────────────────────────────────────
  select presupuesto into v_presupuesto
    from participantes
   where id = v_puja.participante_id;

  if v_presupuesto < v_puja.cantidad then
    raise exception 'presupuesto_insuficiente';
  end if;

  -- ── 3. Verificar límite de plantilla (máx 14) ──────────────────
  select count(*) into v_planta_cnt
    from plantillas
   where participante_id = v_puja.participante_id;

  if v_planta_cnt >= 14 then
    raise exception 'plantilla_completa';
  end if;

  -- ── 4. Verificar portería única por división (solo para POR) ───
  select posicion, equipo
    into v_jug_posicion, v_jug_equipo
    from jugadores
   where id = p_jugador_id;

  if v_jug_posicion = 'POR' then
    select division_id into v_div_ganador
      from participantes
     where id = v_puja.participante_id;

    if exists (
      select 1
        from plantillas pl
        join participantes pa on pa.id = pl.participante_id
        join jugadores     ju on ju.id = pl.jugador_id
       where ju.posicion       = 'POR'
         and ju.equipo         = v_jug_equipo
         and pa.division_id    = v_div_ganador
         and pa.federacion_id  = p_federacion_id
    ) then
      raise exception 'porteria_ocupada';
    end if;
  end if;

  -- ── 5. Fichar al jugador ────────────────────────────────────────
  insert into plantillas (participante_id, jugador_id, precio_compra)
  values (v_puja.participante_id, p_jugador_id, v_puja.cantidad);

  -- ── 6. Descontar presupuesto ────────────────────────────────────
  update participantes
     set presupuesto = presupuesto - v_puja.cantidad
   where id = v_puja.participante_id;

  -- ── 7. Resolver todas las pujas del jugador en esta federación ──
  update pujas p
     set resuelta = true,
         ganadora = false
    from participantes pa
   where p.jugador_id      = p_jugador_id
     and p.participante_id = pa.id
     and pa.federacion_id  = p_federacion_id;

  -- ── 8. Marcar la puja ganadora ──────────────────────────────────
  update pujas
     set ganadora = true
   where id = p_puja_id;

  return jsonb_build_object('ok', true);
end;
$$;

-- Conceder ejecución al rol authenticated
grant execute on function resolver_puja(uuid, int, uuid) to authenticated;
