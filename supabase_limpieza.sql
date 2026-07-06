-- ═══════════════════════════════════════════════════════════════
-- FILFA — Limpieza de tablas sin uso
-- Ejecutar en: Supabase Dashboard → SQL Editor
--
-- Elimina tablas/vistas que index.html no consulta en ningún sitio
-- (verificado buscando cada `.from('...')` del frontend). Cubre:
--   - El sistema de "Competiciones" (copa/grupos/eliminatorias/goles)
--     construido en BD pero nunca conectado a la app.
--   - El calendario de partidos LaLiga↔Fantasy (sustituido por nada;
--     la vista "Calendario" de la app es en realidad la clasificación).
--   - Restos del login antiguo (usuarios en texto plano) y de un
--     sistema de puntuación por CSV ya sustituido por Admin → Pts
--     Jugadores (que usa `puntos_jugador`, no `puntuaciones_jornada`).
--
-- Haz una copia de seguridad (Database → Backups, o pg_dump) antes de
-- ejecutar esto si tienes dudas. Todas las sentencias son `if exists`,
-- así que es seguro ejecutarlo aunque alguna tabla ya no exista.
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Sistema de competiciones (copa/grupos/eliminatorias) ────
-- Orden: hijos antes que padres (o usar cascade).
drop table if exists competicion_inscripciones cascade;
drop table if exists fase_partidos            cascade;
drop table if exists fase_grupos              cascade;
drop table if exists fases                    cascade;
drop table if exists competiciones            cascade;

-- ─── 2. Copa antigua (pre-competiciones) ────────────────────────
drop table if exists copa_calendario cascade;
drop table if exists copa_grupos     cascade;

-- ─── 3. Calendario de partidos (nunca leído por la app) ─────────
drop table if exists calendario cascade;

-- ─── 4. Login antiguo con contraseñas en texto plano ────────────
-- Solo si ya confirmaste que todos entran bien con Supabase Auth
-- (ver README.md, paso 2.1). Si tienes dudas, comenta esta línea.
drop table if exists usuarios cascade;

-- ─── 5. Puntuación por CSV — sustituida por Admin → Pts Jugadores
-- (que usa `puntos_jugador`, tabla distinta y sí en uso)
drop table if exists puntuaciones_jornada cascade;

-- ─── 6. Vistas sin consultas desde el cliente ───────────────────
drop view if exists vista_clasificacion    cascade;
drop view if exists vista_jugadores_libres cascade;

-- ─── 7. Config global — sustituida por columnas en `federaciones`
-- (sorteo_habilitado, ventas_habilitadas, jornada_actual, etc.)
drop table if exists config cascade;
