-- =====================================================================
-- Grupo Portátil · Puente SimpliRoute → Supabase
-- 0002_amarre_y_promocion.sql — De staging a `servicios`
-- =====================================================================
-- APLICADA a gp-inventario el 2026-08-19, en cinco migraciones:
--   simpliroute_amarre_por_unidad
--   simpliroute_amarre_y_promocion
--   simpliroute_promocion_y_diagnostico
--   simpliroute_tipo_y_operador
--   simpliroute_promocion_sin_tracking_id
--   servicios_grano_por_unidad
--
-- Este archivo es el estado final consolidado. Todo lo de aquí salió de 123
-- visitas reales del 2026-08-18 (ver ../HALLAZGOS.md), no de supuestos.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Grano correcto de `servicios`
-- ---------------------------------------------------------------------
-- Una visita de SimpliRoute cubre VARIAS unidades ("#715-716-717-718") y en GP
-- cada unidad colocada cuelga de su propio contrato. El grano de `servicios`
-- es (visita, unidad), no (visita).
--
-- `servicios_simpliroute_visit_id_uidx` era preexistente e imponía un servicio
-- por visita. Se elimina. `ux_servicios_tracking` se conserva, y por eso el
-- puente NO llena `tracking_id` (es un atributo de la visita, no de la unidad).
drop index if exists servicios_simpliroute_visit_id_uidx;
drop index if exists uq_servicios_simpliroute_visit;

create unique index if not exists uq_servicios_visita_unidad
  on servicios (simpliroute_visit_id, unidad_id) nulls not distinct
  where simpliroute_visit_id is not null;

-- NULLS NOT DISTINCT no es decorativo: una visita amarrada por nombre no tiene
-- unidad, y con el default (NULLS DISTINCT) el reproceso la duplicaría.

-- ---------------------------------------------------------------------
-- 2. Normalización de razones sociales
-- ---------------------------------------------------------------------
-- Los mismos clientes están escritos distinto en los dos sistemas: sufijos
-- operativos entre paréntesis y forma societaria con comas. Sin normalizar
-- amarran 39 de 123 por nombre; con normalización, 68.
create or replace function gp_norm(t text) returns text
language sql immutable as $$
  select nullif(trim(regexp_replace(
           regexp_replace(
             regexp_replace(
               translate(upper(coalesce(t,'')), 'ÁÉÍÓÚÜÑ', 'AEIOUUN'),
               '\([^)]*\)', ' ', 'g'),
             '\y(S[ .,]*A[ .,]*P[ .,]*I[ .,]*(DE)?[ .,]*C[ .,]*V|S[ .,]*A[ .,]*(DE)?[ .,]*C[ .,]*V|SA[ .,]*DE[ .,]*CV|SRL)\y', ' ', 'g'),
           '[^A-Z0-9]+', ' ', 'g')), '');
$$;
alter function gp_norm(text) set search_path = public, pg_temp;

-- ---------------------------------------------------------------------
-- 3. Qué visitas NO son servicios
-- ---------------------------------------------------------------------
-- 46 de 123 visitas no son servicio a cliente. Promoverlas inflaría los
-- conteos y la facturación. En tabla para ajustarlas sin migración.
create table if not exists simpliroute_exclusiones (
  patron text primary key,
  motivo text not null,
  activo boolean not null default true
);

insert into simpliroute_exclusiones (patron, motivo) values
  ('GASOLINA',        'parada_operativa'),
  ('ESTACION DE GAS', 'parada_operativa'),
  ('TRANSITO',        'parada_operativa'),
  ('PUNTO EMERGENTE', 'parada_operativa'),
  ('PLANTA ',         'parada_operativa'),
  ('DESCARGA ',       'parada_operativa'),
  ('CHECK LIST',      'parada_operativa')
on conflict (patron) do nothing;

alter table simpliroute_exclusiones enable row level security;
revoke all on simpliroute_exclusiones from anon, authenticated;

insert into simpliroute_config (clave, valor, notas) values
  ('qro_lat_min', '20.0', 'Querétaro se lleva aparte: visitas en esta latitud se excluyen'),
  ('qro_lat_max', '21.5', 'Querétaro se lleva aparte: visitas en esta latitud se excluyen'),
  ('patron_fosa', '^\s*FOSA', 'Regex sobre reference: servicio de fosa séptica, otra línea')
