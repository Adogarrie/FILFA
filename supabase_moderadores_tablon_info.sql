-- ═══════════════════════════════════════════════════════════════
-- FILFA — Permisos de moderador en Tablón e Información
--
-- Amplía las políticas RLS de anuncios y federation_info_blocks
-- para que los moderadores puedan:
--   · Aprobar/rechazar mensajes pendientes en el Tablón
--   · Publicar mensajes de admin en el Tablón
--   · Crear, editar y eliminar bloques de Información
--
-- Requiere que es_admin_o_mod() ya exista (supabase_fix_moderadores_rls.sql).
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ── 1. anuncios UPDATE (aprobar) — admin y moderador ─────────
drop policy if exists "Admin actualiza anuncios" on anuncios;
create policy "Admin o mod actualiza anuncios"
  on anuncios for update
  using  (es_admin_o_mod(federacion_id))
  with check (es_admin_o_mod(federacion_id));

-- ── 2. anuncios DELETE (rechazar/eliminar) — admin y moderador
drop policy if exists "Admin elimina anuncios" on anuncios;
create policy "Admin o mod elimina anuncios"
  on anuncios for delete
  using (es_admin_o_mod(federacion_id));

-- ── 3. anuncios INSERT — ampliar para moderadores ─────────────
-- (ya admite moderadores vía subquery; reemplazamos por es_admin_o_mod)
drop policy if exists "Insertar anuncios" on anuncios;
create policy "Insertar anuncios"
  on anuncios for insert
  with check (
    -- Admin o moderador puede insertar cualquier tipo
    es_admin_o_mod(federacion_id)
    or
    -- Miembros pueden insertar solo mensajes de usuario pendientes
    (tipo = 'mensaje_usuario' and estado = 'pendiente' and
     federacion_id in (select federacion_id from participantes where user_id = auth.uid()))
  );

-- ── 4. federation_info_blocks INSERT — admin y moderador ─────
drop policy if exists "Admin inserta info" on federation_info_blocks;
create policy "Admin o mod inserta info"
  on federation_info_blocks for insert
  with check (es_admin_o_mod(federacion_id));

-- ── 5. federation_info_blocks UPDATE — admin y moderador ─────
drop policy if exists "Admin actualiza info" on federation_info_blocks;
create policy "Admin o mod actualiza info"
  on federation_info_blocks for update
  using  (es_admin_o_mod(federacion_id))
  with check (es_admin_o_mod(federacion_id));

-- ── 6. federation_info_blocks DELETE — admin y moderador ─────
drop policy if exists "Admin elimina info" on federation_info_blocks;
create policy "Admin o mod elimina info"
  on federation_info_blocks for delete
  using (es_admin_o_mod(federacion_id));
