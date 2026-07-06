-- ═══════════════════════════════════════════════════════════
-- Fantasy LaLiga — Copa de la Liga
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════

-- ─── Grupos de la Copa ──────────────────────────────────────
create table if not exists copa_grupos (
  id              serial primary key,
  grupo           text not null,          -- 'A', 'B', 'C'…
  participante_id uuid not null references participantes(id) on delete cascade,
  unique (grupo, participante_id)
);
create index if not exists copa_grupos_grupo_idx on copa_grupos(grupo);

-- ─── Calendario de Copa ─────────────────────────────────────
create table if not exists copa_calendario (
  id            serial primary key,
  jornada       int not null,
  grupo         text not null,
  local_id      uuid not null references participantes(id) on delete cascade,
  visitante_id  uuid not null references participantes(id) on delete cascade,
  es_neutral    boolean not null default false,
  check (local_id != visitante_id)
);
create index if not exists copa_cal_jornada_idx on copa_calendario(jornada);
create index if not exists copa_cal_grupo_idx   on copa_calendario(grupo);

-- ─── Permisos ────────────────────────────────────────────────
grant select on copa_grupos     to anon;
grant select on copa_calendario to anon;

-- Admin puede insertar/borrar
grant insert, delete on copa_grupos              to anon;
grant insert, delete on copa_calendario          to anon;
grant usage, select  on sequence copa_grupos_id_seq     to anon;
grant usage, select  on sequence copa_calendario_id_seq to anon;
