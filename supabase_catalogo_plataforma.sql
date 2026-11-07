-- ═══════════════════════════════════════════════════════════════
-- FILFA — Catálogo de jugadores solo del admin de la plataforma
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- Requiere: supabase_seguridad.sql (es_admin), supabase_baja_jugador.sql,
--           supabase_anuncios_usuarios.sql (anuncios.estado).
--
-- La tabla `jugadores` es común a todas las federaciones: crear, editar,
-- dar de baja o borrar un jugador afecta a todas. Hasta ahora podía
-- escribir en ella el admin de cualquier federación; desde aquí solo el
-- admin de la plataforma (tabla administradores, es_admin()).
-- Lo que es de cada liga no cambia: lesionado (plantillas), posición en
-- la liga (jugadores_posicion_fed) y asignar un jugador libre a un equipo
-- (asignar_jugador_a_equipo).
--
--   1. RLS de jugadores: lectura para autenticados, escritura es_admin().
--   2. publicar_en_federaciones: anuncio en el Tablón de varias (o todas
--      las) federaciones, p. ej. "nuevo jugador disponible".
--   3. baja_jugador_catalogo: baja de un jugador que deja LaLiga, con
--      reembolso:
--        · plantillas → el dueño recupera el valor de mercado del jugador;
--        · fichajes pendientes → el comprador recupera lo que pagó;
--        · pujas abiertas y cesiones pendientes se borran (no hay dinero
--          reservado);
--      y un anuncio en el Tablón de cada federación afectada.
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. jugadores: escritura solo del admin de la plataforma ─────
alter table jugadores enable row level security;

-- Quita todas las políticas actuales (incluida "Admin escribe jugadores",
-- que dejaba escribir a cualquier admin de federación).
do $$
declare p record;
begin
  for p in select policyname from pg_policies where schemaname = 'public' and tablename = 'jugadores' loop
    execute format('drop policy %I on jugadores', p.policyname);
  end loop;
end $$;

create policy "Lectura jugadores"
  on jugadores for select
  using (auth.role() = 'authenticated');

create policy "Admin plataforma escribe jugadores"
  on jugadores for all
  using (es_admin())
  with check (es_admin());

-- ─── 2. publicar_en_federaciones ─────────────────────────────────
-- p_federaciones null = todas las federaciones.
create or replace function publicar_en_federaciones(
  p_texto        text,
  p_federaciones uuid[] default null,
  p_actor        text   default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_n int;
begin
  if not es_admin() then raise exception 'no_autorizado'; end if;
  insert into anuncios (federacion_id, tipo, texto, actor_nombre, estado)
  select f.id, 'admin', p_texto, p_actor, 'aprobado'
    from federaciones f
   where p_federaciones is null or f.id = any (p_federaciones);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke execute on function publicar_en_federaciones(text, uuid[], text) from public, anon;
grant  execute on function publicar_en_federaciones(text, uuid[], text) to authenticated;

-- ─── 3. baja_jugador_catalogo ────────────────────────────────────
create or replace function baja_jugador_catalogo(
  p_jugador_id uuid,
  p_actor      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_jug     record;
  v_nom     text;
  v_valor   numeric;
  r         record;
  v_reemb   int := 0;
  v_feds    uuid[] := '{}';
  fmt_m     text;
begin
  if not es_admin() then raise exception 'no_autorizado'; end if;

  select * into v_jug from jugadores where id = p_jugador_id for update;
  if not found then raise exception 'jugador_no_encontrado'; end if;
  if v_jug.baja then return jsonb_build_object('ok', true, 'ya_de_baja', true); end if;

  v_nom   := case when v_jug.posicion = 'POR' then 'Portería ' || v_jug.equipo else v_jug.nombre end;
  v_valor := coalesce(v_jug.valor_mercado, 0);

  update jugadores set baja = true where id = p_jugador_id;

  -- Plantillas: el dueño recupera el valor de mercado.
  for r in
    select pl.participante_id, pa.federacion_id, pa.nombre
      from plantillas pl join participantes pa on pa.id = pl.participante_id
     where pl.jugador_id = p_jugador_id
  loop
    update participantes set presupuesto = presupuesto + v_valor where id = r.participante_id;
    fmt_m := replace(trim(to_char(v_valor / 1000000.0, 'FM999999990.99')), '.', ',');
    if right(fmt_m, 1) = ',' then fmt_m := left(fmt_m, -1); end if;
    insert into anuncios (federacion_id, tipo, texto, actor_nombre, estado)
    values (r.federacion_id, 'admin',
            v_nom || ' (' || v_jug.equipo || ') deja LaLiga y es baja del juego. '
            || r.nombre || ' recupera su valor de mercado: ' || fmt_m || 'M.',
            p_actor, 'aprobado');
    v_reemb := v_reemb + 1;
    v_feds  := array_append(v_feds, r.federacion_id);
  end loop;
  delete from plantillas where jugador_id = p_jugador_id;

  -- Fichajes pendientes (también traspasos): el comprador recupera lo pagado.
  for r in
    select fp.participante_id, fp.precio_compra, pa.federacion_id, pa.nombre
      from fichajes_pendientes fp join participantes pa on pa.id = fp.participante_id
     where fp.jugador_id = p_jugador_id
  loop
    update participantes set presupuesto = presupuesto + r.precio_compra where id = r.participante_id;
    fmt_m := replace(trim(to_char(r.precio_compra / 1000000.0, 'FM999999990.99')), '.', ',');
    if right(fmt_m, 1) = ',' then fmt_m := left(fmt_m, -1); end if;
    insert into anuncios (federacion_id, tipo, texto, actor_nombre, estado)
    values (r.federacion_id, 'admin',
            v_nom || ' (' || v_jug.equipo || ') deja LaLiga y es baja del juego. Se anula el fichaje pendiente de '
            || r.nombre || ', que recupera ' || fmt_m || 'M.',
            p_actor, 'aprobado');
    v_reemb := v_reemb + 1;
    v_feds  := array_append(v_feds, r.federacion_id);
  end loop;
  delete from fichajes_pendientes where jugador_id = p_jugador_id;

  delete from pujas    where jugador_id = p_jugador_id and resuelta = false;
  delete from cesiones where jugador_id = p_jugador_id and estado = 'pendiente';

  return jsonb_build_object('ok', true, 'reembolsos', v_reemb,
                            'federaciones', (select coalesce(jsonb_agg(distinct f), '[]'::jsonb) from unnest(v_feds) f));
end;
$$;

revoke execute on function baja_jugador_catalogo(uuid, text) from public, anon;
grant  execute on function baja_jugador_catalogo(uuid, text) to authenticated;
