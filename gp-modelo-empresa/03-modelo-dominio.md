# 03 · Modelo de dominio — Grupo Portátil

> Equivalente GP de las §5-§20 y §28 del blueprint EcoSan.
> Un apartado por dominio, con entidades, estados, reglas y eventos.

---

## Mapa de dominios

```text
COMERCIAL          Solicitud · Cliente · Cotización
CONTRATACIÓN       Contrato · Sitio · Colocación
FLOTA              Unidad · Movimiento · Mantenimiento
OPERACIÓN          Servicio · Ruta · Evidencia · Insumo
DINERO             Cobro · Factura · Acción de cobranza
```

---

## Dominio · Clientes

**Propósito.** Ser la entidad a la que se le vende, se le cobra y se le mide.

### Entidades
`Cliente` · `Contacto`

### Estado actual
❌ **No existe.** El cliente es `contratos.cliente`, texto libre. 106 cadenas
distintas que se normalizan a ~100 ⇒ **~6 duplicados por escritura**.

Ejemplo real: `GTC TERMO CONTROL` aparece en 4 contratos distintos.
Hoy son 4 registros sin relación entre sí.

### Reglas de negocio
- Un cliente puede tener varios contratos y varias obras.
- **Quien solicita el servicio no es quien paga.** El contacto de obra y el de
  oficina son personas distintas — GP ya lo modela con `contacto_obra` y
  `contacto_oficina`, pero como campos sueltos.
- El RFC pertenece al cliente, no al contrato.
- La clasificación (A/B/C por volumen y puntualidad) es del cliente.

### Lo que se desbloquea al crearlo
- Saldo y antigüedad de cartera por cliente.
- **Concentración de ingresos** — métrica #5 del corte semanal, hoy incalculable.
- Historial completo antes de renegociar precio.
- Datos fiscales estructurados para timbrar CFDI sin capturar a mano.

---

## Dominio · Contratos

**Propósito.** El acuerdo que autoriza cobrar y obliga a servir.

### Entidades
`Contrato` · `Sitio` · `Colocación` (`contrato_unidades`)

### Estado actual
✅ 194 contratos activos. **Pero:**

| Falta | Consecuencia |
|---|---|
| `fecha_fin` | No se puede calcular vencimiento, renovación ni churn |
| Ciclo de vida | Solo hay `activo` booleano: no distingue suspendido de cancelado |
| `sucursal_id` poblado | 194 de 194 en NULL — ningún análisis por plaza |
| Separación de sitio | La obra vive dentro del contrato |
| Entidad que factura | 10 contratos son de empresas hermanas y no se distinguen |
| `monto_mensual` | 33 contratos sin él |

### Estados propuestos
```text
borrador → cotizado → firmado → activo → por_vencer → renovado
                                    ↓
                              suspendido / vencido / cancelado
```

### Reglas de negocio
- **Un contrato sin cobro pagado no genera órdenes de servicio.** (Prepago.)
- Un contrato activo debe tener al menos una unidad colocada.
  ⚠️ Hoy **12 contratos activos no tienen ninguna**.
- El precio base del servicio sale del contrato (`precio_sin_iva` +
  `precio_lavamanos` si aplica). Es la fuente única — ya implementado en
  `calcular_tarifa_servicio()`.
- La banda (`LMV` / `MJS`) define en qué días se sirve. No es negociable por servicio.

### Eventos
`contrato.creado` · `contrato.activado` · `contrato.por_vencer` ·
`contrato.renovado` · `contrato.cancelado`

---

## Dominio · Flota

**Propósito.** Saber dónde está cada unidad, en qué estado, y cuánto cuesta.

### Entidades
`Unidad` · `MovimientoUnidad` · `Mantenimiento`

### Estado actual
✅ **El dominio mejor resuelto de GP.** 437 unidades con código único, tipo,
color, categoría, propietario y estatus.

### Estados de unidad (reales, en la base)
```text
BODEGA ──colocación──► EN_CAMPO ──retiro──► BODEGA
BODEGA ──venta──► EN_VENTA
BODEGA ──desgaste──► BAJA
```

⚠️ Falta un estado `MANTENIMIENTO`. Hoy una unidad en reparación sigue marcada
como `BODEGA`, lo que infla la disponibilidad aparente.

### Lo que falta: **historial**
§9 de EcoSan es explícita — *"nunca sobrescribas únicamente el estado, guarda
historial"*. GP solo tiene el estado actual. No se puede responder:

