-- =====================================================================
-- Grupo Portátil · Puente SimpliRoute → Supabase
-- 0004_conciliacion_catalogo.sql — Cerrar los huecos del catálogo
-- =====================================================================
-- APLICADA a gp-inventario el 2026-08-19, en cuatro migraciones:
--   gp_numeros_unidad · alta_lavamanos ·
--   vistas_conciliacion_catalogo · confianza_cambios_de_unidad
--
-- Hallazgo que ordenó todo esto: `contratos.num_sanitario` es una SEGUNDA
-- fuente de qué unidad tiene cada contrato — independiente de
-- `contrato_unidades`, con mejor cobertura (193 de 194 contratos activos) y
-- escrita en el MISMO estilo que la referencia de SimpliRoute. Con dos
-- fuentes internas más SimpliRoute se puede arbitrar en vez de suponer.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Parser de números de unidad
-- ---------------------------------------------------------------------
-- Tanto `contratos.num_sanitario` como la `reference` de SimpliRoute son texto
-- libre con el mismo desorden: "#1058#769#809 Y 2 LAVAMANOS #406#425",
-- "3 BAÑOS 1034,1035,1036 Y 1 LAVAMANOS 428 DE SU PROPIEDAD", y corridas
-- pegadas sin separador como "862819736880" (= 862, 819, 736, 880).
--
-- Se parte primero en corridas de dígitos RESPETANDO los separadores, y solo
-- las corridas largas se tokenizan por rango. Concatenar todo antes de
-- tokenizar es un error: "3 BAÑOS 1034,..." se vuelve "31034..." y sale un
-- "310" que no existe, comiéndose el 3 de la cantidad.
--
-- Rangos reales: sanitarios 700-1136, lavamanos 300-499.
-- Corridas de 1-2 dígitos son cantidades ("3 BAÑOS"), no números de unidad.
create or replace function gp_numeros_unidad(p_texto text)
returns table (numero text)
language sql immutable as $$
  with corridas as (
    select m[1] as run from regexp_matches(coalesce(p_texto,''), '([0-9]+)', 'g') m
  )
  select distinct t.n
  from corridas
  cross join lateral (
    select corridas.run as n where length(corridas.run) between 3 and 4
    union all
    select tok[1]
    from regexp_matches(corridas.run, '(1[01][0-9][0-9]|[789][0-9][0-9]|[34][0-9][0-9])', 'g') tok
    where length(corridas.run) > 4
  ) t
  where t.n is not null;
$$;
alter function gp_numeros_unidad(text) set search_path = public, pg_temp;

-- Verificado contra los 10 casos difíciles reales del catálogo. Notablemente:
--   '3 BAÑOS 1034,1035,1036  Y 1 LAVAMANOS 428 DE SU PROPIEDAD' -> 1034,1035,1036,428
--   '101310301032 1 LAVAMANOS 427'                             -> 1013,1030,1032,427
--   '862819736880'                                             -> 736,819,862,880
--   '1 BAÑO ESTANDAR'                                          -> (nada)
-- Extrae 195 números de los contratos activos y los 195 existen en `unidades`.

-- ---------------------------------------------------------------------
-- 2. Alta de lavamanos
-- ---------------------------------------------------------------------
-- `unidades` solo tenía números >= 700 (sanitarios). Los lavamanos, que GP
-- renta y factura (`contratos.precio_lavamanos` = 2500), no existían como
-- unidad ni había categoría para ellos.
--
-- NO se da de alta el 302: aparece solo en SimpliRoute, para SLYRSA, que en
-- el contrato 115 tiene el 402. Es probable error de dedo de uno de los dos
-- sistemas; crear ambos inventaría una unidad. Queda para revisión humana.
--
-- El propietario se infiere de datos, no se supone:
--   'DE SU PROPIEDAD' en el contrato -> CLIENTE
--   precio_lavamanos > 0             -> GP
insert into unidades (numero, codigo, categoria, estatus, propietario, sucursal_id)
select v.numero, 'MTY-' || lpad(v.numero, 4, '0'), 'LAVAMANOS', 'EN_CAMPO', v.propietario, 1
from (values
  ('402','GP'),      -- contrato 115 · SLYRSA
  ('406','GP'),      -- contrato 126 · SLYRSA   (confirmado por SimpliRoute)
  ('420','GP'),      -- contrato  96 · CARVID   (el contrato marca tiene_lavamanos sin número)
  ('421','GP'),      -- contrato 139 · GRUPO MYTE
  ('424','GP'),      -- contrato  70 · FRIOCAL
  ('425','GP'),      -- contrato 127 · SLYRSA   (confirmado por SimpliRoute)
  ('427','GP'),      -- contrato 194 · SOLUMAX
  ('428','CLIENTE')  -- contrato  58 · SOLUMAX 'DE SU PROPIEDAD' (confirmado por SimpliRoute)
) as v(numero, propietario)
where not exists (select 1 from unidades u where trim(u.numero) = v.numero);

