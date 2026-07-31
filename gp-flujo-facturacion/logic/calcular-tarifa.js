'use strict';

/**
 * Cálculo de tarifa por servicio · Grupo Portátil
 * -----------------------------------------------------------------------------
 * Implementación de referencia (espejo de la función SQL
 * `calcular_tarifa_servicio`). Sirve para:
 *   - pruebas unitarias sin base de datos,
 *   - un Code node de n8n cuando se prefiere calcular fuera de Postgres,
 *   - validar que la lógica SQL y la de aplicación no diverjan.
 *
 * Fórmula:
 *   precio_unitario_aplicado = precio_unitario_base * modificador_servicio
 *   subtotal_base            = precio_unitario_aplicado * cantidad_unidades
 *   recargo_zona             = fijo | subtotal_base * pct/100 | 0
 *   subtotal                 = subtotal_base + recargo_zona
 *   descuento                = subtotal * descuento_contrato/100
 *   base_gravable            = subtotal - descuento
 *   iva                      = base_gravable * 0.16
 *   total                    = base_gravable + iva
 */

const { resolverGeocerca } = require('./geocerca');

const IVA_TASA = 0.16;

/** Redondeo a 2 decimales estable (evita 350.00000000000006). */
function r2(n) {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

/**
 * @param {Object} args
 * @param {Object} args.servicio  {id, contrato_id, tipo_servicio_clave, cantidad_unidades, lat, lng}
 * @param {Object} args.contrato  {id, cliente_id, plaza, tipo_unidad, descuento_porcentaje}
 * @param {Object} args.tipoServicio  {clave, modificador, facturable, clave_prod_serv_sat, clave_unidad_sat}
 * @param {Object} args.tarifa    {precio_unitario}  tarifa base vigente
 * @param {Array}  [args.geocercas]  catálogo de geocercas para resolver recargo
 * @returns {Object} desglose (misma forma que el JSONB de la función SQL)
 */
function calcularTarifaServicio({ servicio, contrato, tipoServicio, tarifa, geocercas = [] }) {
  if (!tipoServicio) throw new Error('tipoServicio requerido');
  if (!tipoServicio.facturable) {
    return { facturable: false, motivo: 'tipo de servicio no facturable', total: 0 };
  }
  if (!tarifa || tarifa.precio_unitario == null) {
    throw new Error(
      `Sin tarifa vigente para plaza=${contrato.plaza} unidad=${contrato.tipo_unidad} servicio=${servicio.tipo_servicio_clave}`
    );
  }

  const cantidad = servicio.cantidad_unidades ?? 1;
  const modificador = tipoServicio.modificador ?? 1;

  const precioUnitarioAplicado = r2(tarifa.precio_unitario * modificador);
  const subtotalBase = r2(precioUnitarioAplicado * cantidad);

  // Recargo por geocerca
  let recargoZona = 0;
  let geo = null;
  if (servicio.lat != null && servicio.lng != null) {
    geo = resolverGeocerca(servicio.lat, servicio.lng, contrato.plaza, geocercas);
    if (geo) {
      if (geo.recargo_tipo === 'fijo') {
        recargoZona = r2(geo.recargo_valor);
      } else if (geo.recargo_tipo === 'porcentaje') {
        recargoZona = r2((subtotalBase * geo.recargo_valor) / 100);
      }
    }
  }

  const subtotal = r2(subtotalBase + recargoZona);

  // Descuento del contrato
  const descPct = contrato.descuento_porcentaje ?? 0;
  const descuento = descPct > 0 ? r2((subtotal * descPct) / 100) : 0;

  const baseGravable = r2(subtotal - descuento);
  const iva = r2(baseGravable * IVA_TASA);
  const total = r2(baseGravable + iva);

  return {
    facturable: true,
    servicio_id: servicio.id,
    contrato_id: contrato.id,
    cliente_id: contrato.cliente_id,
    plaza: contrato.plaza,
    tipo_unidad: contrato.tipo_unidad,
    tipo_servicio: servicio.tipo_servicio_clave,
    cantidad_unidades: cantidad,
    precio_unitario_base: tarifa.precio_unitario,
    modificador_servicio: modificador,
    precio_unitario_aplicado: precioUnitarioAplicado,
    subtotal_base: subtotalBase,
    geocerca_id: geo ? geo.id : null,
    geocerca_nombre: geo ? geo.nombre : null,
    recargo_zona: recargoZona,
    subtotal,
    descuento_porcentaje: descPct,
    descuento,
    base_gravable: baseGravable,
    iva_tasa: IVA_TASA,
    iva,
    total,
    clave_prod_serv_sat: tipoServicio.clave_prod_serv_sat,
    clave_unidad_sat: tipoServicio.clave_unidad_sat,
    moneda: 'MXN',
  };
}

module.exports = { calcularTarifaServicio, r2, IVA_TASA };
