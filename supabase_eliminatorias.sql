-- ═══════════════════════════════════════════════════════════════
-- FILFA — Fases eliminatorias en los torneos (parte A)
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- IMPORTANTE: ejecutar DESPUÉS de supabase_penaltis_tanda.sql y ANTES de
-- subir el index.html que lo usa.
--
-- Estructura: torneo → fase (tipo 'eliminatoria') → rondas → cruces → partidos.
--  · fases_competicion.rondas: [{ nombre, formato: 'unico'|'ida_vuelta',
--    jornadas: [ida, vuelta?], penaltis: bool }] (la ronda N es la posición N).
--  · fases_competicion.goles_fuera: valor doble de los goles fuera en ida y
--    vuelta (por defecto no). cuadro: 'fijo' (el ganador del cruce p pasa
--    solo al cruce ceil(p/2) de la ronda siguiente) o 'libre' (cada ronda
--    se empareja aparte).
--  · cruces_competicion: un emparejamiento. exento = el local pasa sin jugar.
--    ganador_id lo guarda la app al calcular (lo usa el Palmarés);
--    ganador_manual = lo decidió el admin ("Pasa X").
--  · partidos_competicion.cruce_id / partido_n (1 = único o ida, 2 = vuelta):
--    los partidos de siempre, así que quiniela, ventaja local, cálculo y
--    penaltis funcionan igual.
-- Coste: una consulta más al ver un torneo con eliminatoria (pocas filas).
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Tipo de fase 'eliminatoria' ─────────────────────────────
-- Se quita la restricción de tipo que hubiera (su nombre puede variar) y se
-- vuelve a crear con el nuevo valor.
do $$
declare c record;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.fases_competicion'::regclass and contype = 'c'
              and pg_get_constraintdef(oid) ilike '%tipo%'
  loop
    execute format('alter table fases_competicion drop constraint %I', c.conname);
  end loop;
end $$;
alter table fases_competicion add constraint fases_competicion_tipo_check
  check (tipo in ('grupos', 'sueltos', 'eliminatoria'));

alter table fases_competicion add column if not exists rondas      jsonb   not null default '[]'::jsonb;
alter table fases_competicion add column if not exists goles_fuera boolean not null default false;
alter table fases_competicion add column if not exists cuadro      text    not null default 'libre';
alter table fases_competicion drop constraint if exists fases_competicion_cuadro_check;
alter table fases_competicion add constraint fases_competicion_cuadro_check check (cuadro in ('fijo', 'libre'));
alter table fases_competicion drop constraint if exists fases_competicion_rondas_check;
alter table fases_competicion add constraint fases_competicion_rondas_check check (jsonb_typeof(rondas) = 'array');

-- ─── 2. Cruces ──────────────────────────────────────────────────
-- fase_id con el mismo tipo que fases_competicion.id (se lee del esquema).
do $$
declare t text;
begin
  select format_type(atttypid, atttypmod) into t
    from pg_attribute where attrelid = 'public.fases_competicion'::regclass and attname = 'id';
  execute format($f$
    create table if not exists cruces_competicion (
      id             bigserial primary key,
      federacion_id  uuid not null references federaciones(id) on delete cascade,
      fase_id        %s   not null references fases_competicion(id) on delete cascade,
      ronda          smallint not null check (ronda between 1 and 12),
      posicion       smallint not null check (posicion between 1 and 256),
      local_id       uuid references participantes(id) on delete set null,
      visitante_id   uuid references participantes(id) on delete set null,
      exento         boolean not null default false,
      ganador_id     uuid references participantes(id) on delete set null,
      ganador_manual boolean not null default false,
      created_at     timestamptz not null default now(),
      unique (fase_id, ronda, posicion)
    )$f$, t);
end $$;
create index if not exists cruces_competicion_fed on cruces_competicion(federacion_id);

-- federacion_id del cruce = el de su fase.
create or replace function cruces_competicion_validar()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if not exists (select 1 from fases_competicion where id = new.fase_id and federacion_id = new.federacion_id) then
    raise exception 'cruce_federacion_distinta';
  end if;
  return new;
end;
$$;
drop trigger if exists cruces_competicion_validar on cruces_competicion;
create trigger cruces_competicion_validar before insert or update on cruces_competicion
  for each row execute function cruces_competicion_validar();

alter table cruces_competicion enable row level security;
drop policy if exists cruces_competicion_select on cruces_competicion;
drop policy if exists cruces_competicion_admin  on cruces_competicion;
create policy cruces_competicion_select on cruces_competicion for select to authenticated
  using (es_miembro_federacion(federacion_id) or es_admin_o_mod(federacion_id));
create policy cruces_competicion_admin on cruces_competicion for all to authenticated
  using (es_admin_o_mod(federacion_id)) with check (es_admin_o_mod(federacion_id));
revoke all on cruces_competicion from anon;
grant select, insert, update, delete on cruces_competicion to authenticated;
grant usage, select on sequence cruces_competicion_id_seq to authenticated;

-- ─── 3. Partidos de un cruce ────────────────────────────────────
alter table partidos_competicion add column if not exists cruce_id  bigint references cruces_competicion(id) on delete cascade;
alter table partidos_competicion add column if not exists partido_n smallint;
alter table partidos_competicion drop constraint if exists partidos_competicion_partido_n_check;
alter table partidos_competicion add constraint partidos_competicion_partido_n_check
  check (partido_n is null or partido_n in (1, 2));
create index if not exists partidos_competicion_cruce on partidos_competicion(cruce_id);
