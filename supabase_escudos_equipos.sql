-- ═══════════════════════════════════════════════════════════════
-- FILFA — Escudos de equipos (participantes)
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- Pasos previos (Storage):
--   1. Dashboard → Storage → Create bucket
--      Name: escudos-participantes   Public: YES
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Columna escudo_url en participantes ───────────────────────
alter table participantes
  add column if not exists escudo_url text default null;

-- ─── 2. RLS: equipo actualiza su propio escudo_url ───────────────
-- (El admin ya puede actualizar cualquier fila por ser admin_user_id.)
drop policy if exists "Actualizar propio escudo" on participantes;

create policy "Actualizar propio escudo"
  on participantes for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ─── 3. Storage RLS — bucket escudos-participantes ───────────────
-- SELECT (lectura pública — el bucket ya es Public, pero por si acaso)
drop policy if exists "Leer escudos equipos" on storage.objects;
create policy "Leer escudos equipos"
  on storage.objects for select
  using (bucket_id = 'escudos-participantes');

-- INSERT / UPDATE: solo el propio equipo (la carpeta coincide con su participante_id)
-- La ruta esperada es: <participante_id>/<timestamp>.<ext>
drop policy if exists "Subir propio escudo" on storage.objects;
create policy "Subir propio escudo"
  on storage.objects for insert
  with check (
    bucket_id = 'escudos-participantes'
    and (
      -- El primer segmento del path es el participante_id del usuario
      (storage.foldername(name))[1] in (
        select id::text from participantes where user_id = auth.uid()
      )
      -- O es admin de alguna federación que contiene ese equipo
      or exists (
        select 1 from federaciones f
          join participantes p on p.federacion_id = f.id
         where f.admin_user_id = auth.uid()
           and p.id::text = (storage.foldername(name))[1]
      )
    )
  );

drop policy if exists "Actualizar propio escudo storage" on storage.objects;
create policy "Actualizar propio escudo storage"
  on storage.objects for update
  using (
    bucket_id = 'escudos-participantes'
    and (
      (storage.foldername(name))[1] in (
        select id::text from participantes where user_id = auth.uid()
      )
      or exists (
        select 1 from federaciones f
          join participantes p on p.federacion_id = f.id
         where f.admin_user_id = auth.uid()
           and p.id::text = (storage.foldername(name))[1]
      )
    )
  );

drop policy if exists "Eliminar propio escudo storage" on storage.objects;
create policy "Eliminar propio escudo storage"
  on storage.objects for delete
  using (
    bucket_id = 'escudos-participantes'
    and (
      (storage.foldername(name))[1] in (
        select id::text from participantes where user_id = auth.uid()
      )
      or exists (
        select 1 from federaciones f
          join participantes p on p.federacion_id = f.id
         where f.admin_user_id = auth.uid()
           and p.id::text = (storage.foldername(name))[1]
      )
    )
  );
