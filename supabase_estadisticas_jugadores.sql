-- ═══════════════════════════════════════════════════════════════
-- FILFA — Estadísticas de jugadores destacados por equipo (precalculadas)
--
-- "Jugadores destacados" de cada equipo (más puntos aportados, más veces
-- titular, más veces en el once ideal, más entradas como suplente, más
-- veces sustituido, más rentable) y el ranking de la liga de apariciones
-- en el once ideal. Se muestran en Equipos y en Liga Fantástica →
-- Estadísticas.
--
-- Calcularlas en el navegador de cada usuario exigiría descargar todas las
-- alineaciones archivadas de la temporada en cada visita. En su lugar, la
-- app las calcula al cerrar, reabrir o editar una jornada (AdminPtsJugadores
-- en index.html, o con el botón "Recalcular estadísticas") y guarda el
-- resultado aquí: UNA fila por federación con todo en `datos`. Los usuarios
-- solo leen esa fila (unas pocas KB).
--
-- Solo cuentan las jornadas cerradas (alineaciones_snapshot).
--
-- Reinicio de temporada: la app borra la fila de la federación justo
-- después de llamar a reiniciar_federacion() (ver AdminFederacion).
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

create table if not exists estadisticas_jugadores (
  federacion_id   uuid primary key references federaciones(id) on delete cascade,
  datos           jsonb not null default '{}'::jsonb,
  actualizado_at  timestamptz not null default now()
);

alter table estadisticas_jugadores enable row level security;

-- Lectura: miembros de la federación y su admin (igual que `logros`).
drop policy if exists "Ver estadísticas de jugadores de la federación" on estadisticas_jugadores;
create policy "Ver estadísticas de jugadores de la federación"
  on estadisticas_jugadores for select
  using (
    federacion_id in (
      select federacion_id from participantes where user_id = auth.uid()
      union
      select id from federaciones where admin_user_id = auth.uid()
    )
  );

-- Escritura: solo admin/moderador (upsert = insert + update; delete al
-- reiniciar la temporada).
drop policy if exists "Admin o mod inserta estadísticas de jugadores" on estadisticas_jugadores;
create policy "Admin o mod inserta estadísticas de jugadores"
  on estadisticas_jugadores for insert
  with check ( es_admin_o_mod(federacion_id) );

drop policy if exists "Admin o mod actualiza estadísticas de jugadores" on estadisticas_jugadores;
create policy "Admin o mod actualiza estadísticas de jugadores"
  on estadisticas_jugadores for update
  using ( es_admin_o_mod(federacion_id) )
  with check ( es_admin_o_mod(federacion_id) );

drop policy if exists "Admin o mod borra estadísticas de jugadores" on estadisticas_jugadores;
create policy "Admin o mod borra estadísticas de jugadores"
  on estadisticas_jugadores for delete
  using ( es_admin_o_mod(federacion_id) );

grant select, insert, update, delete on estadisticas_jugadores to authenticated;