on conflict (clave) do nothing;

-- Los path_* ya no son suposiciones: salieron de 123 visitas reales.
update simpliroute_config set valor = 'reference'          where clave = 'path_contrato';
update simpliroute_config set valor = 'checkout_time'      where clave = 'path_checkout_ts';
update simpliroute_config set valor = 'checkout_latitude'  where clave = 'path_checkout_lat';
update simpliroute_config set valor = 'checkout_longitude' where clave = 'path_checkout_lng';
update simpliroute_config set valor = 'status'             where clave = 'path_estado';
update simpliroute_config set valor = 'completed'          where clave = 'valor_completado';

-- ---------------------------------------------------------------------
-- 4. Helpers de lectura del payload
-- ---------------------------------------------------------------------
create or replace function sr_val(p_payload jsonb, p_clave_config text)
returns text language sql stable as $$
  select case
    when sr_config(p_clave_config) is null then null
    else p_payload #>> string_to_array(sr_config(p_clave_config), '.')
  end;
$$;
alter function sr_val(jsonb, text) set search_path = public, pg_temp;

create or replace function sr_clasificar(p_payload jsonb)
returns text language sql stable as $$
  select case
    when exists (select 1 from simpliroute_exclusiones e
                 where e.activo
                   and upper(coalesce(p_payload ->> 'title','')) like '%' || e.patron || '%')
      then 'parada_operativa'
    when nullif(p_payload ->> 'latitude','')::float8
         between coalesce(sr_config('qro_lat_min')::float8, 999)
             and coalesce(sr_config('qro_lat_max')::float8, -999)
      then 'queretaro'
    when coalesce(p_payload ->> 'reference','') ~* coalesce(sr_config('patron_fosa'), '^\s*FOSA')
      then 'fosa'
    else 'sanitario'
  end;
$$;
alter function sr_clasificar(jsonb) set search_path = public, pg_temp;

-- Extrae números de sanitario: "#1058#769 Y 2 LAVAMANOS #406" -> 1058, 769, 406
-- La referencia no siempre usa "#" ("3 BAÑOS 1034,1035,1036"), así que se
-- aceptan también números sueltos de 3-4 dígitos. Los que no existan en
-- `unidades` no amarran, así que ampliar aquí no inventa nada.
create or replace function sr_unidades(p_ref text)
returns table (numero text) language sql immutable as $$
  select distinct coalesce(m[1], m[2])
  from regexp_matches(coalesce(p_ref,''), '#\s*(\d{1,5})|\y(\d{3,4})\y', 'g') m
  where coalesce(m[1], m[2]) is not null;
$$;
alter function sr_unidades(text) set search_path = public, pg_temp;

-- El tipo se lee de `notes`, NO del título: los sufijos del título etiquetan al
-- CLIENTE, no al servicio. "RAMOGO NORTH AMERICA (BAJA FOSA)" se marcaría como
-- RETIRO siendo una visita de fosa.
create or replace function sr_tipo(p_payload jsonb)
returns text language sql stable as $$
  select case upper(trim(coalesce(p_payload ->> 'notes','')))
    when 'BAJA'    then 'RETIRO'
    when 'RETIRO'  then 'RETIRO'
    when 'ENTREGA' then 'ENTREGA'
    else 'LIMPIEZA'
  end;
$$;
alter function sr_tipo(jsonb) set search_path = public, pg_temp;

-- ---------------------------------------------------------------------
-- 5. AMARRE — una fila por unidad servida
-- ---------------------------------------------------------------------
-- Cascada, de más confiable a menos:
--   1. referencia -> unidades.numero -> colocación activa -> contrato  (66/77)
--   2. nombre de cliente normalizado, solo si es inequívoco            ( 1/77)
--   3. coordenada del checkout dentro del radio                        (marginal: 4/123)
--   4. nada -> se queda en la bandeja de revisión
create or replace function simpliroute_amarrar(p_payload jsonb)
returns table (contrato_id integer, unidad_id integer, unidad_numero text,
               metodo text, confianza text)
