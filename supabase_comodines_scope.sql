-- ═══════════════════════════════════════════════════════════════
-- FILFA — Scope de comodines por competición
--
-- Cada comodín (capitán doble / banquillo completo) puede
-- configurarse para que solo afecte a una competición concreta:
--   'calendario' → puntuación fantasy por puntos (default)
--   'h2h'        → Liga H2H
--   'torneo'     → Torneo específico (ver comodin_*_torneo_id)
--   'ninguno'    → nunca se aplica (habilitado pero sin efecto)
--
-- Si scope = 'torneo', el comodín solo se aplica en el torneo
-- referenciado por comodin_capitan_torneo_id /
-- comodin_banquillo_torneo_id.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table federaciones
  add column if not exists comodin_capitan_scope       text not null default 'calendario',
  add column if not exists comodin_banquillo_scope     text not null default 'calendario',
  add column if not exists comodin_capitan_torneo_id   uuid references competiciones(id) on delete set null,
  add column if not exists comodin_banquillo_torneo_id uuid references competiciones(id) on delete set null;
