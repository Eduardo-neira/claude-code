-- =====================================================================
-- Grupo Portátil · Flujo de facturación automática post-servicio
-- Migración 0001 — Geocercas (PostGIS), tarifas, servicios y facturas
-- =====================================================================
-- Diseñada para el Supabase existente de GP. Asume que ya existen las
-- tablas `clientes` y `contratos` (ver skill mod-operaciones-gp /
-- references/contratos.md). Esta migración agrega el módulo de
-- facturación por servicio con tarifas por geocerca y tipo de servicio.
--
-- Idempotente: usa IF NOT EXISTS / CREATE OR REPLACE donde aplica.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Extensiones
-- ---------------------------------------------------------------------
-- PostGIS habilita geometría de polígonos y point-in-polygon (ST_Contains).
create extension if not exists postgis;
create extension if not exists "uuid-ossp";

-- ---------------------------------------------------------------------
-- 1. Catálogo de tipos de servicio
-- ---------------------------------------------------------------------
-- Cada servicio facturable (limpieza, entrega, retiro, extra...) con su
-- modificador de precio. `modificador` multiplica la tarifa base:
--   1.00 = precio normal, 1.50 = servicio urgente/extra, 0.00 = sin costo.
create table if not exists tipos_servicio (
  id            uuid primary key default gen_random_uuid(),
  clave         text unique not null,          -- limpieza / entrega / retiro / bombeo_extra / inspeccion
  nombre        text not null,
  modificador   numeric(5,2) not null default 1.00,
  facturable    boolean not null default true,
  -- Claves SAT para el concepto CFDI (CFDI 4.0)
  clave_prod_serv_sat text not null default '80141600',  -- servicios de limpieza / sanitarios
  clave_unidad_sat    text not null default 'E48',        -- unidad de servicio
  creado_en     timestamptz not null default now()
);

comment on table tipos_servicio is 'Catálogo de tipos de servicio facturables y su modificador de tarifa.';

-- ---------------------------------------------------------------------
-- 2. Tarifas base por plaza / tipo de unidad / tipo de servicio
-- ---------------------------------------------------------------------
-- Precio base por UNIDAD para un servicio dado. El precio final del
-- servicio se calcula sobre esta base (ver funcion calcular_tarifa_servicio).
create table if not exists tarifas (
  id                 uuid primary key default gen_random_uuid(),
  plaza              text not null,            -- MTY / QRO
  tipo_unidad        text not null,            -- estandar / ejecutivo / discapacitados / evento
  tipo_servicio_clave text not null references tipos_servicio(clave),
  precio_unitario    numeric(10,2) not null,   -- MXN por unidad, antes de recargos e IVA
  vigente_desde      date not null default current_date,
  vigente_hasta      date,                     -- NULL = vigente
  creado_en          timestamptz not null default now(),
  unique (plaza, tipo_unidad, tipo_servicio_clave, vigente_desde)
);

comment on table tarifas is 'Tarifa base por unidad segun plaza, tipo de unidad y tipo de servicio.';
create index if not exists idx_tarifas_lookup
  on tarifas (plaza, tipo_unidad, tipo_servicio_clave, vigente_desde desc);

-- ---------------------------------------------------------------------
-- 3. Geocercas (zonas por polígono con recargo)
-- ---------------------------------------------------------------------
-- Cada geocerca es un polígono (coordenadas Google Maps, SRID 4326 =
-- WGS84 lat/lng). El recargo se aplica sobre el subtotal del servicio.
--   recargo_tipo = 'fijo'       -> suma recargo_valor MXN por servicio
--   recargo_tipo = 'porcentaje' -> suma subtotal * recargo_valor/100
--   recargo_tipo = 'ninguno'    -> zona base, sin recargo
create table if not exists geocercas (
  id            uuid primary key default gen_random_uuid(),
  nombre        text not null,                 -- "MTY Base", "Santa Catarina foránea", "QRO El Marqués"
  plaza         text not null,                 -- MTY / QRO
  poligono      geometry(Polygon, 4326) not null,
  recargo_tipo  text not null default 'ninguno'
                  check (recargo_tipo in ('ninguno','fijo','porcentaje')),
  recargo_valor numeric(10,2) not null default 0,
  prioridad     int not null default 100,      -- menor = gana si dos zonas se traslapan
  activa        boolean not null default true,
  notas         text,
  creado_en     timestamptz not null default now()
);

