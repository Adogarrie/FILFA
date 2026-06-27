-- ═══════════════════════════════════════════════════════════
-- FILFA — Federaciones (multi-liga con código de invitación)
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════

-- ─── 1. Tabla de federaciones ───────────────────────────────
create table if not exists federaciones (
  id                  uuid primary key default uuid_generate_v4(),
  nombre              text not null,
  codigo              text not null unique,
  admin_user_id       uuid references auth.users(id) on delete set null,
  presupuesto_inicial numeric(10,2) not null default 100000000,
  jornada_actual      int not null default 1,
  sorteo_habilitado   boolean not null default false,
  created_at          timestamptz default now()
);

-- ─── 2. Ampliar participantes ────────────────────────────────
alter table participantes
  add column if not exists federacion_id uuid references federaciones(id) on delete cascade,
  add column if not exists escudo_url    text,
  add column if not exists estadio       text,
  add column if not exists entrenador    text;

create index if not exists participantes_federacion_idx on participantes(federacion_id);

-- ─── 3. Ampliar calendario ──────────────────────────────────
alter table calendario
  add column if not exists federacion_id uuid references federaciones(id) on delete cascade;

create index if not exists calendario_federacion_idx on calendario(federacion_id);

-- ─── 4. Ampliar copa ────────────────────────────────────────
alter table copa_grupos
  add column if not exists federacion_id uuid references federaciones(id) on delete cascade;

alter table copa_calendario
  add column if not exists federacion_id uuid references federaciones(id) on delete cascade;

-- ─── 5. RLS para federaciones ───────────────────────────────
alter table federaciones enable row level security;

drop policy if exists "Ver federaciones"       on federaciones;
drop policy if exists "Crear federacion"       on federaciones;
drop policy if exists "Actualizar federacion"  on federaciones;

create policy "Ver federaciones"
  on federaciones for select using (true);

create policy "Crear federacion"
  on federaciones for insert
  with check (auth.uid() = admin_user_id);

create policy "Actualizar federacion"
  on federaciones for update
  using (auth.uid() = admin_user_id);

grant select, insert, update on federaciones to authenticated;

-- ─── 6. Grants para las nuevas columnas de participantes ────
-- (Permite al cliente autenticado insertar su propio equipo con federacion_id)
grant insert (nombre, division_id, user_id, federacion_id, escudo_url, estadio, entrenador)
  on participantes to authenticated;

grant update (nombre, escudo_url, estadio, entrenador, presupuesto)
  on participantes to authenticated;

-- ─── 7. RLS: admin de federacion puede gestionar su liga ────

-- Admin puede actualizar presupuesto de cualquier equipo de su federación
drop policy if exists "Admin federacion actualiza participantes" on participantes;
create policy "Admin federacion actualiza participantes"
  on participantes for update
  using (
    federacion_id in (select id from federaciones where admin_user_id = auth.uid())
    or auth.uid() = user_id
  )
  with check (
    federacion_id in (select id from federaciones where admin_user_id = auth.uid())
    or auth.uid() = user_id
  );

-- Admin puede gestionar plantillas de cualquier equipo de su federación
drop policy if exists "Admin federacion gestiona plantillas" on plantillas;
create policy "Admin federacion gestiona plantillas"
  on plantillas for all
  using (
    participante_id in (
      select p.id from participantes p
      join federaciones f on f.id = p.federacion_id
      where f.admin_user_id = auth.uid()
    )
    or participante_id in (
      select id from participantes where user_id = auth.uid()
    )
  );

-- ─── 8. Supabase Storage ─────────────────────────────────────
-- Crear manualmente en Supabase Dashboard:
--   Storage → New bucket → nombre: "escudos" → Public: SÍ
-- Luego añadir esta política RLS al bucket:
--   Authenticated users can upload to their own path.
-- O simplemente dejar el bucket público con permisos de upload abiertos.
