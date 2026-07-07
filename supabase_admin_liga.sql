-- ═══════════════════════════════════════════════════════════════
-- FILFA — Admin: gestión de divisiones y equipos
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Divisiones: RLS + permisos ──────────────────────────────
alter table divisiones enable row level security;

drop policy if exists "Ver divisiones"              on divisiones;
drop policy if exists "Autenticado gestiona divisiones" on divisiones;

create policy "Ver divisiones"
  on divisiones for select using (true);

create policy "Admin federacion gestiona divisiones"
  on divisiones for all
  using   (exists (select 1 from federaciones where admin_user_id = auth.uid()))
  with check (exists (select 1 from federaciones where admin_user_id = auth.uid()));

grant select, insert, update, delete on divisiones to authenticated;
grant usage, select on sequence divisiones_id_seq  to authenticated;

-- ─── 2. Participantes: admin puede crear equipos en su federación ─
-- (también añade presupuesto al grant si faltaba)
grant insert (nombre, division_id, user_id, federacion_id,
              escudo_url, estadio, entrenador, presupuesto)
  on participantes to authenticated;

drop policy if exists "Admin crea equipos en federacion" on participantes;
create policy "Admin crea equipos en federacion"
  on participantes for insert
  with check (
    -- Onboarding normal: el usuario crea su propio equipo
    auth.uid() = user_id
    or
    -- Admin creando equipo en su federación (user_id puede ser null)
    federacion_id in (
      select id from federaciones where admin_user_id = auth.uid()
    )
  );

-- ─── 3. Participantes: admin puede eliminar equipos de su federación ─
drop policy if exists "Admin elimina equipos de su federacion" on participantes;
create policy "Admin elimina equipos de su federacion"
  on participantes for delete
  using (
    federacion_id in (
      select id from federaciones where admin_user_id = auth.uid()
    )
    or auth.uid() = user_id
  );

grant delete on participantes to authenticated;
