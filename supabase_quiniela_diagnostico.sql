-- ═══════════════════════════════════════════════════════════════
-- FILFA — Diagnóstico de torneos para la quiniela (SOLO LECTURA)
--
-- No modifica nada. Se puede ejecutar antes o después de
-- supabase_quiniela.sql. Devuelve un único JSON con:
--   · columnas: columnas y tipos reales de las tablas de torneos.
--   · torneos:  por torneo y fase, cuántos partidos hay, cuántos no tienen
--               jornada fantasy asignada (no entrarían en ninguna quiniela),
--               cuántos tienen equipos sin definir, cuántos tienen resultado
--               y si alguno tiene federacion_id distinta a la del torneo.
--   · quiniela_por_jornada: qué partidos entrarían en la quiniela de cada
--               jornada fantasy (misma regla que quiniela_candidatos).
--
-- Ejecutar en: Supabase Dashboard → SQL Editor, y copiar el resultado.
-- ═══════════════════════════════════════════════════════════════

select jsonb_pretty(jsonb_build_object(
  'columnas', (
    select jsonb_object_agg(table_name, cols)
      from (select table_name, jsonb_agg(column_name || ' ' || data_type || case when is_nullable = 'NO' then ' not null' else '' end
                                         order by ordinal_position) as cols
              from information_schema.columns
             where table_schema = 'public'
               and table_name in ('competiciones', 'fases_competicion', 'grupos_competicion', 'partidos_competicion')
             group by table_name) t),
  'torneos', (
    select jsonb_agg(jsonb_build_object(
             'federacion', fe.nombre, 'torneo', co.nombre, 'fase', fa.nombre, 'tipo', fa.tipo,
             'partidos', x.total, 'sin_jornada', x.sin_jornada, 'sin_equipos', x.sin_equipos,
             'con_resultado', x.con_resultado, 'fed_distinta', x.fed_distinta,
             'jornadas', x.jornadas)
           order by fe.nombre, co.nombre, fa.nombre)
      from (select pc.fase_id,
                   count(*) as total,
                   count(*) filter (where pc.jornada_fantasy is null) as sin_jornada,
                   count(*) filter (where pc.participante_local_id is null or pc.participante_visitante_id is null) as sin_equipos,
                   count(*) filter (where pc.goles_local is not null and pc.goles_visitante is not null) as con_resultado,
                   count(*) filter (where pc.federacion_id is distinct from (select c2.federacion_id from fases_competicion f2
                                     join competiciones c2 on c2.id = f2.competicion_id where f2.id = pc.fase_id)) as fed_distinta,
                   (select jsonb_agg(distinct p2.jornada_fantasy) from partidos_competicion p2
                     where p2.fase_id = pc.fase_id and p2.jornada_fantasy is not null) as jornadas
              from partidos_competicion pc
             group by pc.fase_id) x
      join fases_competicion fa on fa.id = x.fase_id
      join competiciones co     on co.id = fa.competicion_id
      left join federaciones fe on fe.id = co.federacion_id),
  'quiniela_por_jornada', (
    select jsonb_agg(jsonb_build_object('federacion', fe.nombre, 'jornada', y.jornada_fantasy,
                                        'competicion', y.competicion, 'partidos', y.n)
           order by fe.nombre, y.jornada_fantasy, y.orden, y.competicion)
      from (select federacion_id, jornada_fantasy, competicion, min(orden) as orden, count(*) as n
              from (select hp.federacion_id, c.jornada_fantasy, coalesce(d.nombre, 'Liga FILFA') as competicion,
                           coalesce(hp.division_id, 0) as orden
                      from h2h_partidos hp
                      join h2h_jornada_config c
                        on c.federacion_id = hp.federacion_id and c.jornada_h2h = hp.jornada
                       and c.division_id is not distinct from hp.division_id
                      left join divisiones d on d.id = hp.division_id
                     where c.jornada_fantasy is not null
                    union all
                    select co.federacion_id, pc.jornada_fantasy, co.nombre, 1000
                      from partidos_competicion pc
                      join fases_competicion fa on fa.id = pc.fase_id
                      join competiciones co     on co.id = fa.competicion_id
                     where pc.jornada_fantasy is not null
                       and pc.participante_local_id is not null and pc.participante_visitante_id is not null) z
             group by federacion_id, jornada_fantasy, competicion) y
      left join federaciones fe on fe.id = y.federacion_id)
)) as diagnostico;
