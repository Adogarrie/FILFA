-- ═══════════════════════════════════════════════════════════════
-- FILFA — Bloques de información de federación
--
-- Permite al admin publicar texto, enlaces e imágenes fijos
-- visibles para todos los miembros de la federación.
-- Los bloques se muestran ordenados según el campo `orden`.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

create table if not exists federation_info_blocks (
  id            uuid        primary key default gen_random_uuid(),
  federacion_id uuid        not null references federaciones(id) on delete cascade,
  tipo          text        not null check (tipo in ('texto', 'enlace', 'imagen')),
  titulo        text,
  contenido     text,
  url           text,
  orden         int         not null default 0,
  created_at    timestamptz not null default now()
);

alter table federation_info_blocks enable row level security;

-- Miembros y admin pueden leer los bloques de su federación
create policy "Ver info de la federacion"
  on federation_info_blocks for select
  using (
    federacion_id in (
      select id            from federaciones  where admin_user_id = auth.uid()
      union
      select federacion_id from participantes where user_id       = auth.uid()
    )
  );

-- Solo el admin puede crear, editar y borrar
create policy "Admin inserta info"
  on federation_info_blocks for insert
  with check (
    federacion_id in (select id from federaciones where admin_user_id = auth.uid())
  );

create policy "Admin actualiza info"
  on federation_info_blocks for update
  using (
    federacion_id in (select id from federaciones where admin_user_id = auth.uid())
  )
  with check (
    federacion_id in (select id from federaciones where admin_user_id = auth.uid())
  );

create policy "Admin elimina info"
  on federation_info_blocks for delete
  using (
    federacion_id in (select id from federaciones where admin_user_id = auth.uid())
  );

grant select, insert, update, delete on federation_info_blocks to authenticated;
