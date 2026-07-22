-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fix RLS anuncios: miembros pueden insertar notificaciones
--
-- La política anterior solo permitía a miembros insertar
-- tipo = 'mensaje_usuario'. Esto bloqueaba silenciosamente los
-- mensajes automáticos generados por sus propias acciones
-- (fichaje, venta, alineacion, oferta, traspaso).
--
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
    (tipo in ('fichaje', 'venta', 'alineacion', 'oferta', 'traspaso')
     and federacion_id in (
       select federacion_id from participantes where user_id = auth.uid()
     ))
  );