- ¿En cuántas obras ha estado la unidad MTY-0481?
- ¿Cuántos días estuvo ociosa este año?
- ¿Cuánto ingreso generó desde que se compró?
- ¿Cuánto costó mantenerla?

### Reglas de negocio
- Una unidad no pasa de un contrato a otro sin volver a bodega.
- `EN_CAMPO` ⇔ existe exactamente una colocación vigente.
  ⚠️ **Hoy se viola 27 veces**: 11 unidades en campo sin colocación,
  16 colocaciones de unidades que no están en campo.
- Las unidades con `propietario = CLIENTE` (8) se excluyen de utilización e
  ingreso por activo. No son activos de GP.

### Eventos
`unidad.colocada` · `unidad.retirada` · `unidad.dañada` · `unidad.reparada` ·
`unidad.dada_de_baja`

---

## Dominio · Servicios

**Propósito.** Registrar qué se hizo, dónde, quién y con qué resultado.
**Es el dominio central del negocio.**

### Entidades
`Servicio` · `ServicioUnidad` · `Evidencia`

### Estado actual
⛔ **`servicios` = 0 filas en Supabase** — pero el dato **sí existe**: vive en
**SimpliRoute** (confirmado por Eduardo, 2026-08-17). El operador cierra ahí cada
visita con hora, coordenada y evidencia.

La tabla está bien diseñada y fue pensada para recibirlo: `checkout_lat`,
`checkout_lng`, `checkout_time`, `hora_programada`, `hora_llegada`,
`checklist_ok`, `calificacion_cliente`, `retrabajo`, `simpliroute_visit_id`,
`source`. Todos los campos correctos. Ninguno con datos.

**No es un problema de captura, es de integración.** Ver `06` §AUT-07.

### Tipos (ya catalogados en `tipos_servicio_modificador`)
| Clave | Modificador de tarifa | Facturable |
|---|---:|---|
| `LIMPIEZA` | 1.00 | Sí |
| `ENTREGA` | 1.00 | Sí |
| `RETIRO` | 1.00 | Sí |
| `EXTRA` | 1.50 | Sí |
| `INSPECCION` | 0.00 | No |

### Estados propuestos
```text
programado → asignado → en_curso → completado
                            ↓
                      fallido / cancelado / reprogramado
```

Hoy solo existe `completado` booleano. Un servicio que no se pudo hacer
(acceso denegado, unidad no encontrada) **no tiene dónde registrarse** — y son
justo los que hay que perseguir.

### Reglas de negocio
- Un servicio completado **requiere evidencia**.
- Un servicio no puede completarse sin operador asignado.
- Un servicio de limpieza debe tener al menos una unidad asociada.
- ⚠️ **Un servicio hoy liga a una sola unidad** (`servicios.unidad_id`).
  Pero una obra tiene varias unidades y se sirven en una sola visita.
  Debe ser relación N:N (§13 de EcoSan).

⚠️ **El servicio ya NO es el disparador de la factura.** GP factura mensual por
contrato, así que el servicio queda como registro operativo puro: cumplimiento,
productividad, consumo de insumos y evidencia ante reclamos. Es una separación
más limpia que la que se había construido.

### Evidencia
Hoy: un campo `foto_url`. Se necesita tabla propia con tipos
`foto_antes` · `foto_despues` · `firma` · `incidencia` · `documento`,
cada una con coordenada, autor y momento de captura — que es justo lo que
SimpliRoute ya captura.

### Eventos
`servicio.programado` · `servicio.asignado` · `servicio.iniciado` ·
`servicio.completado` · `servicio.fallido`

---

## Dominio · Rutas

**Propósito.** Agrupar servicios en una jornada de un operador y medir eficiencia.

### Estado actual
⚠️ `rutas` y `ruta_servicios` existen y están vacías. La operación real vive en
**SimpliRoute**, igual que los servicios. La tabla ya tiene `simpliroute_id` y
`simpliroute_url`: el puente está previsto, no construido.

**Es el mismo puente que el de servicios**, no uno aparte: la misma llamada a la
API de SimpliRoute trae la ruta, sus paradas y la ejecución de cada visita.

### Lo que falta para medir
`distancia_planeada` · `distancia_real` · `duracion_planeada` · `duracion_real`
y, en cada parada, `llegada_planeada` vs `llegada_real`.

