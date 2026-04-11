-- ═══════════════════════════════════════════════════════════════
-- FILFA — Tablas de Alineaciones y Cierres de Jornada
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- Alineaciones: titulares y suplentes por equipo y jornada
create table if not exists alineaciones (
  id              serial primary key,
  participante_id uuid references participantes(id) on delete cascade,
  jornada         int not null,
  jugador_id      uuid references jugadores(id) on delete cascade,
  es_titular      boolean not null default true,
  unique (participante_id, jornada, jugador_id)
);

-- Cierre de jornada: hora límite para modificar alineaciones
create table if not exists jornadas_cierre (
  jornada  int primary key,
  cierre   timestamptz not null
);

-- ─── Permisos ────────────────────────────────────────────────
grant select, insert, update, delete on alineaciones   to anon;
grant select, insert, update, delete on jornadas_cierre to anon;

-- RLS
alter table alineaciones    enable row level security;
alter table jornadas_cierre enable row level security;

drop policy if exists "Lectura pública alineaciones"    on alineaciones;
drop policy if exists "Escritura libre alineaciones"   on alineaciones;
drop policy if exists "Lectura pública jornadas_cierre" on jornadas_cierre;
drop policy if exists "Escritura libre jornadas_cierre" on jornadas_cierre;

create policy "Lectura pública alineaciones"
  on alineaciones for select using (true);

create policy "Escritura libre alineaciones"
  on alineaciones for all using (true) with check (true);

create policy "Lectura pública jornadas_cierre"
  on jornadas_cierre for select using (true);

create policy "Escritura libre jornadas_cierre"
  on jornadas_cierre for all using (true) with check (true);
