-- ═══════════════════════════════════════════════════════════════
-- FILFA — Estado de lesión de jugadores (por federación)
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Columnas ─────────────────────────────────────────────────
alter table jugadores
  add column if not exists lesionado boolean not null default false;

-- Contador de sustituciones por lesión disponibles (se incrementa al vender un
-- jugador lesionado con mercado cerrado; se decrementa al fichar el sustituto).
alter table participantes
  add column if not exists sustituciones_lesion int not null default 0;

-- Estado de lesión per-equipo (= per-federación: un jugador solo está en un
-- equipo por federación). Sustituye al flag global de jugadores.lesionado.
alter table plantillas
  add column if not exists lesionado boolean not null default false;

-- Migración: copiar estado existente de jugadores.lesionado → plantillas.lesionado
update plantillas pl
   set lesionado = true
  from jugadores j
 where j.id = pl.jugador_id
   and j.lesionado = true;

-- ─── 2. activar_fichaje_pendiente (excluye lesionados del límite) ─
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
  v_pend      record;
  v_cnt       int;
  v_max_jug   int;
  v_valor_lib numeric := 0;
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
    if not exists (
      select 1 from plantillas
       where participante_id = v_pend.participante_id
         and jugador_id = p_liberar_jugador_id
    ) then
      raise exception 'jugador_a_liberar_no_encontrado';
    end if;
    select coalesce(j.valor_mercado, 0) into v_valor_lib
      from jugadores j where j.id = p_liberar_jugador_id;
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

-- ─── 3. marcar_lesionado ─────────────────────────────────────────
-- Marca/desmarca un jugador como lesionado en la plantilla de esta federación.
-- Si el jugador se recupera y la plantilla queda llena, pasa a fichajes_pendientes.
drop function if exists marcar_lesionado(uuid, boolean, uuid);

create function marcar_lesionado(
  p_jugador_id    uuid,
  p_nuevo_estado  boolean,
  p_federacion_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_participante_id uuid;
  v_cnt             int;
  v_max             int;
  v_precio          numeric;
begin
  if not exists (
    select 1 from federaciones
     where id = p_federacion_id and admin_user_id = auth.uid()
  ) then
    raise exception 'no_autorizado';
  end if;

  update plantillas pl
     set lesionado = p_nuevo_estado
    from participantes pa
   where pl.participante_id = pa.id
     and pa.federacion_id   = p_federacion_id
     and pl.jugador_id      = p_jugador_id;

  if not found then
    return jsonb_build_object('ok', true, 'en_plantilla', false);
  end if;

  -- Si se recupera (lesionado → sano), comprobar si la plantilla queda llena
  if not p_nuevo_estado then
    select pa.id into v_participante_id
      from plantillas pl
      join participantes pa on pa.id = pl.participante_id
     where pl.jugador_id    = p_jugador_id
       and pa.federacion_id = p_federacion_id;

    if found then
      v_max := get_max_jugadores(p_federacion_id);

      select count(*) into v_cnt
        from plantillas
       where participante_id = v_participante_id
         and not lesionado;

      if v_cnt > v_max then
        select precio_compra into v_precio
          from plantillas
         where participante_id = v_participante_id
           and jugador_id      = p_jugador_id;

        insert into fichajes_pendientes (participante_id, jugador_id, precio_compra)
        values (v_participante_id, p_jugador_id, v_precio)
        on conflict (participante_id, jugador_id) do nothing;

        delete from plantillas
         where participante_id = v_participante_id
           and jugador_id      = p_jugador_id;

        return jsonb_build_object('ok', true, 'en_plantilla', true, 'pendiente', true);
      end if;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'en_plantilla', true, 'pendiente', false);
end;
$$;

grant execute on function marcar_lesionado(uuid, boolean, uuid) to authenticated;
