-- ═══════════════════════════════════════════════════════════════
-- FILFA — Parche ofertas: retirar oferta propia + editar importe
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- Permitir al ofertante borrar sus propias ofertas pendientes (retirarlas)
grant delete on ofertas_jugadores to authenticated;

create policy "Retirar oferta propia"
  on ofertas_jugadores for delete
  using (
    ofertante_id in (select id from participantes where user_id = auth.uid())
    and estado = 'pendiente'
  );
