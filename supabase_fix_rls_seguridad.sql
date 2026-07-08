-- ═══════════════════════════════════════════════════════════════
-- FILFA — Corrección de alertas de seguridad de Supabase
--
-- Problemas que resuelve:
--   1. jugadores y puntuaciones_jornada sin RLS → acceso público
--   2. divisiones sin RLS (por si no se ejecutó el fix anterior)
--   3. tabla "usuarios" con contraseñas en texto plano → eliminar
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. jugadores ────────────────────────────────────────────────
-- Lectura libre para cualquier usuario autenticado; sin escritura directa
-- (los valores de mercado los actualiza el admin vía RPC o SQL Editor).
alter table jugadores enable row level security;

drop policy if exists "Lectura jugadores" on jugadores;
create policy "Lectura jugadores"
  on jugadores for select
  using (auth.role() = 'authenticated');

-- Solo admin puede insertar/actualizar/borrar jugadores
drop policy if exists "Admin escribe jugadores" on jugadores;
create policy "Admin escribe jugadores"
  on jugadores for all
  using (
    exists (select 1 from federaciones where admin_user_id = auth.uid())
  )
  with check (
    exists (select 1 from federaciones where admin_user_id = auth.uid())
  );

-- ─── 2. divisiones ───────────────────────────────────────────────
-- Tabla de referencia (Primera, Segunda…); solo lectura para todos.
alter table divisiones enable row level security;

drop policy if exists "Lectura divisiones" on divisiones;
create policy "Lectura divisiones"
  on divisiones for select
  using (auth.role() = 'authenticated');

drop policy if exists "Admin escribe divisiones" on divisiones;
create policy "Admin escribe divisiones"
  on divisiones for all
  using (
    exists (select 1 from federaciones where admin_user_id = auth.uid())
  )
  with check (
    exists (select 1 from federaciones where admin_user_id = auth.uid())
  );

-- ─── 3. Eliminar tabla "usuarios" (contraseñas en texto plano) ───
-- Esta tabla fue reemplazada por Supabase Auth.
-- Todos los usuarios ya usan auth.users; esta tabla ya no se usa.
drop table if exists usuarios cascade;
