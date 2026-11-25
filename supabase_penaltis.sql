-- ═══════════════════════════════════════════════════════════════
-- FILFA — Orden de lanzadores de penaltis en la alineación
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- IMPORTANTE: ejecutar ANTES de subir el index.html que lo usa (las
-- consultas de Alineación y Equipos piden esta columna y fallarían).
--
-- Solo informativo: cada equipo ordena a sus 11 titulares (1 = primer
-- lanzador; hasta 11 por si hay muerte súbita). Se guarda por jornada
-- con la alineación y se hereda igual que ella. Los suplentes y los
-- jugadores fuera llevan NULL (lo controla la app, no la BD).
-- Sin índice único por (participante_id, jornada, orden_penalti): al
-- intercambiar dos lanzadores el upsert escribe fila a fila y chocaría;
-- la app evita los repetidos.
-- Sin cambios de permisos: la columna sigue las reglas de la tabla.
-- ═══════════════════════════════════════════════════════════════

alter table alineaciones add column if not exists orden_penalti smallint;

alter table alineaciones drop constraint if exists alineaciones_orden_penalti_check;
alter table alineaciones add constraint alineaciones_orden_penalti_check
  check (orden_penalti is null or orden_penalti between 1 and 11);
