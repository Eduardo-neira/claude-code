-- =====================================================================
-- Grupo Portátil · Puente SimpliRoute → Supabase
-- 03_amarre_y_promocion.sql — De staging a `servicios`
-- =====================================================================
-- Correr DESPUÉS de haber llenado `simpliroute_config` con los nombres de
-- campo reales que reveló `02_descubrimiento.sql`.
--
-- Dos responsabilidades separadas a propósito:
--   AMARRE     — decidir a qué contrato de GP pertenece cada visita.
--   PROMOCIÓN  — copiar a `servicios` solo lo que quedó amarrado.
--
-- Nada promueve una visita sin contrato. Una visita sin amarrar se queda en
-- staging y aparece en `simpliroute_sin_amarre` para revisión humana.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helper: leer un campo del payload por ruta configurable
-- ---------------------------------------------------------------------
-- Soporta rutas anidadas separadas por punto ("cliente.referencia").
-- Devuelve NULL si la ruta no está configurada o no existe en el payload.
create or replace function sr_val(p_payload jsonb, p_clave_config text)
returns text language sql stable as $$
  select case
    when sr_config(p_clave_config) is null then null
    else p_payload #>> string_to_array(sr_config(p_clave_config), '.')
  end;
$$;

comment on function sr_val is
  'Lee del payload de SimpliRoute el campo cuya ruta está guardada en simpliroute_config.';

-- ---------------------------------------------------------------------
-- 1. AMARRE — ¿a qué contrato pertenece esta visita?
-- ---------------------------------------------------------------------
-- Estrategia en cascada, de más confiable a menos:
--   1. Referencia explícita: el payload trae algo que identifica al contrato
--      (id, contrato_num, o el nombre del cliente tal cual está capturado).
--   2. Coordenada: el punto del checkout cae dentro del radio configurado
--      respecto de la coordenada del contrato. Requiere PostGIS (ya instalado).
--   3. Nada: se devuelve NULL y la visita queda para revisión.
--
-- Devuelve también CÓMO se amarró, para poder auditar la calidad del puente.
create or replace function simpliroute_amarrar(p_payload jsonb)
returns table (contrato_id integer, metodo text, confianza text)
language plpgsql stable as $$
declare
  v_ref   text;
  v_lat   double precision;
  v_lng   double precision;
  v_radio numeric;
  v_id    integer;
  v_m     double precision;
begin
  ------------------------------------------------------------------
  -- 1. Por referencia explícita
  ------------------------------------------------------------------
  v_ref := trim(coalesce(sr_val(p_payload, 'path_contrato'), ''));

  if v_ref <> '' then
    -- 1a. id numérico de contrato
    if v_ref ~ '^[0-9]+$' then
      select c.id into v_id from contratos c where c.id = v_ref::integer;
      if v_id is not null then
        return query select v_id, 'referencia:id'::text, 'alta'::text;
        return;
      end if;
    end if;

    -- 1b. contrato_num
    select c.id into v_id
    from contratos c
    where upper(trim(c.contrato_num)) = upper(v_ref)
    limit 1;
    if v_id is not null then
      return query select v_id, 'referencia:contrato_num'::text, 'alta'::text;
      return;
    end if;

    -- 1c. nombre de cliente exacto — solo sirve si el cliente tiene UN
    --     contrato activo. Con varias obras el nombre es ambiguo, y en ese
    --     caso preferimos no adivinar.
    select c.id into v_id
    from contratos c
    where c.activo and upper(trim(c.cliente)) = upper(v_ref)
    group by c.id
    having count(*) over (partition by upper(trim(c.cliente))) = 1
    limit 1;
    if v_id is not null then
      return query select v_id, 'referencia:cliente'::text, 'media'::text;
      return;
    end if;
  end if;

  ------------------------------------------------------------------
  -- 2. Por coordenada del checkout
  ------------------------------------------------------------------
  v_lat   := nullif(sr_val(p_payload, 'path_checkout_lat'), '')::double precision;
  v_lng   := nullif(sr_val(p_payload, 'path_checkout_lng'), '')::double precision;
  v_radio := coalesce(sr_config('radio_amarre_m')::numeric, 150);

  if v_lat is not null and v_lng is not null then
    select c.id,
           st_distance(
             st_setsrid(st_makepoint(v_lng, v_lat), 4326)::geography,
             st_setsrid(st_makepoint(c.longitud::double precision,
                                     c.latitud::double precision), 4326)::geography
           )
      into v_id, v_m
    from contratos c
    where c.activo and c.latitud is not null and c.longitud is not null
    order by st_setsrid(st_makepoint(v_lng, v_lat), 4326)::geography <->
             st_setsrid(st_makepoint(c.longitud::double precision,
                                     c.latitud::double precision), 4326)::geography
    limit 1;

    if v_id is not null and v_m <= v_radio then
      return query select
        v_id,
        format('coordenada:%sm', round(v_m::numeric))::text,
        case when v_m <= 50 then 'alta' else 'media' end::text;
      return;
    end if;
  end if;

  ------------------------------------------------------------------
  -- 3. Sin amarre
  ------------------------------------------------------------------
  return query select null::integer, 'sin_amarre'::text, 'nula'::text;
end;
$$;

comment on function simpliroute_amarrar is
  'Decide a qué contrato de GP pertenece una visita de SimpliRoute: referencia explícita, luego coordenada, luego nada.';

