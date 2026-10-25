-- ═══════════════════════════════════════════════════════════════
-- FILFA — Predicción de la clasificación final de la Liga Fantástica
--
-- Añade a `estadisticas_jugadores` (ver supabase_estadisticas_jugadores.sql,
-- que debe ejecutarse antes) la columna con la última predicción calculada:
-- para cada equipo, cuántas de las temporadas simuladas termina en cada
-- puesto, su puesto esperado, su media ponderada y su desviación.
--
-- La calcula SOLO el admin de la federación con el botón "Recalcular
-- predicción" de Liga Fantástica → Predicción (simulación en su navegador
-- con los puntos ya cargados) y la guarda aquí; el resto de usuarios solo
-- la leen. Va en una columna aparte para que Equipos, Estadísticas y la
-- clasificación de jugadores, que piden sus propias columnas, no la
-- descarguen. Al reiniciar la temporada se borra con la fila.
--
-- Permisos: las políticas RLS de la tabla dejan leer a los miembros y
-- escribir a admin y moderadores (los moderadores necesitan escribir los
-- jugadores destacados). Como RLS no distingue columnas, un trigger impide
-- que alguien que no sea el admin cambie `prediccion`; el resto de la fila
-- se sigue pudiendo actualizar como hasta ahora.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table estadisticas_jugadores
  add column if not exists prediccion jsonb;

create or replace function proteger_prediccion_fantasy()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (tg_op = 'INSERT' and new.prediccion is not null)
     or (tg_op = 'UPDATE' and new.prediccion is distinct from old.prediccion) then
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