language plpgsql stable as $$
declare
  v_title text := p_payload ->> 'title';
  v_ref   text := sr_val(p_payload, 'path_contrato');
  v_lat   float8;
  v_lng   float8;
  v_radio numeric;
  v_n     integer;
begin
  -- 1. Por número de sanitario.
  --    La confianza baja a 'media' si el cliente del contrato no coincide con
  --    el título de SimpliRoute: casi siempre significa que la unidad se movió
  --    y `contrato_unidades` quedó desactualizada.
  return query
    select cu.contrato_id, u.id, u.numero,
           'referencia:unidad'::text,
           case when gp_norm(c.cliente) = gp_norm(v_title) then 'alta' else 'media' end
    from sr_unidades(v_ref) n
    join unidades u           on trim(u.numero) = n.numero
    join contrato_unidades cu on cu.unidad_id = u.id and cu.fecha_retiro is null
    join contratos c          on c.id = cu.contrato_id;
  get diagnostics v_n = row_count;
  if v_n > 0 then return; end if;

  -- 2. Por nombre, solo si ese nombre tiene UN contrato activo.
  return query
    select c.id, null::integer, null::text, 'nombre:cliente'::text, 'media'::text
    from contratos c
    where c.activo
      and gp_norm(c.cliente) = gp_norm(v_title)
      and (select count(*) from contratos c2
           where c2.activo and gp_norm(c2.cliente) = gp_norm(v_title)) = 1;
  get diagnostics v_n = row_count;
  if v_n > 0 then return; end if;

  -- 3. Por coordenada.
  v_lat   := nullif(sr_val(p_payload, 'path_checkout_lat'), '')::float8;
  v_lng   := nullif(sr_val(p_payload, 'path_checkout_lng'), '')::float8;
  v_radio := coalesce(sr_config('radio_amarre_m')::numeric, 150);

  if v_lat is not null and v_lng is not null then
    return query
      select x.id, null::integer, null::text,
             format('coordenada:%sm', round(x.metros::numeric))::text, 'baja'::text
      from (
        select c.id,
               st_distance(
                 st_setsrid(st_makepoint(v_lng, v_lat), 4326)::geography,
                 st_setsrid(st_makepoint(c.longitud::float8, c.latitud::float8), 4326)::geography
               ) as metros
        from contratos c
        where c.activo and c.latitud is not null and c.longitud is not null
        order by st_setsrid(st_makepoint(v_lng, v_lat), 4326)::geography <->
                 st_setsrid(st_makepoint(c.longitud::float8, c.latitud::float8), 4326)::geography
        limit 1
      ) x
      where x.metros <= v_radio;
    get diagnostics v_n = row_count;
    if v_n > 0 then return; end if;
  end if;

  -- 4. Sin amarre.
  return query select null::integer, null::integer, null::text,
                      'sin_amarre'::text, 'nula'::text;
end;
$$;
alter function simpliroute_amarrar(jsonb) set search_path = public, pg_temp;

-- ---------------------------------------------------------------------
-- 6. Vistas de trabajo
-- ---------------------------------------------------------------------
create or replace view simpliroute_visitas_amarradas as
select
  v.visita_id, v.ruta_id, v.fecha_planeada,
  v.payload ->> 'title'     as title_sr,
  v.payload ->> 'reference' as referencia_sr,
  a.contrato_id, a.unidad_id, a.unidad_numero, a.metodo, a.confianza,
  sr_val(v.payload, 'path_estado')                            as estado_sr,
  nullif(sr_val(v.payload, 'path_checkout_ts'), '')           as checkout_ts,
  nullif(sr_val(v.payload, 'path_checkout_lat'), '')::numeric as checkout_lat,
  nullif(sr_val(v.payload, 'path_checkout_lng'), '')::numeric as checkout_lng,
  v.payload
from simpliroute_visitas_ultima v
cross join lateral simpliroute_amarrar(v.payload) a
where sr_clasificar(v.payload) = 'sanitario';
alter view simpliroute_visitas_amarradas set (security_invoker = on);

