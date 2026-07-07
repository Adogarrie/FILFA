-- ═══════════════════════════════════════════════════════════════
-- FILFA — Pujas: cerrar RLS + permitir admin/mod gestionar pujas
--
-- Problema actual: la política "Escritura libre pujas" es
--   for all using(true) with check(true)
-- Cualquier usuario autenticado puede insertar/borrar pujas de
-- cualquier equipo, o incluso sin autenticar (grant a anon).
--
-- Solución:
--   · Revocar INSERT/DELETE de anon, mantener en authenticated.
--   · Reemplazar la política abierta con políticas acotadas.
--   · Admin y moderador pueden gestionar pujas de cualquier equipo
--     de su federación (necesario para la nueva UI de admin).
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Permisos de rol ─────────────────────────────────────────
revoke insert, update, delete on pujas from anon;

-- ─── 2. Borrar política abierta ─────────────────────────────────
drop policy if exists "Escritura libre pujas" on pujas;

-- ─── 3. INSERT ──────────────────────────────────────────────────
-- Equipo propio O admin/mod de la federación del equipo objetivo.
drop policy if exists "Insertar puja propia o admin" on pujas;
create policy "Insertar puja propia o admin"
  on pujas for insert
  with check (
    -- Equipo propio
    participante_id in (select id from participantes where user_id = auth.uid())
    -- Admin o moderador de la federación a la que pertenece el participante
    or es_admin_o_mod(
         (select federacion_id from participantes where id = participante_id)
       )
  );

-- ─── 4. UPDATE ──────────────────────────────────────────────────
-- Reemplazamos la política de fix_pujas_rls.sql añadiendo moderadores.
drop policy if exists "Actualizar puja propia o admin" on pujas;
create policy "Actualizar puja propia o admin"
  on pujas for update
  using (
    participante_id in (select id from participantes where user_id = auth.uid())
    or es_admin_o_mod(
         (select federacion_id from participantes where id = participante_id)
       )
  )
  with check (
    -- Admin/mod puede cambiar cualquier campo (incluido resuelta = true)
    es_admin_o_mod(
      (select federacion_id from participantes where id = participante_id)
    )
    -- El equipo solo puede modificar su propia puja mientras esté pendiente
    or (
      participante_id in (select id from participantes where user_id = auth.uid())
      and resuelta = false
      and ganadora is null
    )
  );

-- ─── 5. DELETE ──────────────────────────────────────────────────
drop policy if exists "Borrar puja propia o admin" on pujas;
create policy "Borrar puja propia o admin"
  on pujas for delete
  using (
    participante_id in (select id from participantes where user_id = auth.uid())
    or es_admin_o_mod(
         (select federacion_id from participantes where id = participante_id)
       )
  );
