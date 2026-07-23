-- ═══════════════════════════════════════════════════════════════
-- FILFA — Cierre de jornada: snapshot histórico de alineaciones
--
-- Al cerrar una jornada, el sistema genera un registro JSON
-- por equipo con el lineup efectivo + puntos individuales.
-- Esta tabla NO tiene FK a jugadores ni a participantes,
-- por lo que sobrevive borrados de jugadores o equipos.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

create table if not exists alineaciones_snapshot (
  id                  uuid        primary key default gen_random_uuid(),
  federacion_id       uuid        not null references federaciones(id) on delete cascade,
  participante_id     uuid        not null,   -- sin FK, sobrevive borrado de participante
  participante_nombre text        not null,
  jornada             int         not null,
  datos               jsonb       not null default '[]',
  -- Cada elemento de datos: { jugador_id (str), nombre, posicion, equipo_real,
  --   es_titular, orden_suplente, posicion_usada, jugo (bool), pts }
  puntos_totales      numeric(8,2) not null default 0,
  cerrada_at          timestamptz  not null default now(),
  unique(federacion_id, participante_id, jornada)
);

alter table alineaciones_snapshot enable row level security;

-- Lectura: cualquier miembro de la federación
create policy "Miembros leen snapshots"
  on alineaciones_snapshot for select
  using (
    es_admin_o_mod(federacion_id)
    or federacion_id in (
      select federacion_id from participantes where user_id = auth.uid()
    )
  );

-- Escritura: solo admin / moderador
create policy "Admin inserta snapshots"
  on alineaciones_snapshot for insert
  with check (es_admin_o_mod(federacion_id));

create policy "Admin actualiza snapshots"
  on alineaciones_snapshot for update
  using  (es_admin_o_mod(federacion_id))
  with check (es_admin_o_mod(federacion_id));

create policy "Admin elimina snapshots"
  on alineaciones_snapshot for delete
  using (es_admin_o_mod(federacion_id));
