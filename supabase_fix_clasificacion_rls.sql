-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fix RLS clasificacion para admin de federación
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- El admin de federación (federaciones.admin_user_id) no estaba en
-- la tabla administradores, por lo que es_admin() devolvía false
-- y todos los upserts a clasificacion fallaban silenciosamente.

drop policy if exists "Escritura solo admin clasificacion" on clasificacion;

create policy "Escritura admin federacion clasificacion"
  on clasificacion for all
  using (
    exists (
      select 1 from participantes p
      join federaciones f on f.id = p.federacion_id
      where p.id = clasificacion.participante_id
        and f.admin_user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from participantes p
      join federaciones f on f.id = p.federacion_id
      where p.id = clasificacion.participante_id
        and f.admin_user_id = auth.uid()
    )
  );
