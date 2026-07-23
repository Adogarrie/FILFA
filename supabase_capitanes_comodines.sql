-- ═══════════════════════════════════════════════════════════════
-- FILFA — Capitán y comodines de temporada
--
-- Dos comodines opcionales (activados por el admin):
--   · Capitán doble: los puntos del capitán cuentan x2 esa jornada
--   · Banquillo completo: los 14 jugadores suman (sin sustit. auto)
-- No se pueden usar ambos en la misma jornada.
-- El admin fija cuántas veces puede usar cada uno por equipo.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Nuevas columnas en federaciones ─────────────────────────
alter table federaciones
  add column if not exists comodin_capitan_habilitado    bool    not null default false,
  add column if not exists comodin_banquillo_habilitado   bool    not null default false,
  add column if not exists max_comodin_capitan    int,  -- null = ilimitado
  add column if not exists max_comodin_banquillo   int;  -- null = ilimitado

-- ── 2. Capitán por equipo y jornada ────────────────────────────
create table if not exists capitanes (
  id              uuid primary key default gen_random_uuid(),
  federacion_id   uuid not null references federaciones(id)   on delete cascade,
  participante_id uuid not null references participantes(id)  on delete cascade,
  jornada         int  not null,
  jugador_id      uuid references jugadores(id) on delete set null,
  created_at      timestamptz default now(),
  unique(participante_id, jornada)
);
alter table capitanes enable row level security;

create policy "Miembros leen capitanes" on capitanes for select
  using (
    es_admin_o_mod(federacion_id)
    or federacion_id in (select federacion_id from participantes where user_id = auth.uid())
  );

create policy "Propio equipo o admin inserta capitan" on capitanes for insert
  with check (
    es_admin_o_mod(federacion_id)
    or participante_id in (select id from participantes where user_id = auth.uid())
  );

create policy "Propio equipo o admin actualiza capitan" on capitanes for update
  using (
    es_admin_o_mod(federacion_id)
    or participante_id in (select id from participantes where user_id = auth.uid())
  )
  with check (
    es_admin_o_mod(federacion_id)
    or participante_id in (select id from participantes where user_id = auth.uid())
  );

create policy "Propio equipo o admin borra capitan" on capitanes for delete
  using (
    es_admin_o_mod(federacion_id)
    or participante_id in (select id from participantes where user_id = auth.uid())
  );

-- ── 3. Uso de comodines por equipo y jornada ───────────────────
create table if not exists comodines_usados (
  id              uuid primary key default gen_random_uuid(),
  federacion_id   uuid not null references federaciones(id)   on delete cascade,
  participante_id uuid not null references participantes(id)  on delete cascade,
  jornada         int  not null,
  tipo            text not null check (tipo in ('capitan', 'banquillo')),
  created_at      timestamptz default now(),
  unique(participante_id, jornada, tipo)
);
alter table comodines_usados enable row level security;

create policy "Miembros leen comodines" on comodines_usados for select
  using (
    es_admin_o_mod(federacion_id)
    or federacion_id in (select federacion_id from participantes where user_id = auth.uid())
  );

create policy "Propio equipo o admin usa comodin" on comodines_usados for insert
  with check (
    es_admin_o_mod(federacion_id)
    or participante_id in (select id from participantes where user_id = auth.uid())
  );

create policy "Propio equipo o admin cancela comodin" on comodines_usados for delete
  using (
    es_admin_o_mod(federacion_id)
    or participante_id in (select id from participantes where user_id = auth.uid())
  );
