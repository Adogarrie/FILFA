-- ═══════════════════════════════════════════════════════════════
-- FILFA — Mensajes de usuarios en el Tablón
--
-- Añade la columna `estado` a anuncios para permitir que los
-- usuarios envíen mensajes pendientes de aprobación del admin.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Nueva columna estado ───────────────────────────────────
alter table anuncios
  add column if not exists estado text not null default 'aprobado';

alter table anuncios
  drop constraint if exists anuncios_estado_check;

alter table anuncios
  add constraint anuncios_estado_check check (estado in ('aprobado', 'pendiente'));

-- ── 2. Actualizar política SELECT ─────────────────────────────
-- Admin ve todos; miembros solo ven los aprobados.
drop policy if exists "Ver anuncios de la federación" on anuncios;
create policy "Ver anuncios de la federación"
  on anuncios for select
  using (
    -- Admin ve todo en su federación
    federacion_id in (select id from federaciones where admin_user_id = auth.uid())
    or
    -- Miembros solo ven aprobados
    (estado = 'aprobado' and federacion_id in (
      select federacion_id from participantes where user_id = auth.uid()
    ))
  );

-- ── 3. Actualizar política INSERT ─────────────────────────────
-- Admin puede insertar cualquier tipo; miembros solo pueden
-- insertar mensajes de usuario en estado pendiente.
drop policy if exists "Insertar anuncios" on anuncios;
create policy "Insertar anuncios"
  on anuncios for insert
  with check (
    -- Admin o moderador puede insertar cualquier cosa
    federacion_id in (
      select id from federaciones where admin_user_id = auth.uid()
      union
      select m.federacion_id from moderadores m
        join participantes p on p.id = m.participante_id
        where p.user_id = auth.uid()
    )
    or
    -- Miembros pueden insertar solo mensajes de usuario pendientes
    (tipo = 'mensaje_usuario' and estado = 'pendiente' and
     federacion_id in (select federacion_id from participantes where user_id = auth.uid()))
  );

-- ── 4. Política UPDATE (aprobar/rechazar) ─────────────────────
drop policy if exists "Admin actualiza anuncios" on anuncios;
create policy "Admin actualiza anuncios"
  on anuncios for update
  using  (federacion_id in (select id from federaciones where admin_user_id = auth.uid()))
  with check (federacion_id in (select id from federaciones where admin_user_id = auth.uid()));

-- ── 5. Política DELETE (eliminar y rechazar) ──────────────────
drop policy if exists "Admin elimina anuncios" on anuncios;
create policy "Admin elimina anuncios"
  on anuncios for delete
  using (federacion_id in (select id from federaciones where admin_user_id = auth.uid()));

-- ── 6. Grants ─────────────────────────────────────────────────
grant select, insert, update, delete on anuncios to authenticated;