insert into contrato_unidades (contrato_id, unidad_id, fecha_colocacion, notas)
select v.contrato_id, u.id, current_date,
       'Alta 2026-08-19: lavamanos detectado por el puente SimpliRoute. Fecha de colocación real desconocida.'
from (values
  (115,'402'), (126,'406'), (96,'420'), (139,'421'),
  (70,'424'),  (127,'425'), (194,'427'), (58,'428')
) as v(contrato_id, numero)
join unidades u on trim(u.numero) = v.numero
where not exists (
  select 1 from contrato_unidades cu where cu.unidad_id = u.id and cu.fecha_retiro is null);

-- ---------------------------------------------------------------------
-- 3. Vistas de conciliación
-- ---------------------------------------------------------------------
create or replace view gp_contrato_unidad_declarada as
select c.id as contrato_id, c.cliente, c.activo, n.numero,
       u.id as unidad_id, u.categoria, u.estatus
from contratos c
cross join lateral gp_numeros_unidad(c.num_sanitario) n
left join unidades u on trim(u.numero) = n.numero;
alter view gp_contrato_unidad_declarada set (security_invoker = on);

-- Dónde las DOS fuentes internas de GP no coinciden entre sí.
create or replace view gp_colocaciones_discrepantes as
select d.contrato_id, d.cliente, d.numero as dice_el_contrato,
       u2.numero as dice_contrato_unidades, cu.fecha_colocacion
from gp_contrato_unidad_declarada d
left join contrato_unidades cu on cu.contrato_id = d.contrato_id and cu.fecha_retiro is null
left join unidades u2 on u2.id = cu.unidad_id
where d.activo and cu.id is not null
  and not exists (
    select 1 from contrato_unidades cu2
    join unidades ux on ux.id = cu2.unidad_id
    where cu2.contrato_id = d.contrato_id and cu2.fecha_retiro is null
      and trim(ux.numero) = d.numero)
order by d.contrato_id;
alter view gp_colocaciones_discrepantes set (security_invoker = on);

-- Cambios de unidad no registrados.
--
-- Esta vista CLASIFICA en vez de afirmar, y la razón importa: con pocos días
-- de datos "la unidad registrada no se sirvió hoy" es lo NORMAL, no un
-- hallazgo — LC INFRAESTRUCTURA tiene 8 obras, la mitad en banda LMV y la
-- otra en MJS. Solo es concluyente cuando el cliente tiene UNA unidad
-- registrada y se sirvió UNA distinta: ahí no hay explicación de banda.
--
-- (Una versión anterior de esta vista daba 123 filas de ruido por hacer
-- producto cartesiano entre unidades registradas y servidas del mismo
-- cliente. Quedó anotado para no repetirlo.)
create or replace view gp_cambios_de_unidad_no_registrados as
with dias as (select count(distinct fecha_planeada) as n from simpliroute_visitas_ultima),
servidas as (
  select distinct n.numero, gp_norm(v.payload->>'title') as cliente_norm
  from simpliroute_visitas_ultima v
  cross join lateral gp_numeros_unidad(v.payload->>'reference') n
  where sr_clasificar(v.payload) = 'sanitario'
),
registradas as (
  select distinct d.contrato_id, d.cliente, gp_norm(d.cliente) as cliente_norm, d.numero, d.estatus
  from gp_contrato_unidad_declarada d where d.activo
),
conteos as (
  select r.cliente_norm, count(distinct r.numero) as n_registradas,
         (select count(distinct s.numero) from servidas s where s.cliente_norm = r.cliente_norm) as n_servidas
  from registradas r group by r.cliente_norm
)
select r.contrato_id, r.cliente, r.numero as unidad_registrada, r.estatus as estatus_registrada,
  (select string_agg(s.numero, ', ' order by s.numero)
     from servidas s where s.cliente_norm = r.cliente_norm) as unidades_servidas_ahi,
  case when k.n_registradas = 1 and k.n_servidas = 1
       then 'alta · cambio de unidad, sin otra explicación'
       else 'baja · el cliente tiene ' || k.n_registradas ||
            ' unidades en ' || k.n_registradas || ' obras; puede ser banda LMV/MJS' end as confianza,
  (select n from dias) as dias_de_datos
from registradas r
join conteos k on k.cliente_norm = r.cliente_norm
where exists (select 1 from servidas s  where s.cliente_norm = r.cliente_norm)
  and not exists (select 1 from servidas s2 where s2.numero = r.numero)
order by (k.n_registradas = 1 and k.n_servidas = 1) desc, r.cliente, r.numero;
alter view gp_cambios_de_unidad_no_registrados set (security_invoker = on);

revoke all on gp_contrato_unidad_declarada        from anon, authenticated;
revoke all on gp_colocaciones_discrepantes        from anon, authenticated;
revoke all on gp_cambios_de_unidad_no_registrados from anon, authenticated;
