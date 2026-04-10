-- ═══════════════════════════════════════════════════════════
-- Fantasy LaLiga — Calendario de Liga
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════

-- ─── Tabla de partidos ──────────────────────────────────────
create table if not exists calendario (
  id            serial primary key,
  jornada       int not null,
  division_id   int not null references divisiones(id),
  local_id      uuid not null references participantes(id) on delete cascade,
  visitante_id  uuid not null references participantes(id) on delete cascade,
  es_neutral    boolean not null default false,
  check (local_id != visitante_id)
);
create index if not exists calendario_jornada_idx    on calendario(jornada);
create index if not exists calendario_division_idx   on calendario(division_id);
create index if not exists calendario_local_idx      on calendario(local_id);
create index if not exists calendario_visitante_idx  on calendario(visitante_id);

-- ─── Permisos ────────────────────────────────────────────────
grant select on calendario to anon;
