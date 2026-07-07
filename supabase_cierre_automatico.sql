-- ═══════════════════════════════════════════════════════════════
-- FILFA — Cierre automático diario de pujas
--
-- Flujo:
--   · Admin configura hora_cierre_pujas en la federación (HH:MM).
--   · Cada día a esa hora, la primera carga de Mercado llama a
--     procesar_cierre_pujas().  El ganador de cada jugador es el
--     que más dinero pujó (desempate: puja más antigua).
--   · El cierre es idempotente: una segunda llamada en el mismo
--     día devuelve 'ya_procesado' sin hacer nada.
--   · Zona horaria: Europe/Madrid.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Columnas ────────────────────────────────────────────────
alter table federaciones
  add column if not exists hora_cierre_pujas time default null;

-- created_at en pujas (necesario para el filtro de cierre)
alter table pujas
  add column if not exists created_at timestamptz default now();
-- Actualizar filas existentes que puedan tener NULL
update pujas set created_at = now() where created_at is null;

-- ─── 2. Tabla de registro de cierres ────────────────────────────
create table if not exists log_cierres_pujas (
  id            serial primary key,
  federacion_id uuid not null references federaciones(id) on delete cascade,
  fecha_cierre  date not null,
  procesado_en  timestamptz not null default now(),
  firmados      int not null default 0,
  unique(federacion_id, fecha_cierre)
);

alter table log_cierres_pujas enable row level security;

grant select on log_cierres_pujas to authenticated;

drop policy if exists "Ver log cierres" on log_cierres_pujas;
create policy "Ver log cierres"
  on log_cierres_pujas for select using (true);

