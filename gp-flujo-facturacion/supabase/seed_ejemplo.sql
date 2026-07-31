-- =====================================================================
-- Grupo Portátil · Seed de EJEMPLO para el módulo de facturación
-- =====================================================================
-- Valores ilustrativos. Eduardo debe ajustar precios reales y los
-- polígonos de geocerca con las coordenadas reales de cada zona.
-- Los polígonos van en formato lng lat (orden PostGIS/GeoJSON), SRID 4326.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tipos de servicio
-- ---------------------------------------------------------------------
insert into tipos_servicio (clave, nombre, modificador, facturable, clave_prod_serv_sat, clave_unidad_sat)
values
  ('limpieza',     'Limpieza / bombeo periódico', 1.00, true,  '80141600', 'E48'),
  ('entrega',      'Entrega de unidad',           1.00, true,  '78101800', 'E48'),
  ('retiro',       'Retiro de unidad',            1.00, true,  '78101800', 'E48'),
  ('bombeo_extra', 'Bombeo / limpieza extra urgente', 1.50, true, '80141600', 'E48'),
  ('inspeccion',   'Inspección de cortesía',      0.00, false, '80141600', 'E48')
on conflict (clave) do nothing;

-- ---------------------------------------------------------------------
-- Tarifas base (MXN por unidad, antes de recargos e IVA) — EJEMPLO
-- ---------------------------------------------------------------------
insert into tarifas (plaza, tipo_unidad, tipo_servicio_clave, precio_unitario)
values
  -- Monterrey
  ('MTY', 'estandar',       'limpieza', 350.00),
  ('MTY', 'estandar',       'entrega',  600.00),
  ('MTY', 'estandar',       'retiro',   500.00),
  ('MTY', 'estandar',       'bombeo_extra', 350.00),
  ('MTY', 'ejecutivo',      'limpieza', 500.00),
  ('MTY', 'ejecutivo',      'entrega',  800.00),
  ('MTY', 'ejecutivo',      'retiro',   700.00),
  ('MTY', 'ejecutivo',      'bombeo_extra', 500.00),
  ('MTY', 'discapacitados', 'limpieza', 450.00),
  ('MTY', 'discapacitados', 'entrega',  700.00),
  ('MTY', 'discapacitados', 'retiro',   600.00),
  ('MTY', 'discapacitados', 'bombeo_extra', 450.00),
  -- Querétaro
  ('QRO', 'estandar',       'limpieza', 380.00),
  ('QRO', 'estandar',       'entrega',  650.00),
  ('QRO', 'estandar',       'retiro',   550.00),
  ('QRO', 'estandar',       'bombeo_extra', 380.00),
  ('QRO', 'ejecutivo',      'limpieza', 540.00),
  ('QRO', 'ejecutivo',      'entrega',  860.00),
  ('QRO', 'ejecutivo',      'retiro',   740.00),
  ('QRO', 'ejecutivo',      'bombeo_extra', 540.00)
on conflict (plaza, tipo_unidad, tipo_servicio_clave, vigente_desde) do nothing;

-- ---------------------------------------------------------------------
-- Geocercas (polígonos EJEMPLO — reemplazar con coordenadas reales)
-- ---------------------------------------------------------------------
-- Recuerda: ST_GeomFromText usa 'POLYGON((lng lat, lng lat, ... , lng lat))'
-- y el anillo debe CERRAR (primer punto == último punto).

-- MTY zona base (área metropolitana centro) — sin recargo
insert into geocercas (nombre, plaza, poligono, recargo_tipo, recargo_valor, prioridad, notas)
values (
  'MTY Base — Área Metropolitana', 'MTY',
  st_geomfromtext('POLYGON((-100.42 25.55, -100.20 25.55, -100.20 25.80, -100.42 25.80, -100.42 25.55))', 4326),
  'ninguno', 0, 100, 'Zona base sin recargo (ejemplo, ajustar polígono).'
)
on conflict do nothing;

-- MTY zona foránea (Santa Catarina / García hacia el poniente) — recargo fijo
insert into geocercas (nombre, plaza, poligono, recargo_tipo, recargo_valor, prioridad, notas)
values (
  'MTY Foránea Poniente — Santa Catarina/García', 'MTY',
  st_geomfromtext('POLYGON((-100.70 25.60, -100.42 25.60, -100.42 25.80, -100.70 25.80, -100.70 25.60))', 4326),
  'fijo', 250.00, 50, 'Recargo por traslado foráneo poniente (ejemplo).'
)
on conflict do nothing;

-- MTY zona foránea norte (Escobedo / El Carmen) — recargo porcentaje
insert into geocercas (nombre, plaza, poligono, recargo_tipo, recargo_valor, prioridad, notas)
values (
  'MTY Foránea Norte — Escobedo/El Carmen', 'MTY',
  st_geomfromtext('POLYGON((-100.42 25.80, -100.20 25.80, -100.20 25.95, -100.42 25.95, -100.42 25.80))', 4326),
  'porcentaje', 15.00, 50, 'Recargo 15% por traslado foráneo norte (ejemplo).'
)
on conflict do nothing;

-- QRO zona base (ciudad) — sin recargo
insert into geocercas (nombre, plaza, poligono, recargo_tipo, recargo_valor, prioridad, notas)
values (
  'QRO Base — Ciudad', 'QRO',
  st_geomfromtext('POLYGON((-100.45 20.53, -100.34 20.53, -100.34 20.65, -100.45 20.65, -100.45 20.53))', 4326),
  'ninguno', 0, 100, 'Zona base QRO (ejemplo).'
)
on conflict do nothing;

-- QRO El Marqués (parque industrial) — recargo fijo por acceso/distancia
insert into geocercas (nombre, plaza, poligono, recargo_tipo, recargo_valor, prioridad, notas)
values (
  'QRO El Marqués — Parque Industrial', 'QRO',
  st_geomfromtext('POLYGON((-100.34 20.55, -100.22 20.55, -100.22 20.70, -100.34 20.70, -100.34 20.55))', 4326),
  'fijo', 300.00, 50, 'Recargo por El Marqués (ejemplo, coordinar con Juan Pablo).'
)
on conflict do nothing;
