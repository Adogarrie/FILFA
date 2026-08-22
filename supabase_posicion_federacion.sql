-- ═══════════════════════════════════════════════════════════════
-- FILFA — Posición y posición alternativa por federación
-- Problema: posicion/posicion_alt en jugadores es global y contamina
--           todas las federaciones cuando una la modifica.
-- Solución: tabla de overrides por (federacion_id, jugador_id).
--           NULL en un campo = usar el valor global de jugadores.
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

create table if not exists jugadores_posicion_fed (
  federacion_id uuid not null references federaciones(id) on delete cascade,
  jugador_id    uuid not null references jugadores(id)    on delete cascade,
  posicion      posicion_tipo default null,
  posicion_alt  posicion_tipo default null,
  primary key (federacion_id, jugador_id),
  check (
    posicion_alt is null
    or (posicion_alt <> 'POR' and (posicion is null or posicion_alt <> posicion))
  )
);

-- Permisos
grant select on jugadores_posicion_fed to anon;
grant all    on jugadores_posicion_fed to authenticated;

-- RLS
alter table jugadores_posicion_fed enable row level security;

create policy "Lectura publica posicion fed"
  on jugadores_posicion_fed for select
  using (true);

create policy "Admin escribe posicion fed"
  on jugadores_posicion_fed for all
  using  (auth.uid() in (select admin_user_id from federaciones where id = federacion_id))
  with check (auth.uid() in (select admin_user_id from federaciones where id = federacion_id));

-- ───────────────────────────────────────────────────────────────
-- MIGRACIÓN RECOMENDADA (ejecutar después de crear la tabla):
--
-- Si alguna federación había asignado posicion_alt globalmente
-- (antes de este cambio), esos valores siguen en jugadores.posicion_alt
-- y se verán en TODAS las federaciones como fallback.
--
-- Para empezar desde cero (cada federación define sus propias
-- posiciones alternativas sin heredar valores previos):
--
--   update jugadores set posicion_alt = null;
--
-- Después cada admin de cada federación re-asigna las posiciones
-- alternativas desde Admin → Jugadores.
-- ═══════════════════════════════════════════════════════════════
