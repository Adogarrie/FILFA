-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fix permisos de mercado
--
-- El script original otorgaba insert/delete en plantillas y
-- update de presupuesto en participantes al rol `anon`, lo que
-- permitía fichar, vender y alterar presupuestos sin estar
-- autenticado. Este script lo corrige.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Revocar grants del rol anon ─────────────────────────────
revoke insert, delete                        on plantillas          from anon;
revoke usage, select                         on sequence plantillas_id_seq from anon;
revoke update (presupuesto)                  on participantes       from anon;

-- ─── 2. Conceder al rol authenticated ───────────────────────────
grant insert, delete                         on plantillas          to authenticated;
grant usage, select                          on sequence plantillas_id_seq to authenticated;
grant update (presupuesto)                   on participantes       to authenticated;

-- ─── 3. Eliminar políticas abiertas (using/with check = true) ───
drop policy if exists "Insertar plantillas anon"    on plantillas;
drop policy if exists "Borrar plantillas anon"      on plantillas;
drop policy if exists "Actualizar presupuesto anon" on participantes;

-- ─── 4. Política de INSERT en plantillas ────────────────────────
--   Permitido si el usuario autenticado es el dueño del participante
--   O es el admin de la federación de ese participante.
drop policy if exists "Insertar plantilla propia o admin" on plantillas;
create policy "Insertar plantilla propia o admin"
  on plantillas for insert
  with check (
    exists (
      select 1
      from   participantes p
      left   join federaciones f on f.id = p.federacion_id
      where  p.id = participante_id
        and  (p.user_id = auth.uid() or f.admin_user_id = auth.uid())
    )
  );

-- ─── 5. Política de DELETE en plantillas ────────────────────────
drop policy if exists "Borrar plantilla propia o admin" on plantillas;
create policy "Borrar plantilla propia o admin"
  on plantillas for delete
  using (
    exists (
      select 1
      from   participantes p
      left   join federaciones f on f.id = p.federacion_id
      where  p.id = plantillas.participante_id
        and  (p.user_id = auth.uid() or f.admin_user_id = auth.uid())
    )
  );

-- ─── 6. Política de UPDATE presupuesto en participantes ─────────
drop policy if exists "Actualizar presupuesto propio o admin" on participantes;
create policy "Actualizar presupuesto propio o admin"
  on participantes for update
  using (
    user_id = auth.uid()
    or exists (
      select 1 from federaciones
      where  id = participantes.federacion_id
        and  admin_user_id = auth.uid()
    )
  )
  with check (
    user_id = auth.uid()
    or exists (
      select 1 from federaciones
      where  id = participantes.federacion_id
        and  admin_user_id = auth.uid()
    )
  );