-- ---------------------------------------------------------------------
-- 2. Vista de trabajo: visitas con su amarre resuelto
-- ---------------------------------------------------------------------
create or replace view simpliroute_visitas_amarradas as
select
  v.visita_id,
  v.ruta_id,
  v.fecha_planeada,
  a.contrato_id,
  a.metodo,
  a.confianza,
  sr_val(v.payload, 'path_estado')        as estado_sr,
  sr_val(v.payload, 'path_checkout_ts')   as checkout_ts,
  nullif(sr_val(v.payload, 'path_checkout_lat'), '')::numeric as checkout_lat,
  nullif(sr_val(v.payload, 'path_checkout_lng'), '')::numeric as checkout_lng,
  v.payload
from simpliroute_visitas_ultima v
cross join lateral simpliroute_amarrar(v.payload) a;

comment on view simpliroute_visitas_amarradas is
  'Visitas de SimpliRoute con su contrato de GP resuelto y el método usado. Base de la promoción y de la revisión.';

-- Bandeja de revisión: lo que el puente NO pudo amarrar solo.
create or replace view simpliroute_sin_amarre as
select visita_id, fecha_planeada, checkout_lat, checkout_lng,
       left(payload::text, 300) as muestra_payload
from simpliroute_visitas_amarradas
where contrato_id is null
order by fecha_planeada desc, visita_id;

comment on view simpliroute_sin_amarre is
  'Visitas que requieren decisión humana. Si esta vista crece, el amarre está mal configurado.';

-- Salud del puente: qué tan bien está amarrando.
create or replace view simpliroute_salud_amarre as
select
  fecha_planeada,
  count(*)                                          as visitas,
  count(*) filter (where contrato_id is not null)    as amarradas,
  count(*) filter (where confianza = 'alta')         as confianza_alta,
  count(*) filter (where contrato_id is null)        as sin_amarre,
  round(100.0 * count(*) filter (where contrato_id is null) / nullif(count(*),0), 1)
                                                    as pct_sin_amarre
from simpliroute_visitas_amarradas
group by fecha_planeada
order by fecha_planeada desc;

-- ---------------------------------------------------------------------
-- 3. PROMOCIÓN — de staging a `servicios`
-- ---------------------------------------------------------------------
-- Solo promueve visitas amarradas. Idempotente por el índice único sobre
-- `servicios.simpliroute_visit_id` creado en la migración 0001.
--
-- OJO con `completado`: mientras `servicios.completado` siga con default
-- `true` (ver gp-modelo-empresa/04-modelo-datos §Cambio 11), aquí se fija
-- explícitamente para no heredar ese default equivocado.
create or replace function simpliroute_promover(p_fecha date default null)
returns table (promovidos integer, actualizados integer, omitidos integer)
language plpgsql as $$
declare
  v_completado_valor text := sr_config('valor_completado');
  v_ins integer := 0;
  v_upd integer := 0;
  v_omi integer := 0;
begin
  with candidatas as (
    select *
    from simpliroute_visitas_amarradas
    where contrato_id is not null
      and (p_fecha is null or fecha_planeada = p_fecha)
  ),
  upsert as (
    insert into servicios (
      contrato_id, fecha_servicio, tipo, completado,
      simpliroute_visit_id, checkout_time, checkout_lat, checkout_lng,
      source, operador
    )
    select
      c.contrato_id,
      coalesce(c.fecha_planeada, current_date),
      'LIMPIEZA',
      case
        when v_completado_valor is null then false
        else upper(coalesce(c.estado_sr,'')) = upper(v_completado_valor)
      end,
      c.visita_id,
      nullif(c.checkout_ts,'')::timestamptz,
      c.checkout_lat,
      c.checkout_lng,
      'simpliroute',
      ''
    from candidatas c
    on conflict (simpliroute_visit_id) where simpliroute_visit_id is not null
    do update set
      completado    = excluded.completado,
      checkout_time = excluded.checkout_time,
      checkout_lat  = excluded.checkout_lat,
      checkout_lng  = excluded.checkout_lng
    returning (xmax = 0) as fue_insert
  )
  select
    count(*) filter (where fue_insert),
    count(*) filter (where not fue_insert)
  into v_ins, v_upd
  from upsert;

  select count(*) into v_omi
  from simpliroute_visitas_amarradas
  where contrato_id is null
    and (p_fecha is null or fecha_planeada = p_fecha);

  return query select v_ins, v_upd, v_omi;
end;
$$;

comment on function simpliroute_promover is
  'Copia a `servicios` las visitas amarradas. Idempotente. Devuelve promovidos / actualizados / omitidos por falta de amarre.';

-- ---------------------------------------------------------------------
-- 4. Cómo se usa
-- ---------------------------------------------------------------------
-- Ensayo en seco — ver qué haría sin escribir nada:
--   select * from simpliroute_salud_amarre;
--   select * from simpliroute_sin_amarre limit 20;
--
-- Promover un solo día (recomendado la primera vez):
--   select * from simpliroute_promover(current_date - 1);
--
-- Promover todo lo pendiente:
--   select * from simpliroute_promover();
--
-- Deshacer una promoción (staging queda intacto, se puede reprocesar):
--   delete from servicios where source = 'simpliroute';
