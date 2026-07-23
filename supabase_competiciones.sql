-- ═══════════════════════════════════════════════════════════════
-- FILFA — Competiciones personalizadas (torneos, fases, grupos)
--
-- Estructura:
--   competiciones → fases_competicion (grupos | sueltos)
--     grupos → grupos_participantes (equipos)
--     partidos_competicion (todos los partidos, con ronda y jornada_fantasy opcional)
--
-- Resultados calculados en tiempo real desde la tabla 'clasificacion'
-- con el mismo baremo que la Liga H2H.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Competiciones ─────────────────────────────────────────────
create table if not exists competiciones (
  id                uuid primary key default gen_random_uuid(),
  federacion_id     uuid not null references federaciones(id) on delete cascade,
  nombre            text not null,
  created_by_nombre text,
  created_at        timestamptz default now()
);
alter table competiciones enable row level security;

create policy "Miembros leen competiciones" on competiciones for select
  using (
    es_admin_o_mod(federacion_id)
    or federacion_id in (select federacion_id from participantes where user_id = auth.uid())
  );
create policy "Admin crea competicion" on competiciones for insert
  with check (es_admin_o_mod(federacion_id));
create policy "Admin actualiza competicion" on competiciones for update
  using (es_admin_o_mod(federacion_id))
  with check (es_admin_o_mod(federacion_id));
create policy "Admin borra competicion" on competiciones for delete
  using (es_admin_o_mod(federacion_id));

-- ── 2. Fases de una competición ──────────────────────────────────
create table if not exists fases_competicion (
  id              uuid primary key default gen_random_uuid(),
  competicion_id  uuid not null references competiciones(id) on delete cascade,
  federacion_id   uuid not null references federaciones(id) on delete cascade,
  nombre          text not null,
  tipo            text not null check (tipo in ('grupos', 'sueltos')),
  orden           int  not null default 0
);
alter table fases_competicion enable row level security;

create policy "Miembros leen fases" on fases_competicion for select
  using (
    es_admin_o_mod(federacion_id)
    or federacion_id in (select federacion_id from participantes where user_id = auth.uid())
  );
create policy "Admin gestiona fases" on fases_competicion for all
  using (es_admin_o_mod(federacion_id))
  with check (es_admin_o_mod(federacion_id));

-- ── 3. Grupos dentro de una fase tipo 'grupos' ───────────────────
create table if not exists grupos_competicion (
  id              uuid primary key default gen_random_uuid(),
  fase_id         uuid not null references fases_competicion(id) on delete cascade,
  federacion_id   uuid not null references federaciones(id) on delete cascade,
  nombre          text not null
);
alter table grupos_competicion enable row level security;

create policy "Miembros leen grupos" on grupos_competicion for select
  using (
    es_admin_o_mod(federacion_id)
    or federacion_id in (select federacion_id from participantes where user_id = auth.uid())
  );
create policy "Admin gestiona grupos" on grupos_competicion for all
  using (es_admin_o_mod(federacion_id))
  with check (es_admin_o_mod(federacion_id));

-- ── 4. Equipos asignados a un grupo ──────────────────────────────
create table if not exists grupos_participantes (
  id              uuid primary key default gen_random_uuid(),
  grupo_id        uuid not null references grupos_competicion(id) on delete cascade,
  federacion_id   uuid not null references federaciones(id) on delete cascade,
  participante_id uuid not null references participantes(id) on delete cascade,
  unique(grupo_id, participante_id)
);
alter table grupos_participantes enable row level security;

create policy "Miembros leen miembros de grupo" on grupos_participantes for select
  using (
    es_admin_o_mod(federacion_id)
    or federacion_id in (select federacion_id from participantes where user_id = auth.uid())
  );
create policy "Admin gestiona miembros de grupo" on grupos_participantes for all
  using (es_admin_o_mod(federacion_id))
  with check (es_admin_o_mod(federacion_id));

-- ── 5. Partidos (grupos y sueltos) ───────────────────────────────
create table if not exists partidos_competicion (
  id                        uuid primary key default gen_random_uuid(),
  fase_id                   uuid not null references fases_competicion(id) on delete cascade,
  federacion_id             uuid not null references federaciones(id) on delete cascade,
  grupo_id                  uuid references grupos_competicion(id) on delete cascade,
  participante_local_id     uuid not null references participantes(id) on delete cascade,
  participante_visitante_id uuid not null references participantes(id) on delete cascade,
  jornada_fantasy           int,          -- null = TBD
  nombre                    text,         -- etiqueta libre (ej: "Semifinal")
  ronda                     int not null default 1
);
alter table partidos_competicion enable row level security;

create policy "Miembros leen partidos competicion" on partidos_competicion for select
  using (
    es_admin_o_mod(federacion_id)
    or federacion_id in (select federacion_id from participantes where user_id = auth.uid())
  );
create policy "Admin gestiona partidos competicion" on partidos_competicion for all
  using (es_admin_o_mod(federacion_id))
  with check (es_admin_o_mod(federacion_id));
