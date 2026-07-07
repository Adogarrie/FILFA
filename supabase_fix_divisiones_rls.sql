-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fix RLS divisiones
--
-- La política anterior permitía a cualquier usuario autenticado
-- crear, editar y borrar divisiones globalmente.
-- Ahora solo los admins de federación pueden hacerlo.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

drop policy if exists "Autenticado gestiona divisiones"      on divisiones;
drop policy if exists "Admin federacion gestiona divisiones" on divisiones;

create policy "Admin federacion gestiona divisiones"
  on divisiones for all
  using   (exists (select 1 from federaciones where admin_user_id = auth.uid()))
  with check (exists (select 1 from federaciones where admin_user_id = auth.uid()));
