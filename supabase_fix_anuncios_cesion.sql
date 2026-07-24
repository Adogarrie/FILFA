-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fix RLS anuncios: miembros pueden publicar solicitudes de cesión
--
-- Añade 'cesion' a los tipos que los miembros pueden insertar
-- directamente. Se usa para el mensaje automático que aparece
-- en el tablón cuando un usuario solicita una cesión.
--
-- Ejecutar DESPUÉS de supabase_fix_anuncios_perfil.sql
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

drop policy if exists "Insertar anuncios" on anuncios;

create policy "Insertar anuncios"
  on anuncios for insert
  with check (
    -- Admin o moderador: puede insertar cualquier tipo
    es_admin_o_mod(federacion_id)
    or
    -- Miembros: mensajes de usuario, pendientes de aprobación
    (tipo = 'mensaje_usuario'
     and estado = 'pendiente'
     and federacion_id in (
       select federacion_id from participantes where user_id = auth.uid()
     ))
    or
    -- Miembros: notificaciones automáticas de sus propias acciones
    (tipo in ('fichaje', 'venta', 'alineacion', 'oferta', 'traspaso', 'nuevo_miembro', 'perfil', 'cesion')
     and federacion_id in (
       select federacion_id from participantes where user_id = auth.uid()
     ))
  );