-- ─── 3. Función principal ────────────────────────────────────────
-- Procesa el cierre pendiente más reciente para una federación.
-- Devuelve:
--   { ok: true, skipped: true, reason: '...' }  — nada que hacer
--   { ok: true, fecha: '...', firmados: N }      — cierre procesado
create or replace function procesar_cierre_pujas(p_federacion_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hora      time;
  v_fecha     date;
  v_ts        timestamptz;
  v_jug_id    uuid;
  v_ganadora  record;
  v_pres      numeric;
  v_pos       text;
  v_equipo    text;
  v_jug_nom   text;
  v_eq_nom    text;
  v_div       int;
  v_cnt       int;
  v_pendiente boolean;
  v_firmados  int := 0;
begin
  -- ── Obtener hora de cierre (requiere mercado activo) ──────────
  select hora_cierre_pujas into v_hora
    from federaciones
   where id = p_federacion_id
     and ventas_habilitadas = true;

  if v_hora is null then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'sin_hora_o_mercado_cerrado');
  end if;

  -- ── Determinar fecha/hora del último cierre ────────────────────
  v_fecha := (now() at time zone 'Europe/Madrid')::date;
  v_ts    := (v_fecha::text || ' ' || v_hora::text)::timestamp
               at time zone 'Europe/Madrid';

  -- Si el cierre de hoy aún no ha llegado, miramos el de ayer
  if now() < v_ts then
    v_fecha := v_fecha - 1;
    v_ts    := ((v_fecha::text) || ' ' || v_hora::text)::timestamp
                 at time zone 'Europe/Madrid';
  end if;

  -- Si tampoco ha llegado el de ayer (ej. recién instalado), salir
  if now() < v_ts then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'sin_cierre_pendiente');
  end if;

  -- ── Comprobación rápida (sin lock) ────────────────────────────
  if exists (
    select 1 from log_cierres_pujas
    where federacion_id = p_federacion_id and fecha_cierre = v_fecha
  ) then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'ya_procesado');
  end if;

  -- ── Adquirir lock de la federación (serializa llamadas concurrentes)
  perform id from federaciones where id = p_federacion_id for update;

  -- Recomprobar tras el lock
  if exists (
    select 1 from log_cierres_pujas
    where federacion_id = p_federacion_id and fecha_cierre = v_fecha
  ) then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'ya_procesado');
  end if;

  -- ── Procesar cada jugador con pujas anteriores al cierre ───────
  for v_jug_id in
    select distinct p.jugador_id
      from pujas p
      join participantes pa on pa.id = p.participante_id
     where pa.federacion_id = p_federacion_id
       and p.resuelta       = false
       and (p.created_at is null or p.created_at <= v_ts)
  loop
    begin
      -- Puja ganadora: mayor cantidad, más antigua en caso de empate
      select p.* into v_ganadora
        from pujas p
        join participantes pa on pa.id = p.participante_id
       where p.jugador_id      = v_jug_id
         and pa.federacion_id  = p_federacion_id
         and p.resuelta        = false
         and (p.created_at is null or p.created_at <= v_ts)
       order by p.cantidad desc, p.created_at asc
       limit 1
       for update;

      if not found then continue; end if;

      -- Presupuesto
      select presupuesto, nombre into v_pres, v_eq_nom
        from participantes where id = v_ganadora.participante_id;
      if v_pres < v_ganadora.cantidad then continue; end if;

      -- Datos del jugador
      select posicion, equipo, nombre into v_pos, v_equipo, v_jug_nom
        from jugadores where id = v_jug_id;

      -- Portería única por división (plantilla activa + pendientes)
      if v_pos = 'POR' then
        select division_id into v_div
          from participantes where id = v_ganadora.participante_id;
        if exists (
          select 1 from plantillas pl
          join participantes pa on pa.id = pl.participante_id
          join jugadores     ju on ju.id = pl.jugador_id
          where ju.posicion      = 'POR'
            and ju.equipo        = v_equipo
            and pa.division_id   = v_div
            and pa.federacion_id = p_federacion_id
        ) or exists (
          select 1 from fichajes_pendientes fp
          join participantes pa on pa.id = fp.participante_id
          join jugadores     ju on ju.id = fp.jugador_id
          where ju.posicion      = 'POR'
            and ju.equipo        = v_equipo
            and pa.division_id   = v_div
            and pa.federacion_id = p_federacion_id
        ) then continue; end if;
      end if;

      -- Plaza libre o fichaje pendiente
      select count(*) into v_cnt
        from plantillas where participante_id = v_ganadora.participante_id;
      v_pendiente := v_cnt >= 14;

      if v_pendiente then
        if exists (
          select 1 from fichajes_pendientes
          where participante_id = v_ganadora.participante_id and jugador_id = v_jug_id
        ) then continue; end if;
        insert into fichajes_pendientes (participante_id, jugador_id, precio_compra)
        values (v_ganadora.participante_id, v_jug_id, v_ganadora.cantidad);
      else
        insert into plantillas (participante_id, jugador_id, precio_compra)
        values (v_ganadora.participante_id, v_jug_id, v_ganadora.cantidad);
      end if;

      -- Descontar presupuesto
      update participantes
         set presupuesto = presupuesto - v_ganadora.cantidad
       where id = v_ganadora.participante_id;

      -- Resolver todas las pujas del jugador en esta federación
      update pujas p set resuelta = true, ganadora = false
        from participantes pa
       where p.jugador_id     = v_jug_id
         and p.participante_id = pa.id
         and pa.federacion_id  = p_federacion_id;

      -- Marcar ganadora
      update pujas set ganadora = true where id = v_ganadora.id;

      -- Tablón: anuncio individual
      insert into anuncios (federacion_id, tipo, texto)
      values (
        p_federacion_id,
        'fichaje',
        v_eq_nom
          || case when v_pos = 'POR'
                  then ' ficha la Portería de ' || v_equipo
                  else ' ficha a ' || v_jug_nom || ' (' || v_equipo || ')'
             end
          || ' por ' || to_char(v_ganadora.cantidad, 'FM999G999G999') || ' €'
          || case when v_pendiente then ' — pendiente de plaza' else '' end
      );

      v_firmados := v_firmados + 1;

    exception when others then
      null;  -- saltar jugador con error; continúa el lote
    end;
  end loop;

  -- ── Registrar cierre ─────────────────────────────────────────
  insert into log_cierres_pujas (federacion_id, fecha_cierre, firmados)
  values (p_federacion_id, v_fecha, v_firmados)
  on conflict (federacion_id, fecha_cierre) do nothing;

  -- Tablón: resumen del cierre
  insert into anuncios (federacion_id, tipo, texto)
  values (
    p_federacion_id,
    'admin',
    '⏰ Cierre de pujas ' || to_char(v_fecha, 'DD/MM/YYYY') || ' a las '
    || to_char(v_hora, 'HH24:MI') || 'h — '
    || case when v_firmados > 0
            then v_firmados || ' jugador(es) fichado(s)'
            else 'sin fichajes (nadie pujó o presupuesto insuficiente)'
       end
  );

  return jsonb_build_object('ok', true, 'fecha', v_fecha::text, 'firmados', v_firmados);
end;
$$;

grant execute on function procesar_cierre_pujas(uuid) to authenticated;