comment on table geocercas is 'Zonas geográficas (polígonos) con recargo de tarifa por ubicación.';
-- Índice espacial: acelera point-in-polygon.
create index if not exists idx_geocercas_poligono on geocercas using gist (poligono);
create index if not exists idx_geocercas_plaza on geocercas (plaza) where activa;

-- ---------------------------------------------------------------------
-- 4. Servicios ejecutados (fuente del disparo de facturación)
-- ---------------------------------------------------------------------
-- Un registro por servicio completado en campo (lo cierra el operador en
-- AppSheet). Al pasar a estado 'completado' con coordenada, el flujo n8n
-- lo toma y factura. `factura_id` se llena cuando ya se facturó (evita
-- doble facturación — ver índice único parcial abajo).
create table if not exists servicios (
  id                 uuid primary key default gen_random_uuid(),
  contrato_id        uuid not null references contratos(id),
  tipo_servicio_clave text not null references tipos_servicio(clave),
  cantidad_unidades  int not null default 1,
  -- Coordenada del sitio (Google Maps). lat/lng por conveniencia + punto PostGIS.
  lat                double precision,
  lng                double precision,
  ubicacion          geometry(Point, 4326)
                       generated always as (
                         case when lng is not null and lat is not null
                              then st_setsrid(st_makepoint(lng, lat), 4326)
                         end
                       ) stored,
  operador           text,                     -- Alberto / Emmanuel / Meñito / Juan Pablo
  estado             text not null default 'programado'
                       check (estado in ('programado','en_ruta','completado','facturado','cancelado')),
  completado_en      timestamptz,
  factura_id         uuid,                     -- FK lógica a facturas.id (se setea al facturar)
  origen             text default 'appsheet',  -- appsheet / manual / n8n
  notas              text,
  creado_en          timestamptz not null default now(),
  actualizado_en     timestamptz not null default now()
);

comment on table servicios is 'Servicios ejecutados en campo; disparan la facturación al completarse.';
create index if not exists idx_servicios_ubicacion on servicios using gist (ubicacion);
create index if not exists idx_servicios_contrato on servicios (contrato_id);
-- Un servicio completado se factura UNA sola vez (idempotencia del flujo).
create unique index if not exists uq_servicios_factura
  on servicios (id) where factura_id is not null;
create index if not exists idx_servicios_por_facturar
  on servicios (estado) where estado = 'completado' and factura_id is null;

-- ---------------------------------------------------------------------
-- 5. Facturas emitidas (registro CFDI / Facturama)
-- ---------------------------------------------------------------------
create table if not exists facturas (
  id                 uuid primary key default gen_random_uuid(),
  servicio_id        uuid not null references servicios(id),
  contrato_id        uuid not null references contratos(id),
  cliente_id         uuid not null references clientes(id),
  -- Desglose de precio (resultado de calcular_tarifa_servicio)
  subtotal           numeric(12,2) not null,
  recargo_zona       numeric(12,2) not null default 0,
  descuento          numeric(12,2) not null default 0,
  iva                numeric(12,2) not null,
  total              numeric(12,2) not null,
  geocerca_id        uuid references geocercas(id),
  geocerca_nombre    text,
  desglose           jsonb,                    -- breakdown completo para auditoría
  -- Datos CFDI / Facturama
  estado_cfdi        text not null default 'pendiente'
                       check (estado_cfdi in ('pendiente','timbrada','error','cancelada')),
  facturama_id       text,                     -- id que regresa Facturama
  uuid_fiscal        text,                     -- folio fiscal (UUID SAT) del CFDI timbrado
  pdf_url            text,
  xml_url            text,
  error_mensaje      text,
  creado_en          timestamptz not null default now(),
  timbrado_en        timestamptz
);

comment on table facturas is 'Facturas emitidas por servicio, con desglose y tracking del CFDI en Facturama.';
create index if not exists idx_facturas_servicio on facturas (servicio_id);
create index if not exists idx_facturas_estado on facturas (estado_cfdi);

-- FK diferida de servicios.factura_id -> facturas.id
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'fk_servicios_factura'
  ) then
    alter table servicios
      add constraint fk_servicios_factura
      foreign key (factura_id) references facturas(id);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 6. Función: resolver geocerca de una coordenada
