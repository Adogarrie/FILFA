-- ═══════════════════════════════════════════════════════════════
-- FILFA — Inscripciones en competiciones
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Añadir columna inscripciones_habilitadas a competiciones ─
alter table competiciones
  add column if not exists inscripciones_habilitadas boolean not null default false;

-- ─── 2. Tabla competicion_inscripciones ──────────────────────────
create table if not exists competicion_inscripciones (
  id              serial primary key,
  competicion_id  int  not null references competiciones(id) on delete cascade,
  participante_id uuid not null references participantes(id) on delete cascade,
  created_at      timestamptz default now(),
  unique(competicion_id, participante_id)
);
create index if not exists comp_insc_comp_idx on competicion_inscripciones(competicion_id);

-- ─── 3. RLS ───────────────────────────────────────────────────────
alter table competicion_inscripciones enable row level security;

drop policy if exists "Ver inscripciones" on competicion_inscripciones;
create policy "Ver inscripciones"
  on competicion_inscripciones for select using (true);

-- Equipo puede inscribirse a sí mismo cuando inscripciones_habilitadas = true
drop policy if exists "Equipo se inscribe" on competicion_inscripciones;
create policy "Equipo se inscribe"
  on competicion_inscripciones for insert
  with check (
    participante_id in (select id from participantes where user_id = auth.uid())
    and competicion_id in (select id from competiciones where inscripciones_habilitadas = true)
  );

-- Equipo puede cancelar su propia inscripción
drop policy if exists "Equipo cancela inscripcion" on competicion_inscripciones;
create policy "Equipo cancela inscripcion"
  on competicion_inscripciones for delete
  using (
    participante_id in (select id from participantes where user_id = auth.uid())
    or competicion_id in (select c.id from competiciones c
      join federaciones f on f.id = c.federacion_id
      where f.admin_user_id = auth.uid())
  );

-- Admin puede gestionar inscripciones de su federación
drop policy if exists "Admin gestiona inscripciones" on competicion_inscripciones;
create policy "Admin gestiona inscripciones"
  on competicion_inscripciones for all
  using (
    competicion_id in (
      select c.id from competiciones c
      join federaciones f on f.id = c.federacion_id
      where f.admin_user_id = auth.uid()
    )
  )
  with check (
    competicion_id in (
      select c.id from competiciones c
      join federaciones f on f.id = c.federacion_id
      where f.admin_user_id = auth.uid()
    )
  );

-- ─── 4. Grants ────────────────────────────────────────────────────
grant select, insert, delete on competicion_inscripciones to authenticated;
grant usage, select on sequence competicion_inscripciones_id_seq to authenticated;
