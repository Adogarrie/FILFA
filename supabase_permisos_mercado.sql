-- ═══════════════════════════════════════════════════════════
-- Permisos adicionales para que el cliente web (rol anon)
-- pueda fichar/vender jugadores y actualizar el presupuesto.
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════

-- ─── Permisos sobre plantillas ──────────────────────────────
grant insert, delete on plantillas            to anon;
grant usage, select  on sequence plantillas_id_seq to anon;

-- Política: cualquiera puede insertar en plantillas
drop policy if exists "Insertar plantillas anon" on plantillas;
create policy "Insertar plantillas anon"
  on plantillas for insert with check (true);

-- Política: cualquiera puede borrar de plantillas
drop policy if exists "Borrar plantillas anon" on plantillas;
create policy "Borrar plantillas anon"
  on plantillas for delete using (true);

-- ─── Permisos sobre participantes (solo columna presupuesto) ─
grant update (presupuesto) on participantes to anon;

-- Política: cualquiera puede actualizar el presupuesto
drop policy if exists "Actualizar presupuesto anon" on participantes;
create policy "Actualizar presupuesto anon"
  on participantes for update using (true) with check (true);

-- ─── Leer presupuesto en el select ──────────────────────────
-- (ya está cubierto por la política "Lectura pública participantes")
