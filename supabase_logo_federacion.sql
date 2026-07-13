-- ═══════════════════════════════════════════════════════════════
-- FILFA — Logo de federación
--
-- 1. Ejecutar este SQL en Supabase Dashboard → SQL Editor
-- 2. Ir a Storage → New bucket → nombre: "logos-federacion"
--    Marcar como PUBLIC y guardar
-- ═══════════════════════════════════════════════════════════════

-- Columna para la URL del logo
alter table federaciones
  add column if not exists logo_url text default null;

-- Política de Storage: solo el admin de la federación puede subir/borrar
-- (aplica después de crear el bucket manualmente desde el Dashboard)
insert into storage.buckets (id, name, public)
values ('logos-federacion', 'logos-federacion', true)
on conflict (id) do nothing;

create policy "Admin sube logo federacion"
  on storage.objects for insert
  with check (
    bucket_id = 'logos-federacion'
    and auth.uid() in (select admin_user_id from federaciones)
  );

create policy "Admin borra logo federacion"
  on storage.objects for delete
  using (
    bucket_id = 'logos-federacion'
    and auth.uid() in (select admin_user_id from federaciones)
  );

create policy "Lectura publica logos federacion"
  on storage.objects for select
  using (bucket_id = 'logos-federacion');
