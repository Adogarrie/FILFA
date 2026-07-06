-- ═══════════════════════════════════════════════════════════════
-- FILFA — Tablón de anuncios
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- Nuevas columnas en federaciones para los toggles de features
alter table federaciones
  add column if not exists puntos_mod_habilitado boolean not null default false,
  add column if not exists ofertas_habilitadas   boolean not null default false;

-- Tabla principal del tablón
create table if not exists anuncios (
  id             bigserial primary key,
  federacion_id  uuid not null references federaciones(id) on delete cascade,
  tipo           text not null,   -- 'fichaje' | 'venta' | 'sorteo' | 'alineacion' | 'puntos' | 'moderador' | 'penalizacion' | 'oferta' | 'admin'
  texto          text not null,
  actor_nombre   text,            -- quién hizo la acción
  created_at     timestamptz not null default now()
);

create index if not exists anuncios_fed_idx on anuncios(federacion_id, created_at desc);

alter table anuncios enable row level security;

drop policy if exists "Ver anuncios de la federación" on anuncios;
create policy "Ver anuncios de la federación"
  on anuncios for select
  using (
    federacion_id in (
      select federacion_id from participantes where user_id = auth.uid()
      union
      select id from federaciones where admin_user_id = auth.uid()
    )
  );

drop policy if exists "Insertar anuncios" on anuncios;
create policy "Insertar anuncios"
  on anuncios for insert
  with check (
    federacion_id in (
      select id from federaciones where admin_user_id = auth.uid()
      union
      select m.federacion_id from moderadores m
        join participantes p on p.id = m.participante_id
        where p.user_id = auth.uid()
      union
      select federacion_id from participantes where user_id = auth.uid()
    )
  );

grant select, insert on anuncios to authenticated;
grant usage, select on sequence anuncios_id_seq to authenticated;
