-- ═══════════════════════════════════════════════════════════════
-- FILFA — Scope de comodines por competición (multi-selección)
--
-- Cada comodín puede activarse en una o varias competiciones:
--   Calendario, Liga H2H, y/o uno o varios Torneos.
-- Un booleano por contexto genérico + array de UUIDs para torneos.
--
-- comodin_*_torneo_ids: array de IDs de torneos a los que aplica.
-- Si el array está vacío y en_torneo=true, no aplica a ninguno.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table federaciones
  add column if not exists comodin_capitan_en_calendario   bool    not null default true,
  add column if not exists comodin_capitan_en_h2h          bool    not null default false,
  add column if not exists comodin_capitan_en_torneo       bool    not null default false,
  add column if not exists comodin_capitan_torneo_ids      uuid[]  not null default '{}',
  add column if not exists comodin_banquillo_en_calendario bool    not null default true,
  add column if not exists comodin_banquillo_en_h2h        bool    not null default false,
  add column if not exists comodin_banquillo_en_torneo     bool    not null default false,
  add column if not exists comodin_banquillo_torneo_ids    uuid[]  not null default '{}';
