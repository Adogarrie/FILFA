-- ═══════════════════════════════════════════════════════════════
-- FILFA — Doble posición en jugadores
--
-- Un jugador puede tener una posición secundaria opcional (posicion_alt).
-- El admin la asigna/elimina desde AdminJugadores.
--
-- En la alineación, cada titular con posicion_alt puede ser colocado
-- en cualquiera de sus dos posiciones (posicion_usada); esto afecta
-- al recuento de la formación y al cálculo de sustituciones.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Posición alternativa en jugadores ─────────────────────────
alter table jugadores
  add column if not exists posicion_alt posicion_tipo default null;

-- Un portero no puede tener posición alternativa, y la alt no puede
-- ser igual a la primaria ni ser portero.
alter table jugadores
  drop constraint if exists jugadores_posicion_alt_check;

alter table jugadores
  add constraint jugadores_posicion_alt_check check (
    posicion_alt is null
    or (posicion <> 'POR' and posicion_alt <> 'POR' and posicion_alt <> posicion)
  );

-- ── 2. Posición usada en alineaciones ────────────────────────────
-- Guarda qué posición eligió el usuario para un titular con doble pos.
alter table alineaciones
  add column if not exists posicion_usada posicion_tipo default null;
