-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fix RLS alineaciones: admins y moderadores pueden
--         guardar alineaciones de equipos sin usuario
--
-- El problema: la política existente solo permite INSERT/DELETE
-- al propietario del equipo (user_id = auth.uid()). Los equipos
-- creados por el admin sin usuario real fallan silenciosamente.
--
-- La solución: añadir políticas separadas para admin/moderador
-- sin tocar las políticas existentes de los usuarios normales.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ── INSERT ──────────────────────────────────────────────────────
-- Eliminar política de insert existente (puede que tenga otro nombre)
drop policy if exists "Admin puede insertar alineaciones" on alineaciones;
drop policy if exists "Admins insert alineaciones"        on alineaciones;

create policy "Admins insert alineaciones"
  on alineaciones for insert
  with check (
    (select federacion_id from participantes where id = participante_id)
      in (select id from federaciones where admin_user_id = auth.uid())
  );

-- ── DELETE ──────────────────────────────────────────────────────
drop policy if exists "Admin puede borrar alineaciones" on alineaciones;
drop policy if exists "Admins delete alineaciones"      on alineaciones;

create policy "Admins delete alineaciones"
  on alineaciones for delete
  using (
    (select federacion_id from participantes where id = participante_id)
      in (select id from federaciones where admin_user_id = auth.uid())
  );

-- ── UPDATE (por si acaso) ────────────────────────────────────────
drop policy if exists "Admins update alineaciones" on alineaciones;

create policy "Admins update alineaciones"
  on alineaciones for update
  using (
    (select federacion_id from participantes where id = participante_id)
      in (select id from federaciones where admin_user_id = auth.uid())
  )
  with check (
    (select federacion_id from participantes where id = participante_id)
      in (select id from federaciones where admin_user_id = auth.uid())
  );
