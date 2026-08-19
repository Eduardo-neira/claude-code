-- =====================================================================
-- Grupo Portátil · Puente SimpliRoute → Supabase
-- 02_descubrimiento.sql — Aprender el schema de la API con datos reales
-- =====================================================================
-- CORRIDO el 2026-08-19 sobre 123 visitas reales del 2026-08-18.
-- Los resultados están en ../HALLAZGOS.md y ya se aplicaron en las
-- migraciones 0002-0006. Este archivo se conserva para repetir el
-- diagnóstico cuando cambie algo en SimpliRoute.
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
-- 1. Qué campos trae realmente una visita
-- ---------------------------------------------------------------------
-- Sustituye a la documentación. Devuelve cada campo de primer nivel, cuántas
-- visitas lo traen, su tipo y un valor de ejemplo.
--
-- OJO: no usar max(payload -> clave) para sacar el tipo — no existe max(jsonb)
-- y la consulta falla. Se agregan los tipos observados como texto.
select
  k.clave,
  count(*)                                                     as apariciones,
  count(*) filter (where v.payload -> k.clave = 'null'::jsonb)  as nulos,
  string_agg(distinct jsonb_typeof(v.payload -> k.clave), '/')  as tipo,
  left(max(v.payload ->> k.clave), 60)                          as ejemplo
from simpliroute_visitas_ultima v
cross join lateral jsonb_object_keys(v.payload) as k(clave)
group by k.clave
order by apariciones desc, k.clave;

-- Resultado 2026-08-19: 59 campos. Los que importan:
--   reference          -> números de sanitario: "#774", "#1058#769#809 Y 2 LAVAMANOS #406#425"
--   title              -> razón social del cliente
--   notes              -> CANTIDAD de unidades, o BAJA / ENTREGA
--   status             -> completed (112) / failed (7) / pending (4)
--   checkout_time / checkout_latitude / checkout_longitude
--   latitude / longitude, route (uuid), driver, vehicle, tracking_id
-- Nulos en las 123: order_id, visit_type, window_*, fleet, seller, load,
--   programmed_date, priority_level, edition_status, geocode_alert, current_eta

-- ---------------------------------------------------------------------
-- 2. Candidatos a campo de AMARRE
-- ---------------------------------------------------------------------
with campos as (
  select v.visita_id, k.clave, v.payload ->> k.clave as valor
  from simpliroute_visitas_ultima v
  cross join lateral jsonb_object_keys(v.payload) as k(clave)
  where jsonb_typeof(v.payload -> k.clave) = 'string'
    and coalesce(v.payload ->> k.clave, '') <> ''
)
select
  c.clave,
  count(*)                as visitas_con_valor,
  count(distinct c.valor) as valores_distintos,
  count(*) filter (
    where exists (select 1 from contratos ct
                  where ct.activo and upper(trim(ct.cliente)) = upper(trim(c.valor)))
  )                       as match_cliente_exacto,
  count(*) filter (
    where exists (select 1 from unidades u
                  where upper(trim(u.codigo)) = upper(trim(c.valor)))
  )                       as match_codigo_unidad,
  left(max(c.valor), 50)  as ejemplo
from campos c
group by c.clave
order by 4 desc, 5 desc, 2 desc;

-- Resultado: NINGÚN campo trae el contrato directo.
--   title  -> coincide exacto con contratos.cliente en 39/123 (68 al normalizar)
--   reference -> trae los NÚMEROS DE SANITARIO, que es el amarre bueno:
--                reference -> unidades.numero -> contrato_unidades -> contrato
--   notes  -> es la cantidad, NO un id (parecía match por ser numérico)

-- ---------------------------------------------------------------------
-- 3. ¿Sirve el amarre por coordenada?
-- ---------------------------------------------------------------------
with v as (
  select visita_id,
         nullif(payload ->> 'checkout_latitude','')::float8  as lat,
         nullif(payload ->> 'checkout_longitude','')::float8 as lng
  from simpliroute_visitas_ultima
),
cercano as (
  select v.visita_id, c.id as contrato_id, c.metros
  from v cross join lateral (
    select ct.id,
           st_distance(
             st_setsrid(st_makepoint(v.lng, v.lat), 4326)::geography,
             st_setsrid(st_makepoint(ct.longitud::float8, ct.latitud::float8), 4326)::geography
           ) as metros
    from contratos ct
    where ct.activo and ct.latitud is not null and ct.longitud is not null
    order by st_setsrid(st_makepoint(v.lng, v.lat), 4326)::geography <->
             st_setsrid(st_makepoint(ct.longitud::float8, ct.latitud::float8), 4326)::geography
    limit 1) c
  where v.lat is not null and v.lng is not null
)
select
  case when metros <=  50 then 'a) <= 50 m   (confiable)'
       when metros <= 150 then 'b) 51-150 m  (aceptable)'
       when metros <= 500 then 'c) 151-500 m (dudoso)'
       else                    'd) > 500 m   (no amarra)' end as rango,
  count(*) as visitas
from cercano group by 1 order by 1;

-- Resultado: solo 4 de 123 caen dentro de 150 m. El amarre por coordenada
-- NO es viable como método principal — quedó como último recurso.
-- Causa: 60 contratos activos no tienen coordenada capturada.

-- ---------------------------------------------------------------------
-- 4. Estados de visita observados
-- ---------------------------------------------------------------------
select payload ->> 'status' as estado, count(*) as visitas,
       count(*) filter (where payload ->> 'checkout_time' is not null) as con_checkout
from simpliroute_visitas_ultima
group by 1 order by 2 desc;

-- Resultado: completed 112 / failed 7 / pending 4.
-- checkout_time existe exactamente cuando el estado no es pending.
-- Por eso valor_completado = 'completed' (verificado, no supuesto).
