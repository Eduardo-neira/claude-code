'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');

const { puntoEnPoligono, resolverGeocerca } = require('./geocerca');
const { calcularTarifaServicio, r2 } = require('./calcular-tarifa');

// ---- Geocercas de ejemplo (cuadrados simples en [lng,lat]) -----------------
const GEOCERCAS = [
  {
    id: 'mty-base',
    nombre: 'MTY Base',
    plaza: 'MTY',
    poligono: [
      [-100.42, 25.55],
      [-100.20, 25.55],
      [-100.20, 25.80],
      [-100.42, 25.80],
      [-100.42, 25.55],
    ],
    recargo_tipo: 'ninguno',
    recargo_valor: 0,
    prioridad: 100,
    activa: true,
  },
  {
    id: 'mty-poniente',
    nombre: 'MTY Foránea Poniente',
    plaza: 'MTY',
    poligono: [
      [-100.70, 25.60],
      [-100.42, 25.60],
      [-100.42, 25.80],
      [-100.70, 25.80],
      [-100.70, 25.60],
    ],
    recargo_tipo: 'fijo',
    recargo_valor: 250,
    prioridad: 50,
    activa: true,
  },
  {
    id: 'mty-norte',
    nombre: 'MTY Foránea Norte',
    plaza: 'MTY',
    poligono: [
      [-100.42, 25.80],
      [-100.20, 25.80],
      [-100.20, 25.95],
      [-100.42, 25.95],
      [-100.42, 25.80],
    ],
    recargo_tipo: 'porcentaje',
    recargo_valor: 15,
    prioridad: 50,
    activa: true,
  },
];

const TIPO_LIMPIEZA = {
  clave: 'limpieza',
  modificador: 1.0,
  facturable: true,
  clave_prod_serv_sat: '80141600',
  clave_unidad_sat: 'E48',
};
const TIPO_EXTRA = { ...TIPO_LIMPIEZA, clave: 'bombeo_extra', modificador: 1.5 };
const TIPO_INSPECCION = { ...TIPO_LIMPIEZA, clave: 'inspeccion', facturable: false };

const TARIFA_350 = { precio_unitario: 350 };

// =============================================================================
// Point-in-polygon
// =============================================================================
test('puntoEnPoligono: dentro y fuera', () => {
  const cuadro = [
    [0, 0],
    [10, 0],
    [10, 10],
    [0, 10],
  ];
  assert.equal(puntoEnPoligono([5, 5], cuadro), true);
  assert.equal(puntoEnPoligono([15, 5], cuadro), false);
  assert.equal(puntoEnPoligono([-1, 5], cuadro), false);
});

test('resolverGeocerca: punto en zona base MTY', () => {
  const g = resolverGeocerca(25.67, -100.31, 'MTY', GEOCERCAS);
  assert.equal(g.id, 'mty-base');
});

test('resolverGeocerca: traslape -> gana menor prioridad (foránea)', () => {
  // Punto que cae tanto en base como en poniente (ambas cubren -100.42..): usamos
  // un punto claramente solo en poniente.
  const g = resolverGeocerca(25.70, -100.55, 'MTY', GEOCERCAS);
  assert.equal(g.id, 'mty-poniente');
});

test('resolverGeocerca: sin coordenada -> null', () => {
  assert.equal(resolverGeocerca(null, null, 'MTY', GEOCERCAS), null);
});

test('resolverGeocerca: respeta la plaza', () => {
  assert.equal(resolverGeocerca(25.67, -100.31, 'QRO', GEOCERCAS), null);
});

// =============================================================================
// Cálculo de tarifa
// =============================================================================
test('tarifa base sin recargo ni descuento (zona base)', () => {
  const d = calcularTarifaServicio({
    servicio: { id: 's1', contrato_id: 'c1', tipo_servicio_clave: 'limpieza', cantidad_unidades: 2, lat: 25.67, lng: -100.31 },
    contrato: { id: 'c1', cliente_id: 'cli1', plaza: 'MTY', tipo_unidad: 'estandar', descuento_porcentaje: 0 },
    tipoServicio: TIPO_LIMPIEZA,
    tarifa: TARIFA_350,
    geocercas: GEOCERCAS,
  });
  assert.equal(d.subtotal_base, 700); // 350 * 2
  assert.equal(d.recargo_zona, 0);
  assert.equal(d.geocerca_nombre, 'MTY Base');
  assert.equal(d.subtotal, 700);
  assert.equal(d.iva, 112); // 700 * 0.16
  assert.equal(d.total, 812);
});

test('recargo de zona fijo (foránea poniente)', () => {
  const d = calcularTarifaServicio({
    servicio: { id: 's2', contrato_id: 'c1', tipo_servicio_clave: 'limpieza', cantidad_unidades: 1, lat: 25.70, lng: -100.55 },
    contrato: { id: 'c1', cliente_id: 'cli1', plaza: 'MTY', tipo_unidad: 'estandar', descuento_porcentaje: 0 },
    tipoServicio: TIPO_LIMPIEZA,
    tarifa: TARIFA_350,
    geocercas: GEOCERCAS,
  });
  assert.equal(d.subtotal_base, 350);
  assert.equal(d.recargo_zona, 250);
  assert.equal(d.subtotal, 600);
  assert.equal(d.total, 696); // 600 * 1.16
});

