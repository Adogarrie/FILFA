-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fix: moderadores no podían escribir en "clasificacion"
--
-- Problema: la política de clasificacion solo comprobaba
-- federaciones.admin_user_id = auth.uid(). Los moderadores con
-- "Moderadores pueden introducir puntos" activado sí podían escribir
-- en puntos_jugador, pero el recálculo de totales por equipo
-- (tabla clasificacion) seguía bloqueado por RLS — de ahí que solo
-- se actualizara cuando el admin volvía a guardar.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

drop policy if exists "Escritura admin federacion clasificacion" on clasificacion;
drop policy if exists "Admin o mod escribe clasificacion"        on clasificacion;

create policy "Admin o mod escribe clasificacion"
  on clasificacion for all
  using (
    exists (
      select 1 from participantes p
      join federaciones f on f.id = p.federacion_id
      where p.id = clasificacion.participante_id
        and (
          f.admin_user_id = auth.uid()
          or (
            f.puntos_mod_habilitado = true
            and exists (
              select 1 from moderadores m
              join  participantes pa on pa.id = m.participante_id
              where m.federacion_id = f.id
                and pa.user_id      = auth.uid()
            )
          )
        )
    )
  )
  with check (
    exists (
      select 1 from participantes p
      join federaciones f on f.id = p.federacion_id
      where p.id = clasificacion.participante_id
        and (
          f.admin_user_id = auth.uid()
          or (
            f.puntos_mod_habilitado = true
            and exists (
              select 1 from moderadores m
              join  participantes pa on pa.id = m.participante_id
              where m.federacion_id = f.id
                and pa.user_id      = auth.uid()
            )
          )
        )
    )
  );