-- ---------------------------------------------------------------------
-- Devuelve la geocerca activa de mayor prioridad (menor `prioridad`) que
-- contiene el punto, dentro de la plaza indicada. NULL si ninguna.
create or replace function resolver_geocerca(
  p_lat   double precision,
  p_lng   double precision,
  p_plaza text
)
returns geocercas
language sql
stable
as $$
  select g.*
  from geocercas g
  where g.activa
    and g.plaza = p_plaza
    and st_contains(g.poligono, st_setsrid(st_makepoint(p_lng, p_lat), 4326))
  order by g.prioridad asc
  limit 1;
$$;

comment on function resolver_geocerca is 'Geocerca activa que contiene el punto (lat,lng) en la plaza dada.';

-- ---------------------------------------------------------------------
-- 7. Función núcleo: calcular tarifa de un servicio
-- ---------------------------------------------------------------------
-- Fuente única de verdad del precio. Dado un servicio, resuelve:
--   tarifa base (plaza/unidad/tipo servicio) x cantidad x modificador
--   + recargo por geocerca
--   - descuento del contrato
--   + IVA 16%
-- Devuelve el desglose completo como JSONB para que n8n lo consuma y lo
-- guarde en facturas.desglose.
create or replace function calcular_tarifa_servicio(p_servicio_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  v_serv   servicios%rowtype;
  v_contr  contratos%rowtype;
  v_tipo   tipos_servicio%rowtype;
  v_tarifa tarifas%rowtype;
  v_geo    geocercas%rowtype;
  v_precio_unitario numeric(12,2);
  v_subtotal_base   numeric(12,2);
  v_recargo_zona    numeric(12,2) := 0;
  v_subtotal        numeric(12,2);
  v_descuento       numeric(12,2) := 0;
  v_base_gravable   numeric(12,2);
  v_iva             numeric(12,2);
  v_total           numeric(12,2);
  v_iva_tasa        numeric(4,3) := 0.16;
begin
  select * into v_serv from servicios where id = p_servicio_id;
  if not found then
    raise exception 'Servicio % no existe', p_servicio_id;
  end if;

  select * into v_contr from contratos where id = v_serv.contrato_id;
  if not found then
    raise exception 'Contrato del servicio % no existe', p_servicio_id;
  end if;

  select * into v_tipo from tipos_servicio where clave = v_serv.tipo_servicio_clave;
  if not found then
    raise exception 'Tipo de servicio % no existe', v_serv.tipo_servicio_clave;
  end if;

  -- Servicio no facturable (ej. inspección de cortesía): total 0.
  if not v_tipo.facturable then
    return jsonb_build_object(
      'facturable', false,
      'motivo', 'tipo de servicio no facturable',
      'total', 0
    );
  end if;

  -- Tarifa base vigente por plaza/unidad/tipo de servicio.
  select * into v_tarifa
  from tarifas t
  where t.plaza = v_contr.plaza
    and t.tipo_unidad = v_contr.tipo_unidad
    and t.tipo_servicio_clave = v_serv.tipo_servicio_clave
    and t.vigente_desde <= current_date
    and (t.vigente_hasta is null or t.vigente_hasta >= current_date)
  order by t.vigente_desde desc
  limit 1;

  if not found then
    raise exception 'Sin tarifa vigente para plaza=% unidad=% servicio=%',
      v_contr.plaza, v_contr.tipo_unidad, v_serv.tipo_servicio_clave;
  end if;

  -- 1) Base: precio unitario x cantidad x modificador del tipo de servicio
  v_precio_unitario := v_tarifa.precio_unitario * v_tipo.modificador;
  v_subtotal_base   := v_precio_unitario * v_serv.cantidad_unidades;

  -- 2) Recargo por geocerca (si hay coordenada)
  if v_serv.lat is not null and v_serv.lng is not null then
    select * into v_geo from resolver_geocerca(v_serv.lat, v_serv.lng, v_contr.plaza);
    if found and v_geo.recargo_tipo = 'fijo' then
      v_recargo_zona := v_geo.recargo_valor;
    elsif found and v_geo.recargo_tipo = 'porcentaje' then
      v_recargo_zona := round(v_subtotal_base * v_geo.recargo_valor / 100.0, 2);
    end if;
  end if;

  v_subtotal := v_subtotal_base + v_recargo_zona;

  -- 3) Descuento del contrato (porcentaje sobre subtotal con zona)
  if coalesce(v_contr.descuento_porcentaje, 0) > 0 then
    v_descuento := round(v_subtotal * v_contr.descuento_porcentaje / 100.0, 2);
  end if;

  -- 4) IVA 16% sobre base gravable
  v_base_gravable := v_subtotal - v_descuento;
  v_iva   := round(v_base_gravable * v_iva_tasa, 2);
  v_total := v_base_gravable + v_iva;

  return jsonb_build_object(
    'facturable', true,
    'servicio_id', v_serv.id,
    'contrato_id', v_contr.id,
    'cliente_id', v_contr.cliente_id,
    'plaza', v_contr.plaza,
    'tipo_unidad', v_contr.tipo_unidad,
    'tipo_servicio', v_serv.tipo_servicio_clave,
    'cantidad_unidades', v_serv.cantidad_unidades,
    'precio_unitario_base', v_tarifa.precio_unitario,
    'modificador_servicio', v_tipo.modificador,
    'precio_unitario_aplicado', v_precio_unitario,
    'subtotal_base', v_subtotal_base,
    'geocerca_id', case when v_geo.id is not null then v_geo.id else null end,
    'geocerca_nombre', v_geo.nombre,
    'recargo_zona', v_recargo_zona,
    'subtotal', v_subtotal,
    'descuento_porcentaje', coalesce(v_contr.descuento_porcentaje, 0),
    'descuento', v_descuento,
    'base_gravable', v_base_gravable,
    'iva_tasa', v_iva_tasa,
    'iva', v_iva,
    'total', v_total,
    'clave_prod_serv_sat', v_tipo.clave_prod_serv_sat,
    'clave_unidad_sat', v_tipo.clave_unidad_sat,
    'moneda', 'MXN'
  );
