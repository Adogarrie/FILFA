-- ═══════════════════════════════════════════════════════════
-- Fantasy LaLiga — Usuarios y permisos de administración
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════

-- ─── Tabla de usuarios ──────────────────────────────────────
create table if not exists usuarios (
  id              serial primary key,
  username        text not null unique,
  password        text not null,
  participante_id uuid references participantes(id) on delete set null,
  is_admin        boolean not null default false
);

-- El cliente web puede leer usuarios (para validar login)
grant select on usuarios to anon;

-- ─── Permisos para escribir clasificación (tab Puntos/Admin) ─
grant insert, update on clasificacion to anon;

-- ─── Permisos para gestionar calendario desde la app ─────────
grant insert, delete on calendario to anon;
grant usage, select on sequence calendario_id_seq to anon;