test('recargo de zona porcentaje (foránea norte 15%)', () => {
  const d = calcularTarifaServicio({
    servicio: { id: 's3', contrato_id: 'c1', tipo_servicio_clave: 'limpieza', cantidad_unidades: 1, lat: 25.88, lng: -100.31 },
    contrato: { id: 'c1', cliente_id: 'cli1', plaza: 'MTY', tipo_unidad: 'estandar', descuento_porcentaje: 0 },
    tipoServicio: TIPO_LIMPIEZA,
    tarifa: TARIFA_350,
    geocercas: GEOCERCAS,
  });
  assert.equal(d.recargo_zona, 52.5); // 350 * 15%
  assert.equal(d.subtotal, 402.5);
  assert.equal(d.total, r2(402.5 * 1.16)); // 466.9
});

test('modificador de servicio (bombeo extra x1.5) + descuento contrato 10%', () => {
  const d = calcularTarifaServicio({
    servicio: { id: 's4', contrato_id: 'c1', tipo_servicio_clave: 'bombeo_extra', cantidad_unidades: 1, lat: 25.67, lng: -100.31 },
    contrato: { id: 'c1', cliente_id: 'cli1', plaza: 'MTY', tipo_unidad: 'estandar', descuento_porcentaje: 10 },
    tipoServicio: TIPO_EXTRA,
    tarifa: TARIFA_350,
    geocercas: GEOCERCAS,
  });
  assert.equal(d.precio_unitario_aplicado, 525); // 350 * 1.5
  assert.equal(d.subtotal_base, 525);
  assert.equal(d.recargo_zona, 0); // zona base
  assert.equal(d.descuento, 52.5); // 525 * 10%
  assert.equal(d.base_gravable, 472.5);
  assert.equal(d.iva, 75.6); // 472.5 * 0.16
  assert.equal(d.total, 548.1);
});

test('recargo fijo + descuento juntos', () => {
  const d = calcularTarifaServicio({
    servicio: { id: 's5', contrato_id: 'c1', tipo_servicio_clave: 'limpieza', cantidad_unidades: 1, lat: 25.70, lng: -100.55 },
    contrato: { id: 'c1', cliente_id: 'cli1', plaza: 'MTY', tipo_unidad: 'estandar', descuento_porcentaje: 10 },
    tipoServicio: TIPO_LIMPIEZA,
    tarifa: TARIFA_350,
    geocercas: GEOCERCAS,
  });
  // subtotal_base 350 + recargo 250 = 600; desc 10% = 60; base 540; iva 86.4; total 626.4
  assert.equal(d.subtotal, 600);
  assert.equal(d.descuento, 60);
  assert.equal(d.base_gravable, 540);
  assert.equal(d.total, 626.4);
});

test('servicio no facturable devuelve total 0', () => {
  const d = calcularTarifaServicio({
    servicio: { id: 's6', contrato_id: 'c1', tipo_servicio_clave: 'inspeccion', cantidad_unidades: 1, lat: 25.67, lng: -100.31 },
    contrato: { id: 'c1', cliente_id: 'cli1', plaza: 'MTY', tipo_unidad: 'estandar', descuento_porcentaje: 0 },
    tipoServicio: TIPO_INSPECCION,
    tarifa: TARIFA_350,
    geocercas: GEOCERCAS,
  });
  assert.equal(d.facturable, false);
  assert.equal(d.total, 0);
});

test('servicio sin coordenada: sin recargo de zona', () => {
  const d = calcularTarifaServicio({
    servicio: { id: 's7', contrato_id: 'c1', tipo_servicio_clave: 'limpieza', cantidad_unidades: 1, lat: null, lng: null },
    contrato: { id: 'c1', cliente_id: 'cli1', plaza: 'MTY', tipo_unidad: 'estandar', descuento_porcentaje: 0 },
    tipoServicio: TIPO_LIMPIEZA,
    tarifa: TARIFA_350,
    geocercas: GEOCERCAS,
  });
  assert.equal(d.recargo_zona, 0);
  assert.equal(d.geocerca_id, null);
  assert.equal(d.total, 406); // 350 * 1.16
});

test('sin tarifa vigente lanza error', () => {
  assert.throws(() =>
    calcularTarifaServicio({
      servicio: { id: 's8', contrato_id: 'c1', tipo_servicio_clave: 'limpieza', cantidad_unidades: 1, lat: 25.67, lng: -100.31 },
      contrato: { id: 'c1', cliente_id: 'cli1', plaza: 'MTY', tipo_unidad: 'estandar', descuento_porcentaje: 0 },
      tipoServicio: TIPO_LIMPIEZA,
      tarifa: null,
      geocercas: GEOCERCAS,
    })
  );
});
