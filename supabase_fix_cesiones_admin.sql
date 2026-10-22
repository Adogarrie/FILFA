-- ═══════════════════════════════════════════════════════════════
-- FILFA — Cesiones: admin/mod pueden solicitar y cancelar en nombre
-- de cualquier equipo de su federación
--
-- Problema: la política "Solicitar cesion" solo deja insertar si el
-- participante es del propio usuario. Cuando el admin actúa como otro
-- equipo (selector de equipo en Mi Plantilla) y pulsa "Solicitar
-- cesión", Supabase responde "new row violates row-level security
-- policy for table cesiones". Lo mismo al cancelar la solicitud.
--
-- Solución (mismo patrón que supabase_fix_pujas_admin.sql):
--   · INSERT: equipo propio, o admin/moderador de la federación del
--     equipo. En ambos casos la cesión nace 'pendiente' y la
--     federación de la cesión debe ser la del equipo.
--   · DELETE de solicitudes pendientes: también admin/moderador.
--   · Aprobar/rechazar (UPDATE) sigue siendo solo del admin.
--
-- Requiere es_admin_o_mod (supabase_fix_moderadores_rls.sql).
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── INSERT ─────────────────────────────────────────────────────
drop policy if exists "Solicitar cesion" on cesiones;
create policy "Solicitar cesion"
  on cesiones for insert
  with check (
    estado = 'pendiente'
    and federacion_id = (select federacion_id from participantes where id = participante_id)
    and (
      -- Equipo propio
      participante_id in (select id from participantes where user_id = auth.uid())
      -- Admin o moderador de la federación del equipo
      or es_admin_o_mod(federacion_id)
    )
  );

-- ─── DELETE (cancelar solicitud pendiente) ──────────────────────
drop policy if exists "Cancelar cesion propia" on cesiones;
create policy "Cancelar cesion propia"
  on cesiones for delete
  using (
    estado = 'pendiente'
    and (
      participante_id in (select id from participantes where user_id = auth.uid())
      or es_admin_o_mod(federacion_id)
    )
  );
