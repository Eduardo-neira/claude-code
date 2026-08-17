-- =====================================================================
-- Grupo Portátil · Puente SimpliRoute → Supabase
-- 02_descubrimiento.sql — Aprender el schema de la API con datos reales
-- =====================================================================
-- Correr DESPUÉS de la primera ingesta del workflow n8n.
--
-- Por qué existe este archivo: la documentación pública de SimpliRoute no
-- fue accesible al construir esto, y adivinar nombres de campo es
-- exactamente el error que ya nos costó una vez (el flujo de facturación se
-- construyó sobre un supuesto equivocado). Aquí los nombres salen de los
-- datos, no de una suposición.
--
-- Ninguna consulta modifica nada. Son todas de lectura.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. ¿Llegó algo?
-- ---------------------------------------------------------------------
select
  count(*)                       as filas_crudas,
  count(distinct visita_id)      as visitas_distintas,
  min(fecha_planeada)            as desde,
  max(fecha_planeada)            as hasta,
  max(ingestado_en)              as ultima_ingesta
from simpliroute_visitas_raw;

-- ---------------------------------------------------------------------
-- 1. LA CONSULTA CLAVE: qué campos trae realmente una visita
-- ---------------------------------------------------------------------
-- Sustituye a la documentación. Devuelve cada campo de primer nivel, cuántas
-- visitas lo traen, y un valor de ejemplo.
select
  k.clave,
  count(*)                                        as apariciones,
  count(*) filter (where v.payload -> k.clave = 'null'::jsonb) as nulos,
  jsonb_typeof(max(v.payload -> k.clave))         as tipo,
  left(max(v.payload ->> k.clave), 60)            as ejemplo
from simpliroute_visitas_ultima v
cross join lateral jsonb_object_keys(v.payload) as k(clave)
group by k.clave
order by apariciones desc, k.clave;

-- ---------------------------------------------------------------------
-- 2. Candidatos a campo de AMARRE
-- ---------------------------------------------------------------------
-- El amarre visita ↔ contrato es el problema central del puente.
-- Esta consulta busca campos de texto cuyo valor se parezca a algo que GP
-- pueda reconocer: número de contrato, número de sanitario, o el nombre del
-- cliente tal como está escrito en `contratos.cliente`.
with campos as (
  select v.visita_id, k.clave, v.payload ->> k.clave as valor
  from simpliroute_visitas_ultima v
  cross join lateral jsonb_object_keys(v.payload) as k(clave)
  where jsonb_typeof(v.payload -> k.clave) = 'string'
    and coalesce(v.payload ->> k.clave, '') <> ''
)
select
  c.clave,
  count(*)                                                as visitas_con_valor,
  count(distinct c.valor)                                 as valores_distintos,
  -- ¿coincide exacto con el cliente de algún contrato activo?
  count(*) filter (
    where exists (select 1 from contratos ct
                  where ct.activo and upper(trim(ct.cliente)) = upper(trim(c.valor)))
  )                                                       as match_cliente_exacto,
  -- ¿coincide con contrato_num?
  count(*) filter (
    where exists (select 1 from contratos ct
                  where ct.activo and upper(trim(ct.contrato_num)) = upper(trim(c.valor)))
  )                                                       as match_contrato_num,
  -- ¿coincide con un código de unidad (MTY-xxx)?
  count(*) filter (
    where exists (select 1 from unidades u
                  where upper(trim(u.codigo)) = upper(trim(c.valor)))
  )                                                       as match_codigo_unidad,
  -- ¿parece un id numérico de contrato?
  count(*) filter (
    where c.valor ~ '^[0-9]{1,4}$'
      and exists (select 1 from contratos ct where ct.id = c.valor::int)
  )                                                       as match_id_contrato,
  left(max(c.valor), 50)                                  as ejemplo
from campos c
group by c.clave
having count(*) filter (
    where exists (select 1 from contratos ct
                  where ct.activo and upper(trim(ct.cliente)) = upper(trim(c.valor)))
  ) > 0
   or count(*) filter (
    where exists (select 1 from contratos ct
                  where ct.activo and upper(trim(ct.contrato_num)) = upper(trim(c.valor)))
  ) > 0
   or count(*) filter (
    where exists (select 1 from unidades u
                  where upper(trim(u.codigo)) = upper(trim(c.valor)))
  ) > 0
order by 4 desc, 5 desc, 6 desc;

-- El campo que quede arriba en esta lista es el que va en
--   simpliroute_config.path_contrato

-- ---------------------------------------------------------------------
-- 3. ¿Qué tan lejos cae el amarre por coordenada?
-- ---------------------------------------------------------------------
-- Plan B si no hay campo de referencia utilizable. Mide, para cada visita,
-- la distancia al contrato activo más cercano.
-- Ajusta 'latitude'/'longitude' a los nombres que haya revelado la consulta 1.
with v as (
  select
    visita_id,
    nullif(payload ->> 'latitude','')::double precision  as lat,
    nullif(payload ->> 'longitude','')::double precision as lng
  from simpliroute_visitas_ultima
),
cercano as (
  select
    v.visita_id,
    c.id as contrato_id,
    c.cliente,
    st_distance(
      st_setsrid(st_makepoint(v.lng, v.lat), 4326)::geography,
      st_setsrid(st_makepoint(c.longitud::double precision, c.latitud::double precision), 4326)::geography
    ) as metros,
    row_number() over (
      partition by v.visita_id
      order by st_distance(
        st_setsrid(st_makepoint(v.lng, v.lat), 4326)::geography,
        st_setsrid(st_makepoint(c.longitud::double precision, c.latitud::double precision), 4326)::geography
      )
    ) as rn
  from v
  join contratos c
    on c.activo and c.latitud is not null and c.longitud is not null
  where v.lat is not null and v.lng is not null
)
select
  case
    when metros <=  50 then 'a) <= 50 m   (amarre confiable)'
    when metros <= 150 then 'b) 51-150 m  (aceptable)'
    when metros <= 500 then 'c) 151-500 m (dudoso, revisar)'
    else                    'd) > 500 m   (no amarra)'
  end as rango,
  count(*) as visitas
from cercano
where rn = 1
group by 1
order by 1;

-- Si la mayoría cae en (a) o (b), el amarre por coordenada es viable.
-- Recuerda: 60 contratos activos NO tienen coordenadas, así que esos
-- nunca amarrarán por esta vía. Consulta:
--   select count(*) from contratos where activo and latitud is null;

-- ---------------------------------------------------------------------
-- 4. Campos anidados (por si la visita trae objetos, no solo texto plano)
-- ---------------------------------------------------------------------
select
  k.clave as campo_padre,
  jsonb_typeof(v.payload -> k.clave) as tipo,
  left((v.payload -> k.clave)::text, 200) as ejemplo
from simpliroute_visitas_ultima v
cross join lateral jsonb_object_keys(v.payload) as k(clave)
where jsonb_typeof(v.payload -> k.clave) in ('object','array')
limit 20;

-- ---------------------------------------------------------------------
-- 5. Estados de visita observados
-- ---------------------------------------------------------------------
-- Para llenar `valor_completado` en simpliroute_config. Ajusta el nombre del
-- campo si la consulta 1 reveló otro.
select payload ->> 'status' as estado, count(*)
from simpliroute_visitas_ultima
group by 1 order by 2 desc;
