-- =====================================================================
-- Grupo Portátil · Puente SimpliRoute → Supabase
-- 0005_correcciones_9_dias.sql — Lo que solo se vio con más datos
-- =====================================================================
-- APLICADA a gp-inventario el 2026-08-26, tras 9 días de ingesta
-- (1,116 visitas contra las 123 del primer día).
--
-- Tres defectos que con un solo día no se manifestaban, y uno de razonamiento.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. PostGIS no estaba en el search_path  (defecto propio, silencioso)
-- ---------------------------------------------------------------------
-- PostGIS está instalado en el esquema `extensions`, no en `public`. Al fijar
-- `search_path = public, pg_temp` en simpliroute_amarrar() —correcto por
-- seguridad— quedó fuera y el tipo `geography` dejó de resolverse.
--
-- Efecto real: la rama 3 del amarre (por coordenada) NUNCA pudo ejecutarse.
-- No se detectó con un día porque todas las visitas amarraban antes de
-- llegar ahí. Con 9 días aparecieron visitas que sí la alcanzan y la
-- promoción tronó con "type geography does not exist".
alter function simpliroute_amarrar(jsonb) set search_path = public, extensions, pg_temp;

-- ---------------------------------------------------------------------
-- 2. Unidad con más de una colocación activa
-- ---------------------------------------------------------------------
-- Hay unidades con DOS colocaciones activas a la vez, lo que es imposible:
--   807 -> TEITER (2025-03-21) y TREVA (2025-12-08)
--   863 -> dos contratos del MISMO cliente, misma fecha (contrato duplicado)
--
-- El amarre devolvía dos filas con la misma (visita, unidad) y la promoción
-- fallaba con "ON CONFLICT DO UPDATE cannot affect row a second time".
--
-- La corrección NO es elegir un contrato — sería facturarle a quien no es.
-- Se marca la unidad como ambigua y no se promueve: la regla del puente
-- desde el principio es que sin amarre claro, va a revisión.
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
  -- Una fila por UNIDAD (no por colocación), para que una unidad con
  -- colocaciones duplicadas no genere filas en conflicto.
  return query
    with base as (
      select cu.contrato_id, u.id as uid, u.numero, c.cliente
      from sr_unidades(v_ref) n
      join unidades u           on trim(u.numero) = n.numero
      join contrato_unidades cu on cu.unidad_id = u.id and cu.fecha_retiro is null
      join contratos c          on c.id = cu.contrato_id
    ),
    agg as (
      select b.uid, min(b.numero) as numero,
             count(distinct b.contrato_id) as n_contratos,
             min(b.contrato_id) as contrato_id,
             bool_or(gp_norm(b.cliente) = gp_norm(v_title)) as coincide_titulo
      from base b group by b.uid
    )
    select
      case when a.n_contratos = 1 then a.contrato_id end,
      a.uid, a.numero,
      case when a.n_contratos = 1 then 'referencia:unidad'
           else 'ambiguo:unidad_en_' || a.n_contratos || '_contratos' end,
      case when a.n_contratos > 1 then 'nula'
           when a.coincide_titulo  then 'alta'
           else 'media' end
    from agg a;
  get diagnostics v_n = row_count;
  if v_n > 0 then return; end if;

  return query
    select c.id, null::integer, null::text, 'nombre:cliente'::text, 'media'::text
    from contratos c
    where c.activo and gp_norm(c.cliente) = gp_norm(v_title)
      and (select count(*) from contratos c2
           where c2.activo and gp_norm(c2.cliente) = gp_norm(v_title)) = 1;
  get diagnostics v_n = row_count;
  if v_n > 0 then return; end if;

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

  return query select null::integer, null::integer, null::text,
                      'sin_amarre'::text, 'nula'::text;
end;
$$;
alter function simpliroute_amarrar(jsonb) set search_path = public, extensions, pg_temp;

