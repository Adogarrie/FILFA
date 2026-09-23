-- ═══════════════════════════════════════════════════════════════
-- FILFA — Logros de temporada (palmarés permanente de Liga FILFA)
--
-- Insignias por umbrales de rachas/récords en Liga FILFA (h2h_partidos):
-- racha de victorias, racha invicto, victorias totales, racha marcando,
-- goles en un partido, goleada, racha de portería a cero, goles totales
-- en la temporada. Ver LOGROS_CATALOGO en index.html para el detalle.
--
-- IMPORTANTE: esta tabla NO se incluye en reiniciar_federacion()
-- (supabase_reiniciar_temporada.sql) a propósito. h2h_partidos se borra
-- en cada reinicio de temporada, pero los logros ya desbloqueados deben
-- sobrevivir como palmarés histórico permanente del equipo. Si alguna
-- vez se añade `logros` al reinicio de federación, se estaría borrando
-- ese palmarés — no hacerlo salvo que se pida explícitamente.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table federaciones
  add column if not exists logros_habilitado boolean not null default false;

create table if not exists logros (
  id               bigserial primary key,
  federacion_id    uuid not null references federaciones(id) on delete cascade,
  participante_id  uuid not null references participantes(id) on delete cascade,
  categoria        text not null,
  tier             text not null,   -- '3', '5', '10'... o 'temporada' para los logros especiales
  valor            integer,         -- valor real alcanzado en el momento del desbloqueo (informativo)
  jornada          integer,         -- jornada en la que se desbloqueó (informativo)
  unlocked_at      timestamptz not null default now(),
  unique (participante_id, categoria, tier)
);

create index if not exists logros_fed_idx on logros(federacion_id);

alter table logros enable row level security;

drop policy if exists "Ver logros de la federación" on logros;
create policy "Ver logros de la federación"
  on logros for select
  using (
    federacion_id in (
      select federacion_id from participantes where user_id = auth.uid()
      union
      select id from federaciones where admin_user_id = auth.uid()
    )
  );

-- Solo admin/moderador escriben logros — se generan automáticamente al
-- guardar resultados de Liga FILFA (o al pulsar "Recalcular logros") en
-- AdminLigaH2H, nunca por acción directa de un usuario normal.
drop policy if exists "Admin o mod inserta logros" on logros;
create policy "Admin o mod inserta logros"
  on logros for insert
  with check ( es_admin_o_mod(federacion_id) );

grant select, insert on logros to authenticated;
grant usage, select on sequence logros_id_seq to authenticated;
