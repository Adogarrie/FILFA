-- ═══════════════════════════════════════════════════════════════
-- FILFA — Moderadores
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

create table if not exists moderadores (
  id              serial primary key,
  federacion_id   uuid not null references federaciones(id) on delete cascade,
  participante_id uuid not null references participantes(id) on delete cascade,
  created_at      timestamptz default now(),
  unique(federacion_id, participante_id)
);
create index if not exists moderadores_fed_idx on moderadores(federacion_id);

alter table moderadores enable row level security;

drop policy if exists "Ver moderadores" on moderadores;
create policy "Ver moderadores" on moderadores for select using (true);

drop policy if exists "Admin gestiona moderadores" on moderadores;
create policy "Admin gestiona moderadores" on moderadores for all
  using   (federacion_id in (select id from federaciones where admin_user_id = auth.uid()))
  with check (federacion_id in (select id from federaciones where admin_user_id = auth.uid()));

grant select, insert, delete on moderadores to authenticated;
grant usage, select on sequence moderadores_id_seq to authenticated;
