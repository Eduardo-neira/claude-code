-- =====================================================================
-- Grupo Portátil · Puente SimpliRoute → Supabase
-- 0001_staging_simpliroute.sql — Aterrizaje crudo (staging)
-- =====================================================================
-- Objetivo de esta migración: que las visitas que SimpliRoute ya registra
-- aterricen en Supabase SIN tocar todavía `servicios`.
--
-- Por qué en dos etapas y no directo a `servicios`:
--   1. No conocemos aún los nombres exactos de campos que devuelve la API
--      de SimpliRoute para la cuenta de GP. Guardar el JSON crudo nos deja
--      descubrirlos con datos reales en vez de adivinarlos (ver 02).
--   2. El problema difícil no es traer los datos, es **amarrar** cada visita
--      con su contrato de GP. Mientras eso no esté resuelto, meter filas a
--      `servicios` con `contrato_id` nulo ensuciaría la tabla madre.
--   3. Si el amarre se corrige después, se reprocesa desde el crudo sin
--      volver a pegarle a la API.
--
-- Es ADITIVA: solo crea objetos nuevos y un índice único sobre `servicios`.
-- No modifica ni migra ningún dato existente.
--
-- APLICADA a gp-inventario el 2026-08-17.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Bitácora cruda de visitas (append-only)
-- ---------------------------------------------------------------------
-- Append-only a propósito: el ingestor solo INSERTA, nunca actualiza.
-- Reprocesar un día agrega filas nuevas en vez de pisar las anteriores,
-- así queda historia de qué devolvió la API y cuándo. La vista
-- `simpliroute_visitas_ultima` se queda con la más reciente por visita.
create table if not exists simpliroute_visitas_raw (
  id             bigint generated always as identity primary key,
  visita_id      text not null,          -- id de la visita en SimpliRoute
  ruta_id        text,                   -- id de la ruta, si el payload lo trae
  fecha_planeada date,
  payload        jsonb not null,         -- la visita completa, tal cual llegó
  ingestado_en   timestamptz not null default now()
);

comment on table simpliroute_visitas_raw is
  'Bitácora cruda de visitas traídas de la API de SimpliRoute. Append-only: el ingestor nunca actualiza ni borra.';
comment on column simpliroute_visitas_raw.payload is
  'JSON completo de la visita tal como lo devolvió SimpliRoute. Fuente para descubrir nombres de campo y para reprocesar.';

create index if not exists idx_sr_raw_visita  on simpliroute_visitas_raw (visita_id);
create index if not exists idx_sr_raw_fecha   on simpliroute_visitas_raw (fecha_planeada);
create index if not exists idx_sr_raw_ingesta on simpliroute_visitas_raw (ingestado_en desc);

-- Última versión conocida de cada visita.
--
-- El desempate por `id` NO es decorativo: `now()` es la hora de inicio de
-- transacción, así que dos versiones de la misma visita insertadas en el mismo
-- lote comparten `ingestado_en`, el ORDER BY empata y `distinct on` elegiría
-- una fila arbitraria — puede ganar la vieja. `id` es identity monotónico y
-- desempata siempre a favor de la última insertada.
create or replace view simpliroute_visitas_ultima as
select distinct on (visita_id)
  id, visita_id, ruta_id, fecha_planeada, payload, ingestado_en
from simpliroute_visitas_raw
order by visita_id, ingestado_en desc, id desc;

-- Sin esto la vista hereda SECURITY DEFINER (default de Supabase para vistas
-- creadas por el rol postgres) y NO respeta el RLS de quien la consulta,
-- anulando la protección de la tabla de abajo.
alter view simpliroute_visitas_ultima set (security_invoker = on);

comment on view simpliroute_visitas_ultima is
  'Una fila por visita: la ingesta más reciente (desempate determinista por id). Es la vista que consumen el amarre y la promoción.';

-- ---------------------------------------------------------------------
-- 2. Configuración del puente
-- ---------------------------------------------------------------------
-- Los nombres de campo de SimpliRoute se llenan DESPUÉS de la primera
-- ingesta, con lo que revele `02_descubrimiento.sql`. Se dejan nulos a
-- propósito: es más honesto que un default inventado.
create table if not exists simpliroute_config (
  clave text primary key,
  valor text,
  notas text
);

insert into simpliroute_config (clave, valor, notas) values
  ('path_contrato',   null,
   'Campo del payload que trae el identificador de contrato de GP. Llenar tras correr 02. Ej: reference'),
  ('path_checkout_ts', null,
   'Campo del payload con la marca de tiempo del checkout. Ej: checkout_time'),
  ('path_checkout_lat', null,
   'Campo del payload con la latitud del checkout'),
  ('path_checkout_lng', null,
   'Campo del payload con la longitud del checkout'),
  ('path_estado',     null,
   'Campo del payload con el estado de la visita (completada / fallida)'),
  ('valor_completado', null,
   'Valor exacto que usa SimpliRoute para "visita completada". Ej: completed'),
  ('radio_amarre_m',  '150',
   'Radio máximo en metros para amarrar una visita a un contrato por coordenada'),
  ('sucursal_id',     '1',
   'Sucursal a la que pertenecen las visitas de esta cuenta de SimpliRoute (1 = MTY)')
on conflict (clave) do nothing;

comment on table simpliroute_config is
  'Parámetros del puente SimpliRoute. Los path_* se llenan con datos reales tras la primera ingesta (ver 02_descubrimiento.sql).';

-- Helper de lectura, para no repetir el subselect en cada función.
create or replace function sr_config(p_clave text)
returns text language sql stable as $$
  select valor from simpliroute_config where clave = p_clave;
$$;

-- search_path fijo: sin esto un rol podría anteponer un esquema propio y
-- hacer que la función lea de otra tabla `simpliroute_config`.
alter function sr_config(text) set search_path = public, pg_temp;

-- ---------------------------------------------------------------------
-- 3. Idempotencia sobre `servicios`
-- ---------------------------------------------------------------------
-- `servicios.simpliroute_visit_id` ya existía en el schema pero sin índice
-- único. Sin esto, reprocesar un día duplicaría servicios — y como la tabla
-- hoy tiene 0 filas, es el momento más barato para ponerlo.
create unique index if not exists uq_servicios_simpliroute_visit
  on servicios (simpliroute_visit_id)
  where simpliroute_visit_id is not null;

-- Lo mismo para rutas.
create unique index if not exists uq_rutas_simpliroute_id
  on rutas (simpliroute_id)
  where simpliroute_id is not null;

-- ---------------------------------------------------------------------
-- 4. Seguridad
-- ---------------------------------------------------------------------
-- Staging contiene direcciones y coordenadas de clientes: no se expone a anon.
alter table simpliroute_visitas_raw enable row level security;
alter table simpliroute_config      enable row level security;

-- Sin políticas para anon/authenticated: solo la service_role (que las
-- ignora) puede leer y escribir. Es lo que usa n8n.

-- Cinturón adicional al RLS: no hay razón para que anon o authenticated
-- puedan siquiera intentar leer staging.
revoke all on simpliroute_visitas_raw     from anon, authenticated;
revoke all on simpliroute_config          from anon, authenticated;
revoke all on simpliroute_visitas_ultima  from anon, authenticated;
