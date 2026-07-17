-- ═══════════════════════════════════════════════════════════════
-- FILFA — Cesiones de jugadores entre equipos
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════
-- Una cesión = solicitud de que un jugador LIBRE del mercado
-- puntúe para un equipo durante una jornada concreta.
-- El admin aprueba o rechaza cada solicitud.
-- ═══════════════════════════════════════════════════════════════

-- Borrar tabla anterior (esquema antiguo con cedente_id/cesionario_id)
drop table if exists cesiones cascade;

create table cesiones (
  id              serial      primary key,
  federacion_id   uuid        not null references federaciones(id)   on delete cascade,
  jugador_id      uuid        not null references jugadores(id)       on delete cascade,
  participante_id uuid        not null references participantes(id)   on delete cascade,
  jornada         int         not null,
  estado          text        not null default 'pendiente'
                                check (estado in ('pendiente','aprobada','rechazada')),
  created_at      timestamptz not null default now()
);

alter table cesiones enable row level security;

-- Cualquier participante de la federación puede ver todas las cesiones de su federación
drop policy if exists "Ver cesiones" on cesiones;
create policy "Ver cesiones"
  on cesiones for select
  using (
    exists (
      select 1 from participantes
       where federacion_id = cesiones.federacion_id
         and user_id = auth.uid()
    )
    or exists (
      select 1 from federaciones
       where id = cesiones.federacion_id
         and admin_user_id = auth.uid()
    )
  );

-- El propio equipo puede solicitar una cesión (estado debe ser 'pendiente')
drop policy if exists "Solicitar cesion" on cesiones;
create policy "Solicitar cesion"
  on cesiones for insert
  with check (
    participante_id in (select id from participantes where user_id = auth.uid())
    and estado = 'pendiente'
  );

-- Solo el admin puede cambiar el estado (aprobar / rechazar / revertir)
drop policy if exists "Admin aprobar cesion" on cesiones;
create policy "Admin aprobar cesion"
  on cesiones for update
  using  (exists (select 1 from federaciones where id = federacion_id and admin_user_id = auth.uid()))
  with check (exists (select 1 from federaciones where id = federacion_id and admin_user_id = auth.uid()));

-- El equipo puede cancelar sus propias solicitudes pendientes
drop policy if exists "Cancelar cesion propia" on cesiones;
create policy "Cancelar cesion propia"
  on cesiones for delete
  using (
    participante_id in (select id from participantes where user_id = auth.uid())
    and estado = 'pendiente'
  );

-- Admin puede borrar cualquier cesión
drop policy if exists "Admin borrar cesion" on cesiones;
create policy "Admin borrar cesion"
  on cesiones for delete
  using (exists (select 1 from federaciones where id = federacion_id and admin_user_id = auth.uid()));

grant all   on cesiones            to authenticated;
grant usage, select on sequence cesiones_id_seq to authenticated;

-- ─── Columna de control en federaciones ──────────────────────────
-- Default true: las cesiones están habilitadas salvo que el admin las desactive
alter table federaciones
  add column if not exists cesiones_habilitadas boolean not null default true;
