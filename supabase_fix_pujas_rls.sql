-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fix RLS pujas: permitir al admin de federación resolver pujas
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- El problema: la política "Actualizar puja propia o admin" tenía:
--   with check (es_admin() OR (... AND resuelta = false AND ganadora is null))
-- Esto bloqueaba silenciosamente cualquier UPDATE que pusiera resuelta = true,
-- porque es_admin() busca en la tabla 'administradores' (no en federaciones),
-- y la alternativa exigía resuelta = false en el valor NUEVO.

drop policy if exists "Actualizar puja propia o admin" on pujas;

create policy "Actualizar puja propia o admin"
  on pujas for update
  using (
    -- Admin de la federación dueña de la puja
    exists (
      select 1 from participantes p
      join federaciones f on f.id = p.federacion_id
      where p.id = pujas.participante_id
        and f.admin_user_id = auth.uid()
    )
    -- O el propio equipo actualizando su puja
    or participante_id in (select id from participantes where user_id = auth.uid())
  )
  with check (
    -- Admin puede poner cualquier valor (incluido resuelta = true)
    exists (
      select 1 from participantes p
      join federaciones f on f.id = p.federacion_id
      where p.id = pujas.participante_id
        and f.admin_user_id = auth.uid()
    )
    -- El equipo solo puede modificar su propia puja pendiente
    or (participante_id in (select id from participantes where user_id = auth.uid())
        and resuelta = false and ganadora is null)
  );
