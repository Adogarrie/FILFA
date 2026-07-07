-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fix puntos_jugador: acotar por federación
--
-- Sin federacion_id, el admin de cualquier federación podía
-- sobreescribir los puntos de todos los jugadores de la plataforma,
-- y una federación podía ver/usar puntos de otra.
--
-- IMPORTANTE: Si ya hay filas en puntos_jugador con datos reales,
-- ejecutar primero:  TRUNCATE TABLE puntos_jugador;
-- (Los puntos deberán reintroducirse por federación.)
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Añadir columna (nullable primero para no romper si hay datos) ─
alter table puntos_jugador
  add column if not exists federacion_id uuid references federaciones(id) on delete cascade;

-- ─── 2. Si hay filas sin federacion_id, borrarlas ───────────────
delete from puntos_jugador where federacion_id is null;

-- ─── 3. Hacer la columna obligatoria ────────────────────────────
alter table puntos_jugador
  alter column federacion_id set not null;

-- ─── 4. Reemplazar el unique constraint ─────────────────────────
--   Antes: (jugador_id, jornada)  → cualquier admin sobrescribía a todos
--   Ahora: (jugador_id, jornada, federacion_id) → cada fed tiene sus propios puntos
alter table puntos_jugador
  drop constraint if exists puntos_jugador_jugador_id_jornada_key;

alter table puntos_jugador
  add constraint puntos_jugador_jugador_jornada_fed_key
  unique (jugador_id, jornada, federacion_id);

-- ─── 5. Fix RLS: acotar escritura a la federación del admin ─────
drop policy if exists "Admin escribe puntos_jugador" on puntos_jugador;

create policy "Admin escribe puntos_jugador"
  on puntos_jugador for all
  using (
    exists (
      select 1 from federaciones
      where  id = puntos_jugador.federacion_id
        and  admin_user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from federaciones
      where  id = puntos_jugador.federacion_id
        and  admin_user_id = auth.uid()
    )
  );