Sin eso no hay: cumplimiento, retrasos, km por servicio, costo por ruta.

### Reglas de negocio
- Una ruta pertenece a un operador, una fecha y una plaza.
- Las paradas van ordenadas (`ruta_servicios.orden`).
- La ruta cierra cuando todas sus paradas están en estado terminal.
- Al cerrar la ruta se descuentan los insumos (ya implementado).

---

## Dominio · Dinero

**Propósito.** Cobrar antes, comprobar después, y saber quién debe.

### Entidades
`Cobro` · `Factura` · `AcciónDeCobranza`

### Estado actual

**Cobros:** 337 filas, periodos jul–sep 2026, **$1,925,770 MXN**,
**337 en `pendiente`, 0 con `fecha_pago`**.

**Facturas:** 0 filas. Se timbra en Facturama, no se persiste.

**Cobranza:** no existe como entidad.

### El bloqueo estructural
```text
servicios_por_facturar  exige  cobros.estado = 'pagado'
                                        ↓
                          hoy hay 0 cobros pagados
                                        ↓
              el flujo de facturación automática nunca emitirá nada
```

Esto no es un bug: es la regla de prepago funcionando correctamente sobre datos
incompletos. **Se arregla registrando pagos, no cambiando la vista.**

### La unidad de facturación es el COBRO, no el servicio

**Confirmado por Eduardo (2026-08-17): GP factura mensual por contrato.**

Verificado en la base: `cobros` es exactamente **1 por contrato por periodo**
(156 en agosto, 156 en septiembre) y su monto coincide al centavo con
`contratos.monto_mensual` en los 126 casos donde ese campo existe. La estructura
mensual ya es correcta; `facturas.cobro_id` ya existe para colgar la factura ahí.

⚠️ `gp-flujo-facturacion` se construyó emitiendo **por servicio**. Es la
granularidad equivocada y hay que corregirla. Ver `06` §AUT-01.

### Reglas de negocio
- Cobro anticipado: el pago precede al servicio.
- **La factura cuelga del `cobro` (mensual), no del `servicio`.**
- `FACTURA` lleva IVA 16% y se timbra CFDI; `REMISION` no lleva IVA.
- El recargo por zona se resuelve con PostGIS sobre la coordenada del checkout;
  si falta, se usa la del contrato.
- **GP solo factura lo suyo.** Los 10 contratos de las empresas hermanas
  (Torreón, Saltillo) tienen administración aparte: se marcan y se excluyen,
  no se timbra por ellos. Ver `04-modelo-datos` §Cambio 3.
- Los servicios `EXTRA` (modificador 1.50) probablemente sí se cobran fuera del
  mensual `[?]` — falta confirmarlo.

### Eventos
`cobro.generado` · `cobro.pagado` · `cobro.vencido` · `factura.timbrada` ·
`factura.cancelada`

---

## Dominio · Insumos

**Propósito.** Saber cuánto cuesta realmente dar un servicio.

### Estado actual
✅ Módulo **completo y bien diseñado**: catálogo (9 insumos), existencias por
sucursal, consumo estándar (26 recetas BOM), ledger de movimientos con
idempotencia, consumo declarado que sobreescribe al estimado.

⛔ `movimientos_insumo` = 0 filas. Se alimenta al cerrar ruta, y no hay rutas
en Supabase — aunque sí las hay en SimpliRoute.

Es el mejor ejemplo del patrón general de GP: **la ingeniería está adelante de
los datos.**

---

## Permisos (§29 de EcoSan)

### Estado actual
`perfiles.rol` es un enum con **dos valores**: `admin`, `oficina`. Un usuario registrado.

### Roles que faltan
`direccion` · `operaciones` · `despacho` · `cobranza` · `operador` · `cliente`

### Por qué importa ya
El cliente pregunta por WhatsApp y las integraciones escriben desde fuera. En
cuanto esos flujos toquen Supabase, **necesitan identidad y permiso propios**.
Un token de integración no debe poder leer precios ni cartera; un cliente solo lo suyo.

Como se advierte en `01-modelo-empresa`, en GP una persona cruza varios puestos.
Por eso conviene modelar **permisos** (`servicio.completar`, `factura.emitir`,
`cliente.leer`) y componer roles con ellos, no al revés.

⚠️ Riesgo adicional: esta base contiene contratos de **empresas de terceros**
(las hermanas). Un rol mal acotado expondría precios que ni siquiera son de GP.