-- Bandeja de revisión.
create or replace view simpliroute_sin_amarre as
select visita_id, fecha_planeada, title_sr, referencia_sr, checkout_lat, checkout_lng
from simpliroute_visitas_amarradas
where contrato_id is null
order by fecha_planeada desc, title_sr;
alter view simpliroute_sin_amarre set (security_invoker = on);

-- Unidades servidas que el catálogo no ubica. Lista de trabajo para cerrar
-- el amarre: lavamanos ausentes y colocaciones sin registrar.
create or replace view simpliroute_unidades_faltantes as
with nums as (
  select distinct v.payload ->> 'title' as cliente_en_simpliroute,
         v.fecha_planeada, n.numero
  from simpliroute_visitas_ultima v
  cross join lateral sr_unidades(sr_val(v.payload, 'path_contrato')) n
  where sr_clasificar(v.payload) = 'sanitario'
)
select nums.numero, nums.cliente_en_simpliroute, nums.fecha_planeada,
       case when u.id is null then 'no existe en unidades'
            else 'sin colocación activa' end as problema,
       u.estatus as estatus_en_catalogo, u.propietario
from nums
left join unidades u on trim(u.numero) = nums.numero
left join contrato_unidades cu on cu.unidad_id = u.id and cu.fecha_retiro is null
where cu.id is null
order by (u.id is not null), nums.numero;
alter view simpliroute_unidades_faltantes set (security_invoker = on);

-- La unidad se sirvió a un cliente distinto del que dice contrato_unidades.
-- Si estas colocaciones están mal, la facturación de esos contratos también.
create or replace view simpliroute_conflictos_colocacion as
select a.unidad_numero,
       a.title_sr as cliente_en_simpliroute,
       c.cliente  as cliente_en_contrato,
       a.contrato_id, cu.fecha_colocacion,
       a.fecha_planeada as visto_el
from simpliroute_visitas_amarradas a
join contratos c          on c.id = a.contrato_id
join contrato_unidades cu on cu.contrato_id = a.contrato_id
                         and cu.unidad_id = a.unidad_id
                         and cu.fecha_retiro is null
where a.metodo = 'referencia:unidad'
  and a.confianza = 'media'
  and gp_norm(c.cliente) is distinct from gp_norm(a.title_sr)
order by a.unidad_numero;
alter view simpliroute_conflictos_colocacion set (security_invoker = on);

-- Salud del puente, contando SOLO lo que está en alcance.
create or replace view simpliroute_salud_amarre as
with base as (
  select v.visita_id, v.fecha_planeada, sr_clasificar(v.payload) as clasificacion
  from simpliroute_visitas_ultima v
),
amarre as (
  select visita_id, bool_or(contrato_id is not null) as amarrada
  from simpliroute_visitas_amarradas group by visita_id
)
select
  b.fecha_planeada,
  count(*)                                                     as visitas_totales,
  count(*) filter (where b.clasificacion <> 'sanitario')        as fuera_de_alcance,
  count(*) filter (where b.clasificacion = 'sanitario')         as en_alcance,
  count(*) filter (where b.clasificacion = 'sanitario' and a.amarrada) as amarradas,
  count(*) filter (where b.clasificacion = 'sanitario'
                    and not coalesce(a.amarrada,false))         as sin_amarre,
  round(100.0 * count(*) filter (where b.clasificacion = 'sanitario'
                                  and not coalesce(a.amarrada,false))
        / nullif(count(*) filter (where b.clasificacion = 'sanitario'),0), 1) as pct_sin_amarre
from base b
left join amarre a using (visita_id)
group by b.fecha_planeada
order by b.fecha_planeada desc;
alter view simpliroute_salud_amarre set (security_invoker = on);

revoke all on simpliroute_visitas_amarradas     from anon, authenticated;
revoke all on simpliroute_sin_amarre            from anon, authenticated;
revoke all on simpliroute_unidades_faltantes    from anon, authenticated;
revoke all on simpliroute_conflictos_colocacion from anon, authenticated;
revoke all on simpliroute_salud_amarre          from anon, authenticated;