end;
$$;

comment on function calcular_tarifa_servicio is 'Fuente única de verdad del precio de un servicio (base + geocerca - descuento + IVA). Devuelve desglose JSONB.';

-- ---------------------------------------------------------------------
-- 8. Vista: servicios listos para facturar
-- ---------------------------------------------------------------------
-- El flujo n8n consulta esta vista. Solo servicios completados, con
-- coordenada, del contrato con pago confirmado (regla cobro anticipado)
-- y aún no facturados.
create or replace view servicios_por_facturar as
select
  s.id            as servicio_id,
  s.contrato_id,
  c.cliente_id,
  c.numero_contrato,
  c.plaza,
  s.tipo_servicio_clave,
  s.cantidad_unidades,
  s.lat, s.lng,
  s.completado_en,
  s.operador
from servicios s
join contratos c on c.id = s.contrato_id
where s.estado = 'completado'
  and s.factura_id is null
  and c.pago_confirmado = true          -- cobro anticipado: sin pago no se factura extra
  and c.estado = 'activo';

comment on view servicios_por_facturar is 'Servicios completados, con pago confirmado, pendientes de facturar. Fuente del flujo n8n.';

-- ---------------------------------------------------------------------
-- 9. Campos fiscales para CFDI 4.0 (sobre tablas existentes)
-- ---------------------------------------------------------------------
-- Facturama / CFDI 4.0 requiere datos fiscales del receptor que no
-- estaban en el schema base. Se agregan sin romper lo existente.
alter table clientes add column if not exists regimen_fiscal      text;  -- ej. '601', '612', '626'
alter table clientes add column if not exists uso_cfdi            text;  -- ej. 'G03', 'P01'
alter table clientes add column if not exists codigo_postal_fiscal text; -- CP del domicilio fiscal

-- Método/forma de pago por contrato (SAT). Default para servicios prepago.
alter table contratos add column if not exists forma_pago  text default '03';  -- 03 = Transferencia
alter table contratos add column if not exists metodo_pago text default 'PUE'; -- PUE = Pago en una exhibición

-- ---------------------------------------------------------------------
-- 10. Trigger: mantener actualizado_en
-- ---------------------------------------------------------------------
create or replace function _touch_actualizado_en()
returns trigger language plpgsql as $$
begin
  new.actualizado_en := now();
  return new;
end $$;

drop trigger if exists trg_servicios_touch on servicios;
create trigger trg_servicios_touch
  before update on servicios
  for each row execute function _touch_actualizado_en();
