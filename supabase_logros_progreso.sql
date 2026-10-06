-- ═══════════════════════════════════════════════════════════════
-- FILFA — Progreso de logros precalculado
--
-- La pestaña 🏆 Logros mostraba el progreso hacia el siguiente tramo de
-- cada logro calculándolo en el navegador de cada usuario, lo que obligaba
-- a descargar todo el histórico de la temporada (~1-2 MB por visita).
--
-- Ahora el progreso lo calcula el admin/moderador en recalcularLogros()
-- (AdminLigaH2H en index.html), que ya descarga ese histórico al calcular
-- cada jornada H2H o guardar resultados, y lo guarda aquí: una fila por
-- equipo con { categoria: valor } en `datos`. Los usuarios solo leen esta
-- tabla (unas pocas KB).
--
-- El progreso refleja el estado del último recálculo (no es en tiempo
-- real): los logros de plantilla (nacionalidad, edad) no se actualizan con
-- cada fichaje, sino en el siguiente cálculo de jornada.
--
-- Reinicio de temporada: la app borra las filas de la federación justo
-- después de llamar a reiniciar_federacion() (ver AdminFederacion en
-- index.html), así que no hace falta modificar esa función.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

create table if not exists logros_progreso (
  participante_id  uuid primary key references participantes(id) on delete cascade,
  federacion_id    uuid not null references federaciones(id) on delete cascade,
  datos            jsonb not null default '{}'::jsonb,
  actualizado_at   timestamptz not null default now()
);

create index if not exists logros_progreso_fed_idx on logros_progreso(federacion_id);

alter table logros_progreso enable row level security;

-- Lectura: miembros de la federación y su admin (igual que `logros`).
drop policy if exists "Ver progreso de logros de la federación" on logros_progreso;
create policy "Ver progreso de logros de la federación"
  on logros_progreso for select
  using (
    federacion_id in (
      select federacion_id from participantes where user_id = auth.uid()
      union
      select id from federaciones where admin_user_id = auth.uid()
    )
  );

-- Escritura: solo admin/moderador (recalcularLogros hace upsert, que
-- necesita insert + update; delete se usa al reiniciar la temporada).
drop policy if exists "Admin o mod inserta progreso de logros" on logros_progreso;
create policy "Admin o mod inserta progreso de logros"
  on logros_progreso for insert
  with check ( es_admin_o_mod(federacion_id) );

drop policy if exists "Admin o mod actualiza progreso de logros" on logros_progreso;
create policy "Admin o mod actualiza progreso de logros"
  on logros_progreso for update
  using ( es_admin_o_mod(federacion_id) )
  with check ( es_admin_o_mod(federacion_id) );

drop policy if exists "Admin o mod borra progreso de logros" on logros_progreso;
create policy "Admin o mod borra progreso de logros"
  on logros_progreso for delete
  using ( es_admin_o_mod(federacion_id) );

grant select, insert, update, delete on logros_progreso to authenticated;
