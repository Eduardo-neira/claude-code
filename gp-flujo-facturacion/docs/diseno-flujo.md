# Flujo automatizado de facturación post-servicio · Grupo Portátil

## OBJETIVO OPERATIVO

Emitir automáticamente una factura CFDI personalizada **después de cada
servicio completado**, calculando la tarifa según **ubicación (geocerca)** y
**tipo de servicio**, sin intervención manual de captura.

**Indicadores que mejora:**
- Tiempo de emisión de factura: de horas/días → minutos tras cerrar el servicio.
- Fugas de cobro por recargos de zona no aplicados → 0 (el recargo se calcula solo).
- Errores de tarifa por captura manual → eliminados (fuente única de verdad en SQL).
- Trazabilidad: cada factura queda ligada a su servicio, contrato, geocerca y desglose.

---

## PROCESO / FLUJO

| # | Paso | Responsable | Herramienta |
|---|------|-------------|-------------|
| 1 | Operador cierra el servicio en campo (fotos, firma, coordenada GPS) | Alberto / Emmanuel / Meñito / Juan Pablo | AppSheet |
| 2 | AppSheet escribe el servicio en Supabase con `estado='completado'` y `lat/lng` | Sistema | AppSheet → Supabase |
| 3 | Cada 10 min se detectan servicios completados, con pago confirmado, sin facturar | Sistema | n8n (`servicios_por_facturar`) |
| 4 | Se resuelve la geocerca del punto y se calcula la tarifa (base + recargo zona − descuento + IVA) | Sistema | Supabase `calcular_tarifa_servicio()` (PostGIS) |
| 5 | Se arma y timbra el CFDI 4.0 | Sistema | n8n → Facturama API |
| 6 | Se registra la factura y se marca el servicio como `facturado` | Sistema | Supabase (`facturas`, `servicios`) |
| 7 | Se envía la factura al cliente por WhatsApp | Sistema | n8n → Troncalnet |
| 8 | Si el timbrado falla, se registra el error y se alerta a Eduardo | Sistema | n8n → Troncalnet |

### Regla de cobro anticipado
El flujo **solo factura servicios de contratos con `pago_confirmado = true` y
`estado = 'activo'`** (filtrado en la vista `servicios_por_facturar`). Un
servicio de un contrato sin pago no genera factura automática — se queda
pendiente y visible para revisión.

### Modelo de tarifa (fuente única: `calcular_tarifa_servicio`)

```
precio_unitario_aplicado = tarifa_base(plaza, tipo_unidad, tipo_servicio) × modificador_servicio
subtotal_base            = precio_unitario_aplicado × cantidad_unidades
recargo_zona             = geocerca fijo ($) | geocerca % sobre subtotal_base | 0
subtotal                 = subtotal_base + recargo_zona
descuento                = subtotal × descuento_contrato%
base_gravable            = subtotal − descuento
IVA                      = base_gravable × 16%
TOTAL                    = base_gravable + IVA
```

- **Geocerca** = polígono (coordenadas Google Maps, PostGIS SRID 4326). El punto
  del servicio se ubica con `ST_Contains`. Si dos zonas se traslapan gana la de
  menor `prioridad`.
- **Tipo de servicio** aplica un modificador (ej. `bombeo_extra` = ×1.5,
  `inspeccion` = no facturable).

---

## IMPLEMENTACIÓN EN EL STACK DE GP

| Componente | Dónde | Archivo |
|---|---|---|
| Schema + funciones (geocercas, tarifas, servicios, facturas) | Supabase (PostGIS) | `supabase/migrations/0001_facturacion_geocercas.sql` |
| Datos de ejemplo (zonas, tarifas) | Supabase | `supabase/seed_ejemplo.sql` |
| Lógica de tarifa (referencia + tests) | Repo / n8n Code node | `logic/calcular-tarifa.js`, `logic/geocerca.js` |
| Orquestación | n8n | `n8n/workflow-facturacion-post-servicio.json` |
| Timbrado CFDI | Facturama API | (dentro del workflow) |
| Aviso a cliente | Troncalnet / WhatsApp | (dentro del workflow) |
| Captura en campo | AppSheet | (existente — solo agregar coordenada GPS al cierre) |

**Pasos de despliegue:** ver `README.md`.

---

## RIESGOS OPERATIVOS

| Riesgo | Mitigación |
|---|---|
| Servicio sin coordenada GPS | El cálculo procede sin recargo de zona (no bloquea). Hacer obligatorio el GPS en el cierre de AppSheet. |
| Geocercas mal trazadas → recargo equivocado | Seed marcado como ejemplo; validar polígonos reales con el equipo de cada plaza antes de activar. |
| Doble facturación | Índice único parcial en `servicios.factura_id` + la vista excluye ya facturados. |
| Datos fiscales del cliente incompletos (RFC, régimen, CP) | El timbrado falla → se registra `estado_cfdi='error'` y alerta a Eduardo; no rompe el lote. |
| Falla de Facturama | Salida de error del nodo → registro + alerta; el servicio queda pendiente para reintento en el siguiente ciclo. |
| Cliente sin pago pero con servicio realizado | La vista lo excluye; se factura manual tras confirmar pago. |

---

## MÉTRICAS DE ÉXITO

- **% de servicios facturados automáticamente** (meta > 95%).
- **Tiempo medio cierre-de-servicio → CFDI timbrado** (meta < 15 min).
- **Facturas en `estado_cfdi='error'`** por semana (meta → 0, tendencia a la baja).
- **Recargos de zona aplicados / servicios foráneos** (validar que no haya fugas).
- **Diferencia entre tarifa esperada y facturada** (meta = 0; los tests protegen la fórmula).

---

## SIGUIENTE ACCIÓN (Eduardo)

1. Aplicar `0001_facturacion_geocercas.sql` en Supabase (staging primero).
2. Reemplazar el seed de ejemplo por **tarifas reales** y **polígonos reales** de
   las zonas de MTY y QRO (coordinar García/Santa Catarina con MTY y El Marqués
   con Juan Pablo en QRO).
3. Completar datos fiscales (`regimen_fiscal`, `uso_cfdi`, `codigo_postal_fiscal`)
   de los clientes activos.
4. Importar el workflow en n8n, conectar credenciales (Supabase, Facturama,
   Troncalnet) y probar con **1 servicio real** antes de activar el schedule.
5. Agregar el campo de **coordenada GPS obligatoria** al cierre de servicio en AppSheet.
