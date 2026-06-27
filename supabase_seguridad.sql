-- ═══════════════════════════════════════════════════════════════
-- FILFA — Migración a Supabase Auth + RLS real por propietario
-- Ejecutar en: Supabase Dashboard → SQL Editor
--
-- Cierra dos problemas críticos:
--   1) Contraseñas en texto plano expuestas via REST (tabla 'usuarios').
--   2) Políticas RLS abiertas ("using (true)") que permiten a cualquier
--      cliente modificar datos de OTROS participantes.
--
-- Tras ejecutar este script, cada amigo se registra solo en la app (email +
-- contraseña, o Google) y al entrar por primera vez elige si "reclama" su
-- equipo de antes (de la lista de equipos sin dueño) o crea uno nuevo.
-- No hace falta que el admin recopile emails ni ejecute ningún script.
--
-- Para convertirte en admin (tabla 'administradores', sin acceso para
-- nadie salvo el propio Postgres): regístrate primero en la app como
-- cualquier amigo, luego en el SQL Editor ejecuta:
--   select id, email from auth.users where email = 'tu_email@aqui.com';
--   insert into administradores (user_id) values ('<el id de arriba>');
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- 1. ADMINISTRADORES + función es_admin()
-- ═══════════════════════════════════════════════════════════════

create table if not exists administradores (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table administradores enable row level security;
-- Sin políticas: ni anon ni authenticated pueden leer/escribir esta tabla
-- directamente. Solo el service_role (scripts Python) puede gestionarla.

create or replace function es_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (select 1 from administradores where user_id = auth.uid());
$$;

grant execute on function es_admin() to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- 2. USUARIOS — matar la fuga de contraseñas ya mismo
-- ═══════════════════════════════════════════════════════════════

revoke select on usuarios from anon;
-- Cuando hayas confirmado que todos los amigos entran bien con el nuevo
-- login (Supabase Auth), ejecuta manualmente:
--   drop table usuarios;

-- ═══════════════════════════════════════════════════════════════
-- 3. PARTICIPANTES — alta propia (auto-registro), reclamar equipo
--    existente sin dueño, y edición solo del propio dueño o un admin
-- ═══════════════════════════════════════════════════════════════

drop policy if exists "Actualizar presupuesto anon"  on participantes;
drop policy if exists "Edición propia participante"  on participantes;

-- Un mismo usuario no puede ser dueño de dos equipos a la vez
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'participantes_user_id_unique'
  ) then
    alter table participantes add constraint participantes_user_id_unique unique (user_id);
  end if;
end $$;

revoke update (presupuesto) on participantes from anon;
grant select on participantes to authenticated;
grant update (presupuesto) on participantes to authenticated;
-- Alta propia: solo estas tres columnas (el presupuesto inicial lo pone
-- siempre el valor por defecto de la columna, nunca lo elige el cliente)
grant insert (nombre, division_id, user_id) on participantes to authenticated;

create policy "Actualizar propio o admin participante"
  on participantes for update
  using      (es_admin() or auth.uid() = user_id)
  with check (es_admin() or auth.uid() = user_id);

-- Crear un equipo nuevo vinculado a la propia cuenta
create policy "Crear equipo propio"
  on participantes for insert
  with check (auth.uid() = user_id);

-- Reclamar un equipo existente que todavía no tiene cuenta vinculada
-- (migración de amigos que ya jugaban antes de este cambio)
create policy "Reclamar equipo libre"
  on participantes for update
  using      (user_id is null)
  with check (auth.uid() = user_id);

-- ═══════════════════════════════════════════════════════════════
-- 4. PLANTILLAS — solo el propio equipo o un admin puede fichar/vender
-- ═══════════════════════════════════════════════════════════════

drop policy if exists "Insertar plantillas anon" on plantillas;
drop policy if exists "Borrar plantillas anon"    on plantillas;
drop policy if exists "Gestión propia plantilla"  on plantillas;

revoke insert, delete on plantillas from anon;
grant select, insert, update, delete on plantillas to authenticated;

create policy "Insertar plantilla propia o admin"
  on plantillas for insert
  with check (es_admin() or participante_id in
              (select id from participantes where user_id = auth.uid()));

create policy "Actualizar plantilla propia o admin"
  on plantillas for update
  using      (es_admin() or participante_id in
              (select id from participantes where user_id = auth.uid()))
  with check (es_admin() or participante_id in
              (select id from participantes where user_id = auth.uid()));

create policy "Borrar plantilla propia o admin"
  on plantillas for delete
  using (es_admin() or participante_id in
         (select id from participantes where user_id = auth.uid()));

-- ═══════════════════════════════════════════════════════════════
-- 5. ALINEACIONES — solo el propio equipo o un admin puede editarlas
-- ═══════════════════════════════════════════════════════════════

drop policy if exists "Escritura libre alineaciones" on alineaciones;

revoke insert, update, delete on alineaciones from anon;
grant select, insert, update, delete on alineaciones to authenticated;

create policy "Insertar alineacion propia o admin"
  on alineaciones for insert
  with check (es_admin() or participante_id in
              (select id from participantes where user_id = auth.uid()));

