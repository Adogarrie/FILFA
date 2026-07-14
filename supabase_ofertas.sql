-- ═══════════════════════════════════════════════════════════════
-- FILFA — Ofertas entre equipos
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

create table if not exists ofertas_jugadores (
  id              serial primary key,
  federacion_id   uuid        not null references federaciones(id)  on delete cascade,
  jugador_id      uuid        not null references jugadores(id)      on delete cascade,
  ofertante_id    uuid        not null references participantes(id)  on delete cascade,
  propietario_id  uuid        not null references participantes(id)  on delete cascade,
  cantidad        numeric(12,2) not null check (cantidad > 0),
  estado          text        not null default 'pendiente'
                              check (estado in ('pendiente','aceptada','rechazada')),
  mensaje         text,       -- mensaje de rechazo / contraoferta del propietario
  leida           boolean     not null default false,
  created_at      timestamptz not null default now()
);

alter table ofertas_jugadores enable row level security;

grant select, insert, update on ofertas_jugadores to authenticated;
grant usage, select on sequence ofertas_jugadores_id_seq to authenticated;

-- Ver: ofertante, propietario o admin de la federación
create policy "Ver ofertas"
  on ofertas_jugadores for select
  using (
    ofertante_id   in (select id from participantes where user_id = auth.uid())
    or propietario_id in (select id from participantes where user_id = auth.uid())
    or exists (select 1 from federaciones where id = federacion_id and admin_user_id = auth.uid())
  );

-- Insertar: solo el ofertante (debe ser tu propio equipo)
create policy "Hacer oferta"
  on ofertas_jugadores for insert
  with check (
    ofertante_id in (select id from participantes where user_id = auth.uid())
  );

-- Actualizar: propietario (acepta/rechaza), ofertante (marca leída) o admin
create policy "Gestionar oferta"
  on ofertas_jugadores for update
  using (
    propietario_id in (select id from participantes where user_id = auth.uid())
    or ofertante_id in (select id from participantes where user_id = auth.uid())
    or exists (select 1 from federaciones where id = federacion_id and admin_user_id = auth.uid())
  );
