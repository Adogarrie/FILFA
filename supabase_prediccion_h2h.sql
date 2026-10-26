-- ═══════════════════════════════════════════════════════════════
-- FILFA — Predicción de la clasificación final de la Liga FILFA (H2H)
--
-- Añade a `estadisticas_jugadores` la columna con la última predicción de
-- la Liga FILFA: por división, cuántas de las temporadas simuladas termina
-- cada equipo en cada puesto, su puesto esperado y sus puntos esperados.
--
-- La calcula SOLO el admin con el botón "Recalcular predicción" de
-- Liga FILFA → Predicción (simulación en su navegador de los partidos
-- pendientes del calendario, con el bonus de local y el baremo de goles) y
-- la guarda aquí; el resto de usuarios solo la leen. Al reiniciar la
-- temporada se borra con la fila.
--
-- Amplía la protección de supabase_prediccion_fantasy.sql: el trigger
-- impide que alguien que no sea el admin cambie `prediccion` o
-- `prediccion_h2h` (los moderadores siguen pudiendo escribir el resto de
-- la fila, que necesitan para los jugadores destacados). Se puede ejecutar
-- aunque no se haya ejecutado antes supabase_prediccion_fantasy.sql.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table estadisticas_jugadores
  add column if not exists prediccion jsonb,
  add column if not exists prediccion_h2h jsonb;

create or replace function proteger_prediccion_fantasy()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (tg_op = 'INSERT' and (new.prediccion is not null or new.prediccion_h2h is not null))
     or (tg_op = 'UPDATE' and (new.prediccion is distinct from old.prediccion
                               or new.prediccion_h2h is distinct from old.prediccion_h2h)) then
    if not exists (
      select 1 from federaciones
       where id = new.federacion_id and admin_user_id = auth.uid()
    ) then
      raise exception 'Solo el admin de la federación puede recalcular la predicción';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists proteger_prediccion_fantasy on estadisticas_jugadores;
create trigger proteger_prediccion_fantasy
  before insert or update on estadisticas_jugadores
  for each row execute function proteger_prediccion_fantasy();
