-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fix fichajes_pendientes: RLS + RPCs accesibles por equipos
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. RLS en fichajes_pendientes ───────────────────────────────
alter table fichajes_pendientes enable row level security;

drop policy if exists "Ver propios fichajes pendientes" on fichajes_pendientes;
create policy "Ver propios fichajes pendientes"
  on fichajes_pendientes for select
  using (
    -- El propio equipo
    participante_id in (select id from participantes where user_id = auth.uid())
    -- O el admin de la federación a la que pertenece el equipo
    or exists (
      select 1 from participantes p
        join federaciones f on f.id = p.federacion_id
       where p.id = participante_id and f.admin_user_id = auth.uid()
    )
  );

-- ─── 2. activar_fichaje_pendiente ─────────────────────────────────
-- El propio equipo O el admin pueden confirmar un fichaje pendiente.
-- Si la plantilla está llena, se libera el jugador indicado (se abona su valor al mercado).
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
  v_valor_lib numeric := 0;
begin
  -- 1. Cargar fichaje pendiente
  select * into v_pend from fichajes_pendientes where id = p_pendiente_id;
  if not found then raise exception 'fichaje_no_encontrado'; end if;

  -- 2. Verificar permiso (equipo propietario o admin de la federación)
  if not (
    v_pend.participante_id in (select id from participantes where user_id = auth.uid())
    or exists (select 1 from federaciones where id = p_federacion_id and admin_user_id = auth.uid())
  ) then raise exception 'no_autorizado'; end if;

  -- 3. Comprobar si la plantilla tiene hueco
  select count(*) into v_cnt from plantillas where participante_id = v_pend.participante_id;
  if v_cnt >= 14 then
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
    -- Recuperar el valor de mercado del jugador que sale
    select coalesce(j.valor_mercado, 0) into v_valor_lib
      from jugadores j where j.id = p_liberar_jugador_id;
    -- Liberar el jugador de la plantilla
    delete from plantillas
     where participante_id = v_pend.participante_id
       and jugador_id      = p_liberar_jugador_id;
    -- Devolver su valor al presupuesto del equipo
    update participantes
       set presupuesto = presupuesto + v_valor_lib
     where id = v_pend.participante_id;
  end if;

  -- 4. Mover el fichaje pendiente a la plantilla activa
  insert into plantillas (participante_id, jugador_id, precio_compra)
  values (v_pend.participante_id, v_pend.jugador_id, v_pend.precio_compra)
  on conflict (participante_id, jugador_id) do nothing;

  -- 5. Eliminar de pendientes
  delete from fichajes_pendientes where id = p_pendiente_id;
end;
$$;

grant execute on function activar_fichaje_pendiente(int, uuid, uuid) to authenticated;


-- ─── 3. anular_fichaje_pendiente ──────────────────────────────────
-- El propio equipo O el admin pueden anular un fichaje pendiente de mercado.
-- Devuelve el 100% del precio pagado al presupuesto.
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
  v_pend record;
begin
  -- 1. Cargar fichaje pendiente
  select * into v_pend from fichajes_pendientes where id = p_pendiente_id;
  if not found then raise exception 'fichaje_no_encontrado'; end if;

  -- 2. Verificar permiso
  if not (
    v_pend.participante_id in (select id from participantes where user_id = auth.uid())
    or exists (select 1 from federaciones where id = p_federacion_id and admin_user_id = auth.uid())
  ) then raise exception 'no_autorizado'; end if;

  -- 3. Devolver el precio completo al equipo
  update participantes
     set presupuesto = presupuesto + v_pend.precio_compra
   where id = v_pend.participante_id;

  -- 4. Eliminar el fichaje pendiente
  delete from fichajes_pendientes where id = p_pendiente_id;
end;
$$;

grant execute on function anular_fichaje_pendiente(int, uuid) to authenticated;
