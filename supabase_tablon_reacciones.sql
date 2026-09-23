-- ═══════════════════════════════════════════════════════════════
-- FILFA — Reacciones y comentarios en el Tablón
--
-- Dos tablas nuevas sobre `anuncios`: reacciones con emoji (toggle,
-- un participante solo puede reaccionar una vez por emoji a cada
-- anuncio) y comentarios de texto libre. Ambas sin aprobación previa
-- (a diferencia de mensaje_usuario en `anuncios`, que sí puede requerir
-- aprobación según `mensajes_tablon_habilitados`).
--
-- Los comentarios se muestran en la app como texto plano (sin Markdown),
-- a diferencia de anuncios.texto — ver nota de seguridad en el plan:
-- renderMd() no sanitiza HTML y estos comentarios no pasan por moderación.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

create table if not exists anuncio_reacciones (
  id              bigserial primary key,
  anuncio_id      bigint not null references anuncios(id) on delete cascade,
  participante_id uuid not null references participantes(id) on delete cascade,
  emoji           text not null,
  created_at      timestamptz not null default now(),
  unique (anuncio_id, participante_id, emoji)
);

create table if not exists anuncio_respuestas (
  id              bigserial primary key,
  anuncio_id      bigint not null references anuncios(id) on delete cascade,
  participante_id uuid references participantes(id) on delete set null,
  actor_nombre    text,
  texto           text not null,
  created_at      timestamptz not null default now()
);

create index if not exists anuncio_reacciones_anuncio_idx on anuncio_reacciones(anuncio_id);
create index if not exists anuncio_respuestas_anuncio_idx on anuncio_respuestas(anuncio_id);

alter table anuncio_reacciones enable row level security;
alter table anuncio_respuestas enable row level security;

-- Visibilidad = misma federación que el anuncio (igual criterio que
-- "Ver anuncios de la federación" en supabase_anuncios_usuarios.sql,
-- incluyendo el filtro de estado='aprobado' para no-admins).
drop policy if exists "Ver reacciones de la federación" on anuncio_reacciones;
create policy "Ver reacciones de la federación"
  on anuncio_reacciones for select
  using (
    anuncio_id in (
      select id from anuncios where
        federacion_id in (select id from federaciones where admin_user_id = auth.uid())
        or (estado = 'aprobado' and federacion_id in (
          select federacion_id from participantes where user_id = auth.uid()
        ))
    )
  );

drop policy if exists "Ver respuestas de la federación" on anuncio_respuestas;
create policy "Ver respuestas de la federación"
  on anuncio_respuestas for select
  using (
    anuncio_id in (
      select id from anuncios where
        federacion_id in (select id from federaciones where admin_user_id = auth.uid())
        or (estado = 'aprobado' and federacion_id in (
          select federacion_id from participantes where user_id = auth.uid()
        ))
    )
  );

-- Insertar: cualquier miembro de la federación del anuncio, siempre como
-- su propio participante_id — sin aprobación.
drop policy if exists "Insertar reacciones propias" on anuncio_reacciones;
create policy "Insertar reacciones propias"
  on anuncio_reacciones for insert
  with check (
    participante_id in (select id from participantes where user_id = auth.uid())
    and anuncio_id in (
      select id from anuncios where federacion_id in (
        select federacion_id from participantes where user_id = auth.uid()
      )
    )
  );

drop policy if exists "Insertar respuestas propias" on anuncio_respuestas;
create policy "Insertar respuestas propias"
  on anuncio_respuestas for insert
  with check (
    participante_id in (select id from participantes where user_id = auth.uid())
    and anuncio_id in (
      select id from anuncios where federacion_id in (
        select federacion_id from participantes where user_id = auth.uid()
      )
    )
  );

-- Borrar: el propio autor, o admin/moderador de la federación.
drop policy if exists "Borrar reacciones propias o admin" on anuncio_reacciones;
create policy "Borrar reacciones propias o admin"
  on anuncio_reacciones for delete
  using (
    participante_id in (select id from participantes where user_id = auth.uid())
    or anuncio_id in (
      select id from anuncios where es_admin_o_mod(federacion_id)
    )
  );

drop policy if exists "Borrar respuestas propias o admin" on anuncio_respuestas;
create policy "Borrar respuestas propias o admin"
  on anuncio_respuestas for delete
  using (
    participante_id in (select id from participantes where user_id = auth.uid())
    or anuncio_id in (
      select id from anuncios where es_admin_o_mod(federacion_id)
    )
  );

grant select, insert, delete on anuncio_reacciones to authenticated;
grant select, insert, delete on anuncio_respuestas to authenticated;
grant usage, select on sequence anuncio_reacciones_id_seq to authenticated;
grant usage, select on sequence anuncio_respuestas_id_seq to authenticated;
