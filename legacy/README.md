# Legacy

Código y SQL que en algún momento existieron para funcionalidades que
`index.html` ya no usa (verificado por ausencia total de referencias en el
frontend). Se conservan aquí por si se retoman más adelante; no forman parte
del flujo actual de la app.

## python/
- `generar_calendario.py`, `importar_calendario.py` — calendario de partidos LaLiga↔Fantasy (tabla `calendario`, nunca leída por la app).
- `generar_copa.py` — fase de copa por grupos (tablas `copa_grupos`/`copa_calendario`, nunca leídas).
- `importar_puntos.py` — importación de puntos vía CSV. Roto contra el esquema actual (usa la columna `titular` en vez de `es_titular`, y escribe en `puntuaciones_jornada`, tabla que nadie lee). Sustituido por **Admin → Pts Jugadores** en la app.
- `añadir_puntos_equipos.py` — alta manual de puntos por equipo. Redundante con **Admin → Equipos → Puntos por jornada**.
- `ejemplo_grupos_copa.csv`, `ejemplo_puntos_j1.csv` — CSVs de ejemplo de los scripts anteriores.

## sql/
- `supabase_sorteo.sql` — activaba el sorteo vía una tabla `config` global; sustituido por la columna `sorteo_habilitado` en `federaciones` (multi-liga).
- `supabase_copa.sql`, `supabase_competiciones.sql`, `supabase_inscripciones.sql`, `supabase_modo_goles.sql`, `supabase_partidos_resultado.sql` — esquema de un sistema de competiciones (copa/grupos/eliminatorias/modo goles) construido en base de datos pero nunca conectado al frontend.

Ver `supabase_limpieza.sql` en la raíz del repo para los `DROP TABLE` correspondientes a ejecutar en Supabase, si decides que estas tablas ya no hacen falta en producción.