-- ---------------------------------------------------------------------
-- 7. Operadores: driver de SimpliRoute -> operador de GP
-- ---------------------------------------------------------------------
-- Se deja VACÍA a propósito. SimpliRoute usa 7 ids de driver y GP tiene 5
-- operadores; adivinar la correspondencia sería inventar quién hizo cada
-- servicio.
create table if not exists simpliroute_operadores (
  driver_id   text primary key,
  operador_id integer references operadores(id),
  notas       text
);

insert into simpliroute_operadores (driver_id, notas)
select distinct payload ->> 'driver', 'visto en la ingesta; falta asignar operador de GP'
from simpliroute_visitas_ultima
where payload ->> 'driver' is not null
on conflict (driver_id) do nothing;

alter table simpliroute_operadores enable row level security;
revoke all on simpliroute_operadores from anon, authenticated;

-- ---------------------------------------------------------------------
-- 8. PROMOCIÓN
-- ---------------------------------------------------------------------
-- Una fila de `servicios` por (visita, unidad). Solo visitas de sanitario con
-- contrato resuelto. Idempotente por uq_servicios_visita_unidad.
create or replace function simpliroute_promover(p_fecha date default null)
returns table (promovidos integer, actualizados integer, omitidos integer)
language plpgsql as $$
declare
  v_completado text := sr_config('valor_completado');
  v_ins integer := 0;
  v_upd integer := 0;
  v_omi integer := 0;
begin
  with upsert as (
    insert into servicios (
      contrato_id, unidad_id, unidad_codigo, fecha_servicio, tipo, completado,
      simpliroute_visit_id, checkout_time, checkout_lat, checkout_lng,
      operador, operador_id, source
    )
    select
      a.contrato_id,
      a.unidad_id,
      u.codigo,
      coalesce(a.fecha_planeada, current_date),
      sr_tipo(a.payload),
      -- `servicios.completado` nace en true por default del schema; aquí se
      -- fija explícitamente para no heredar ese default equivocado.
      case when v_completado is null then false
           else upper(coalesce(a.estado_sr,'')) = upper(v_completado) end,
      a.visita_id,
      nullif(a.checkout_ts,'')::timestamptz,
      a.checkout_lat,
      a.checkout_lng,
      -- Mientras no se llene simpliroute_operadores se guarda el id del
      -- driver, que es trazable, en vez de un nombre inventado.
      coalesce(o.alias, o.nombre, 'SR:' || coalesce(a.payload ->> 'driver','?')),
      m.operador_id,
      'simpliroute'
    from simpliroute_visitas_amarradas a
    left join unidades u             on u.id = a.unidad_id
    left join simpliroute_operadores m on m.driver_id = a.payload ->> 'driver'
    left join operadores o           on o.id = m.operador_id
    where a.contrato_id is not null
      and (p_fecha is null or a.fecha_planeada = p_fecha)
    on conflict (simpliroute_visit_id, unidad_id) where simpliroute_visit_id is not null
    do update set
      completado    = excluded.completado,
      tipo          = excluded.tipo,
      checkout_time = excluded.checkout_time,
      checkout_lat  = excluded.checkout_lat,
      checkout_lng  = excluded.checkout_lng,
      operador      = excluded.operador,
      operador_id   = coalesce(excluded.operador_id, servicios.operador_id)
    returning (xmax = 0) as fue_insert
  )
  select count(*) filter (where fue_insert), count(*) filter (where not fue_insert)
  into v_ins, v_upd
  from upsert;

  select count(*) into v_omi
  from simpliroute_visitas_amarradas
  where contrato_id is null
    and (p_fecha is null or fecha_planeada = p_fecha);

  return query select v_ins, v_upd, v_omi;
end;
$$;
alter function simpliroute_promover(date) set search_path = public, pg_temp;

-- ---------------------------------------------------------------------
-- 9. Cómo se usa
-- ---------------------------------------------------------------------
--   select * from simpliroute_salud_amarre;
--   select * from simpliroute_sin_amarre;
--   select * from simpliroute_unidades_faltantes;
--   select * from simpliroute_conflictos_colocacion;
--   select * from simpliroute_promover('2026-08-18');
--
-- Deshacer (el crudo queda intacto, se reprocesa cuando quieras):
--   delete from servicios where source = 'simpliroute';
