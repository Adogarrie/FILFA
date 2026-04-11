-- ═══════════════════════════════════════════════════════════════
-- FILFA — Sistema de pujas
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

create table if not exists pujas (
  id              serial primary key,
  participante_id uuid references participantes(id) on delete cascade,
  jugador_id      uuid references jugadores(id) on delete cascade,
  cantidad        numeric(12,2) not null,
  created_at      timestamptz default now(),
  resuelta        boolean not null default false,
  ganadora        boolean,                          -- null=pendiente, true=ganó, false=perdió
  unique (participante_id, jugador_id)             -- 1 puja por equipo por jugador
);

grant select, insert, update, delete on pujas to anon;
grant usage, select on sequence pujas_id_seq to anon;

alter table pujas enable row level security;

drop policy if exists "Lectura pública pujas" on pujas;
drop policy if exists "Escritura libre pujas" on pujas;

create policy "Lectura pública pujas"
  on pujas for select using (true);

create policy "Escritura libre pujas"
  on pujas for all using (true) with check (true);
