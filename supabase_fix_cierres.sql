-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fix jornadas_cierre: añadir federacion_id + fix RLS
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- 1. Añadir federacion_id (los registros previos quedan con null,
--    los borramos ya que la tabla estaba vacía por el bug de RLS)
truncate table jornadas_cierre;

alter table jornadas_cierre
  drop constraint if exists jornadas_cierre_pkey;

alter table jornadas_cierre
  add column if not exists federacion_id uuid references federaciones(id) on delete cascade;

alter table jornadas_cierre
  alter column federacion_id set not null;

alter table jornadas_cierre
  add primary key (federacion_id, jornada);

-- 2. Fix RLS: reemplazar es_admin() por comprobación en federaciones
drop policy if exists "Escritura solo admin jornadas_cierre" on jornadas_cierre;
drop policy if exists "Lectura pública jornadas_cierre"     on jornadas_cierre;

create policy "Lectura pública jornadas_cierre"
  on jornadas_cierre for select using (true);

create policy "Escritura admin federación jornadas_cierre"
  on jornadas_cierre for all
  using (
    exists (
      select 1 from federaciones
      where id = jornadas_cierre.federacion_id
        and admin_user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from federaciones
      where id = jornadas_cierre.federacion_id
        and admin_user_id = auth.uid()
    )
  );
