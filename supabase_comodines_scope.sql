-- ═══════════════════════════════════════════════════════════════
-- FILFA — Scope de comodines por competición (multi-selección)
--
-- Cada comodín puede activarse en una o varias competiciones a la
-- vez: Calendario, Liga H2H, y/o un Torneo específico.
-- Un booleano por contexto, combinables libremente.
--
-- Si comodin_*_en_torneo = true, el torneo referenciado por
-- comodin_*_torneo_id es el que recibe el bonus.
--
-- Si se quiere desactivar el efecto en todos los contextos sin
-- deshabilitar el comodín, basta con desmarcar todos.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table federaciones
  add column if not exists comodin_capitan_en_calendario   bool not null default true,
  add column if not exists comodin_capitan_en_h2h          bool not null default false,
  add column if not exists comodin_capitan_en_torneo       bool not null default false,
  add column if not exists comodin_capitan_torneo_id       uuid references competiciones(id) on delete set null,
  add column if not exists comodin_banquillo_en_calendario bool not null default true,
  add column if not exists comodin_banquillo_en_h2h        bool not null default false,
  add column if not exists comodin_banquillo_en_torneo     bool not null default false,
  add column if not exists comodin_banquillo_torneo_id     uuid references competiciones(id) on delete set null;
