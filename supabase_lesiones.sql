-- ═══════════════════════════════════════════════════════════════
-- FILFA — Estado de lesión de jugadores
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Columna en jugadores ─────────────────────────────────────
alter table jugadores
  add column if not exists lesionado boolean not null default false;

-- ─── 2. activar_fichaje_pendiente (excluye lesionados del límite) ─
-- Sustituye la versión anterior: el límite de 14 solo cuenta jugadores no lesionados.
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
  select * into v_pend from fichajes_pendientes where id = p_pendiente_id;
  if not found then raise exception 'fichaje_no_encontrado'; end if;

  if not (
    v_pend.participante_id in (select id from participantes where user_id = auth.uid())
    or exists (select 1 from federaciones where id = p_federacion_id and admin_user_id = auth.uid())
  ) then raise exception 'no_autorizado'; end if;

  -- Contar solo jugadores NO lesionados para el límite de 14
  select count(*) into v_cnt
    from plantillas pl
    join jugadores  j on j.id = pl.jugador_id
   where pl.participante_id = v_pend.participante_id
     and not j.lesionado;

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
