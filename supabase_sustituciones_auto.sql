-- ═══════════════════════════════════════════════════════════════
-- FILFA — Sustituciones automáticas por jugadores con 0 minutos
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════
-- Flujo:
--   1. Admin marca en jornada_no_jugo los jugadores que jugaron 0'
--   2. La app calcula sustituciones y guarda en sustituciones_auto
--   3. Los puntos de equipo se recalculan usando la alineación efectiva
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Jugadores que no jugaron (0 minutos) por jornada ─────────
-- Es un dato global de la competición real, no por equipo.
-- El admin lo introduce una vez y afecta a todos los equipos fantasy.

create table if not exists jornada_no_jugo (
  id            serial      primary key,
  federacion_id uuid        not null references federaciones(id) on delete cascade,
  jugador_id    uuid        not null references jugadores(id)    on delete cascade,
  jornada       int         not null,
  created_at    timestamptz not null default now(),
  unique (federacion_id, jugador_id, jornada)
);

alter table jornada_no_jugo enable row level security;

-- Admin puede leer/escribir/borrar
drop policy if exists "Admin gestiona no_jugo" on jornada_no_jugo;
create policy "Admin gestiona no_jugo"
  on jornada_no_jugo for all
  using  (exists (select 1 from federaciones where id = federacion_id and admin_user_id = auth.uid()))
  with check (exists (select 1 from federaciones where id = federacion_id and admin_user_id = auth.uid()));

-- Participantes pueden leer (para mostrar badges en la UI)
drop policy if exists "Participantes ven no_jugo" on jornada_no_jugo;
create policy "Participantes ven no_jugo"
  on jornada_no_jugo for select
  using (
    exists (
      select 1 from participantes
       where federacion_id = jornada_no_jugo.federacion_id
         and user_id = auth.uid()
    )
  );

grant all on jornada_no_jugo to authenticated;
grant usage, select on sequence jornada_no_jugo_id_seq to authenticated;

-- ─── 2. Sustituciones automáticas calculadas ─────────────────────
-- Generadas por la app al guardar jornada_no_jugo.
-- Una fila por cada titular sustituido.

create table if not exists sustituciones_auto (
  id               serial      primary key,
  federacion_id    uuid        not null references federaciones(id)   on delete cascade,
  participante_id  uuid        not null references participantes(id)  on delete cascade,
  jornada          int         not null,
  jugador_sale_id  uuid        not null references jugadores(id)      on delete cascade,
  jugador_entra_id uuid        not null references jugadores(id)      on delete cascade,
  created_at       timestamptz not null default now(),
  unique (federacion_id, participante_id, jornada, jugador_sale_id)
);

alter table sustituciones_auto enable row level security;

-- Admin puede gestionar todas
drop policy if exists "Admin gestiona sustituciones_auto" on sustituciones_auto;
create policy "Admin gestiona sustituciones_auto"
  on sustituciones_auto for all
  using  (exists (select 1 from federaciones where id = federacion_id and admin_user_id = auth.uid()))
  with check (exists (select 1 from federaciones where id = federacion_id and admin_user_id = auth.uid()));

-- Participantes pueden leer las suyas
drop policy if exists "Participantes ven sus sustituciones_auto" on sustituciones_auto;
create policy "Participantes ven sus sustituciones_auto"
  on sustituciones_auto for select
  using (
    participante_id in (select id from participantes where user_id = auth.uid())
    or exists (
      select 1 from participantes
       where federacion_id = sustituciones_auto.federacion_id
         and user_id = auth.uid()
    )
  );

grant all on sustituciones_auto to authenticated;
grant usage, select on sequence sustituciones_auto_id_seq to authenticated;