create or replace view gp_unidades_en_dos_contratos as
select u.numero, u.estatus, u.propietario,
       count(*) as colocaciones_activas,
       string_agg(distinct c.cliente, ' | ' order by c.cliente) as clientes,
       string_agg(cu.contrato_id || ' (' || cu.fecha_colocacion || ')', ', '
                  order by cu.fecha_colocacion) as contratos
from unidades u
join contrato_unidades cu on cu.unidad_id = u.id and cu.fecha_retiro is null
join contratos c on c.id = cu.contrato_id
group by u.id, u.numero, u.estatus, u.propietario
having count(*) > 1
order by u.numero;
alter view gp_unidades_en_dos_contratos set (security_invoker = on);
revoke all on gp_unidades_en_dos_contratos from anon, authenticated;

comment on view gp_unidades_en_dos_contratos is
  'Unidades con más de una colocación activa. Imposible físicamente: alguien no cerró la anterior, o el contrato está duplicado.';

-- ---------------------------------------------------------------------
-- 3. Exclusiones que la redacción real burlaba
-- ---------------------------------------------------------------------
-- Los operadores escriben el título distinto cada vez:
--   'TRÁNSITO' con acento    contra el patrón 'TRANSITO'
--   'ESTACION GAS'           contra 'ESTACION DE GAS'
--   'CHECKLIST MANTENIMIENTO' contra 'CHECK LIST'
--   'EMERGENTE'              contra 'PUNTO EMERGENTE'
-- más categorías nuevas: 'REVISION DE ...', 'COBRANZA ...',
-- 'ENTREGA E INSTALACION DE FOSA DE ...'.
--
-- La comparación pasa a hacerse sobre gp_norm(), que quita acentos y
-- puntuación. Verificado ANTES de aplicar: los 19 títulos que caen bajo
-- estos patrones tienen CERO contratos activos, así que no se excluye
-- ningún cliente real.
insert into simpliroute_exclusiones (patron, motivo) values
  ('ESTACION GAS',        'parada_operativa'),
  ('INICIO GAS',          'parada_operativa'),
  ('FINAL GAS',           'parada_operativa'),
  ('EMERGENTE',           'parada_operativa'),
  ('CHECKLIST',           'parada_operativa'),
  ('REVISION DE ',        'visita_no_facturable'),
  ('COBRANZA ',           'visita_no_facturable'),
  ('INSTALACION DE FOSA', 'fosa')
on conflict (patron) do nothing;

create or replace function sr_clasificar(p_payload jsonb)
returns text language sql stable as $$
  select case
    when exists (select 1 from simpliroute_exclusiones e
                 where e.activo
                   and gp_norm(p_payload ->> 'title') like '%' || e.patron || '%')
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

-- ---------------------------------------------------------------------
-- 4. Corrección de razonamiento sobre `gp_colocaciones_discrepantes`
-- ---------------------------------------------------------------------
-- En la vuelta del 2026-08-19 se trató `contratos.num_sanitario` como una
-- SEGUNDA fuente independiente de `contrato_unidades`, y se usó su acuerdo
-- para arbitrar los conflictos de colocación.
--
-- ES FALSO. Las 192 colocaciones originales tienen notas
-- 'backfill desde contratos.num_sanitario' y fecha 2026-08-12: una fue
-- derivada de la otra. Que coincidan no prueba nada — es la misma fuente
-- dos veces. Por eso esta vista da 0 filas: no es que el problema se haya
-- resuelto, es que compara un dato consigo mismo.
--
-- La única fuente genuinamente independiente es SimpliRoute. La verificación
-- por distancia contra `contratos.direccion_obra` sí es válida y es la que
-- sostiene los dos casos confirmados (1085 a 28 km, 869 a 24 km).
comment on view gp_colocaciones_discrepantes is
  'OJO: contrato_unidades fue backfilleada desde num_sanitario el 2026-08-12, así que estas dos "fuentes" son la misma. Esta vista da 0 por construcción, no porque no haya problemas. No usarla para arbitrar.';