create policy "Actualizar alineacion propia o admin"
  on alineaciones for update
  using      (es_admin() or participante_id in
              (select id from participantes where user_id = auth.uid()))
  with check (es_admin() or participante_id in
              (select id from participantes where user_id = auth.uid()));

create policy "Borrar alineacion propia o admin"
  on alineaciones for delete
  using (es_admin() or participante_id in
         (select id from participantes where user_id = auth.uid()));

-- ═══════════════════════════════════════════════════════════════
-- 6. PUJAS — el propio equipo gestiona su puja pendiente; solo un
--    admin puede resolver (marcar resuelta/ganadora)
-- ═══════════════════════════════════════════════════════════════

drop policy if exists "Escritura libre pujas" on pujas;

revoke insert, update, delete on pujas from anon;
grant select, insert, update, delete on pujas to authenticated;

create policy "Insertar puja propia o admin"
  on pujas for insert
  with check (
    es_admin()
    or (participante_id in (select id from participantes where user_id = auth.uid())
        and resuelta = false and ganadora is null)
  );

create policy "Actualizar puja propia o admin"
  on pujas for update
  using (es_admin() or participante_id in
         (select id from participantes where user_id = auth.uid()))
  with check (
    es_admin()
    or (participante_id in (select id from participantes where user_id = auth.uid())
        and resuelta = false and ganadora is null)
  );

create policy "Borrar puja propia o admin"
  on pujas for delete
  using (es_admin() or participante_id in
         (select id from participantes where user_id = auth.uid()));

-- ═══════════════════════════════════════════════════════════════
-- 7. JORNADAS_CIERRE — solo un admin fija los cierres
-- ═══════════════════════════════════════════════════════════════

drop policy if exists "Escritura libre jornadas_cierre" on jornadas_cierre;

revoke insert, update, delete on jornadas_cierre from anon;
grant select, insert, update, delete on jornadas_cierre to authenticated;

create policy "Escritura solo admin jornadas_cierre"
  on jornadas_cierre for all
  using      (es_admin())
  with check (es_admin());

-- ═══════════════════════════════════════════════════════════════
-- 8. CONFIG — lectura pública, escritura solo admin
-- ═══════════════════════════════════════════════════════════════

alter table config enable row level security;

revoke select, update on config from anon;
grant select, update on config to authenticated;

create policy "Lectura config" on config for select using (true);
create policy "Escritura solo admin config"
  on config for all
  using      (es_admin())
  with check (es_admin());

-- ═══════════════════════════════════════════════════════════════
-- 9. CLASIFICACION — lectura pública, escritura solo admin
-- ═══════════════════════════════════════════════════════════════

alter table clasificacion enable row level security;

revoke insert, update on clasificacion from anon;
grant select, insert, update on clasificacion to authenticated;

create policy "Lectura clasificacion" on clasificacion for select using (true);
create policy "Escritura solo admin clasificacion"
  on clasificacion for all
  using      (es_admin())
  with check (es_admin());

-- ═══════════════════════════════════════════════════════════════
-- 10. CALENDARIO — lectura pública, escritura solo admin
-- ═══════════════════════════════════════════════════════════════

alter table calendario enable row level security;

revoke insert, delete on calendario from anon;
grant select, insert, update, delete on calendario to authenticated;

create policy "Lectura calendario" on calendario for select using (true);
create policy "Escritura solo admin calendario"
  on calendario for all
  using      (es_admin())
  with check (es_admin());

-- ═══════════════════════════════════════════════════════════════
-- 11. COPA — lectura pública, escritura solo admin
-- ═══════════════════════════════════════════════════════════════

alter table copa_grupos     enable row level security;
alter table copa_calendario enable row level security;

revoke insert, delete on copa_grupos     from anon;
revoke insert, delete on copa_calendario from anon;
grant select, insert, update, delete on copa_grupos     to authenticated;
grant select, insert, update, delete on copa_calendario to authenticated;

create policy "Lectura copa_grupos" on copa_grupos for select using (true);
create policy "Escritura solo admin copa_grupos"
  on copa_grupos for all
  using      (es_admin())
  with check (es_admin());

create policy "Lectura copa_calendario" on copa_calendario for select using (true);
create policy "Escritura solo admin copa_calendario"
  on copa_calendario for all
  using      (es_admin())
  with check (es_admin());

-- ═══════════════════════════════════════════════════════════════
-- 12. Tablas/vistas de solo lectura — mover el grant de anon a
--     authenticated (defensa en profundidad: sin sesión, sin datos)
-- ═══════════════════════════════════════════════════════════════

revoke select on jugadores              from anon;
revoke select on divisiones             from anon;
revoke select on puntuaciones_jornada   from anon;
revoke select on vista_clasificacion    from anon;
revoke select on vista_jugadores_libres from anon;

grant select on jugadores              to authenticated;
grant select on divisiones             to authenticated;
grant select on puntuaciones_jornada   to authenticated;
grant select on vista_clasificacion    to authenticated;
grant select on vista_jugadores_libres to authenticated;
