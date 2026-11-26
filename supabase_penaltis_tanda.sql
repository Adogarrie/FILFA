-- ═══════════════════════════════════════════════════════════════
-- FILFA — Tandas de penaltis en los partidos sueltos de los torneos
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- IMPORTANTE: ejecutar DESPUÉS de supabase_penaltis.sql y ANTES de subir
-- el index.html que lo usa (Palmarés pide estas columnas y fallaría).
--
-- Reglas (las aplica la app al pulsar ▶ Calcular / ↻ en un partido suelto
-- empatado de una fase con penaltis, y solo con la jornada archivada):
--  · Lanza primero el local, alternos. N lanzamientos fijos por equipo
--    (penaltis_lanzamientos, defecto 5) y después muerte súbita hasta el
--    11.º; luego la lista vuelve a empezar.
--  · Gol si el lanzador hace al menos penaltis_umbral puntos (defecto 6),
--    sin el doble del capitán.
--  · Lista: titulares que jugaron en su orden de penaltis (los que no
--    jugaron se quitan y el resto sube), después los suplentes que
--    entraron por orden de banquillo; los huecos que falten son fallo.
--  · Si la muerte súbita no puede acabar (las 11 parejas iguales):
--    1) primera pareja con distintos puntos, 2) más puntos fantasy en la
--    jornada (sin ventaja de campo), 3) más puntos acumulados en la Liga
--    Fantástica hasta esa jornada, 4) sorteo.
-- El admin puede escribir el marcador a mano (penaltis_detalle.manual).
-- El 1·X·2 de la quiniela sigue usando goles_local/goles_visitante.
-- Sin cambios de permisos: las columnas siguen las reglas de su tabla.
-- ═══════════════════════════════════════════════════════════════

-- Configuración de la federación (solo la cambia el admin, como el resto).
alter table federaciones add column if not exists penaltis_lanzamientos smallint not null default 5;
alter table federaciones add column if not exists penaltis_umbral numeric not null default 6;
alter table federaciones drop constraint if exists federaciones_penaltis_lanzamientos_check;
alter table federaciones add constraint federaciones_penaltis_lanzamientos_check
  check (penaltis_lanzamientos between 1 and 11);

-- Activación por fase (de momento solo se usa en fases de partidos sueltos).
alter table fases_competicion add column if not exists penaltis boolean not null default false;

-- Resultado de la tanda.
--  penaltis_ganador: 'L' | 'V' (hace falta cuando el marcador de la tanda
--  queda igualado y decide un criterio de desempate o el sorteo).
--  penaltis_detalle: tiro a tiro y cómo se decidió (lo pinta la app).
alter table partidos_competicion add column if not exists penaltis_local     smallint;
alter table partidos_competicion add column if not exists penaltis_visitante smallint;
alter table partidos_competicion add column if not exists penaltis_ganador   text;
alter table partidos_competicion add column if not exists penaltis_detalle   jsonb;
alter table partidos_competicion drop constraint if exists partidos_competicion_penaltis_ganador_check;
alter table partidos_competicion add constraint partidos_competicion_penaltis_ganador_check
  check (penaltis_ganador is null or penaltis_ganador in ('L', 'V'));
