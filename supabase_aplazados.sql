-- ═══════════════════════════════════════════════════════════════
-- FILFA — Gestión de jugadores con partido aplazado
--
-- Permite al admin/moderador marcar jugadores como "aplazados"
-- en una jornada concreta. Los usuarios podrán editar las
-- posiciones de esos jugadores aunque la alineación esté cerrada,
-- hasta que el admin quite el marcado (al introducir sus puntos).
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

create table if not exists jugadores_aplazados (
  id            uuid primary key default gen_random_uuid(),
  federacion_id uuid not null references federaciones(id) on delete cascade,
  jornada       int  not null,
  jugador_id    uuid not null references jugadores(id)    on delete cascade,
  created_at    timestamptz default now(),
  unique(federacion_id, jornada, jugador_id)
);

alter table jugadores_aplazados enable row level security;

-- Lectura: cualquier miembro de la federación
create policy "Miembros leen aplazados"
  on jugadores_aplazados for select
  using (
    es_admin_o_mod(federacion_id)
    or federacion_id in (
      select federacion_id from participantes where user_id = auth.uid()
    )
  );

-- Escritura: admin o moderador de la federación
create policy "Admin/mod gestionan aplazados"
  on jugadores_aplazados for insert
  with check (es_admin_o_mod(federacion_id));

create policy "Admin/mod eliminan aplazados"
  on jugadores_aplazados for delete
  using (es_admin_o_mod(federacion_id));
