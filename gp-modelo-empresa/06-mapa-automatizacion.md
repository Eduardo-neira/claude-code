# 06 · Mapa de automatización — Grupo Portátil

> Equivalente GP de las §21 y §22 del blueprint EcoSan.

---

## Inventario de automatizaciones

| ID | Nombre | Estado | Bloqueado por |
|---|---|---|---|
| AUT-01 | Facturación automática | 🟠 Construida con **granularidad equivocada** (por servicio, debe ser mensual) | Rediseño + sin cobros pagados |
| AUT-02 | Descuento de insumos al cerrar ruta | 🟡 Construida, sin activar | Sin rutas |
| AUT-03 | Dashboard de desempeño de operadores | 🟡 Desplegado, muestra vacío | Sin servicios |
| AUT-04 | Chatbot de atención WhatsApp | 🟡 18 FAQ + 5 tarifas cargadas | Sin conversaciones |
| AUT-05 | Auditoría de geocercas Intellihub | 🟢 **Operando** (skill + scripts) | — |
| AUT-06 | Corte semanal | 🟠 Manual, desde Google Sheets | — |
| AUT-07 | **Sincronización SimpliRoute → Supabase** (rutas + servicios + evidencia) | 🔴 **No existe** | **Es el cuello de botella** |
| AUT-09 | Conciliación de pagos | 🔴 No existe | Decisión pendiente |
| AUT-10 | Calendario semanal de servicios | 🔴 No existe | — |
| AUT-11 | Alertas de contrato por vencer | 🔴 No existe | Falta `fecha_fin` |
| AUT-12 | Cobranza automática de vencidos | 🔴 No existe | Falta conciliación |

🟢 operando · 🟡 construido sin datos · 🟠 manual o mal enfocado · 🔴 no existe

> **AUT-08 se fusionó con AUT-07.** Eran dos puentes solo mientras se creía que
> el servicio se capturaba en AppSheet y la ruta en SimpliRoute. Confirmado que
> ambos viven en SimpliRoute, es una sola integración.

**Lectura:** tres automatizaciones ya construidas están inertes por la misma
causa, y una cuarta (AUT-01) está construida sobre un supuesto equivocado.
No hay que construir más — hay que destrabar AUT-07 y corregir AUT-01.

---

## AUT-07 · SimpliRoute → Supabase (prioridad absoluta)

**Qué resuelve.** Que la operación que ya ocurre y ya se registra en SimpliRoute
quede también en la base, que es donde se puede medir, facturar y auditar.

**Punto clave:** el dato **no hay que crearlo, hay que traerlo**. El operador ya
cierra su visita en SimpliRoute con hora, coordenada y evidencia. El trabajo es
de integración, no de captura.

```text
SimpliRoute (ruta del día cerrada)
        ↓
n8n · cron cada hora + al cierre del día
   (o webhook de SimpliRoute si el plan lo incluye)
        ↓
GET rutas del día + sus visitas
        ↓
UPSERT rutas
   simpliroute_id, fecha, operador_id, sucursal_id, estado,
   total_paradas, paradas_completadas
        ↓
UPSERT servicios  (clave: simpliroute_visit_id)
   contrato_id, operador_id, unidad(es), fecha_servicio, tipo,
   completado, hora_programada, hora_llegada,
   checkout_lat, checkout_lng, checkout_time, source='simpliroute'
        ↓
INSERT servicio_evidencias (fotos, firma)
        ↓
Emitir domain_event 'servicio.completado'
        ↓
   ├─► AUT-02 descuenta insumos al cerrar la ruta
   ├─► Actualiza estado de unidad
   └─► Alimenta cumplimiento (programado vs ejecutado)
```

**Responsables:** Eduardo (credenciales de API de SimpliRoute) · sistema (n8n).

**El problema real a resolver: el amarre.**
SimpliRoute conoce sus visitas por su propio ID y por dirección. Supabase conoce
contratos por `id` y unidades por `codigo`. Hay que decidir **cómo se amarra una
visita de SimpliRoute con un contrato de GP**. Opciones, de mejor a peor:

1. Guardar el `contrato_id` de GP en el campo de referencia del cliente en
   SimpliRoute. Es lo más robusto y probablemente ya exista algo así.
2. Amarrar por coordenada contra `contratos.latitud/longitud` (PostGIS ya está
   instalado). Falla en los **60 contratos sin coordenadas**.
3. Amarrar por texto de dirección. Frágil, no recomendado.

Sin resolver esto, el puente trae datos que no se pueden ligar a nada.

**Riesgos:**
- Reprocesar el mismo día duplicaría servicios → **UPSERT por
  `simpliroute_visit_id`**, más `event_log` para idempotencia (para eso existe).
- Una visita sin contrato identificable → mandarla a una bandeja de revisión,
  **nunca insertar con `contrato_id` nulo** y dejarla huérfana.
- Servicios de QRO: como QRO se lleva aparte (decisión de Eduardo), filtrar por
  la cuenta o sucursal de SimpliRoute que corresponda a MTY.

**Métrica de éxito:** `servicios` con más de 400 filas la primera semana,
menos de 5% de visitas sin amarrar, y el dashboard de operadores con datos reales.

---

## AUT-10 · Calendario semanal de servicios

**Qué resuelve.** Que exista el servicio *planeado* contra el cual comparar el ejecutado.

```text
Domingo 20:00 (cron n8n)
        ↓
SELECT generar_servicios_semana(<lunes siguiente>)
        ↓
Contratos activos con banda LMV → lun/mié/vie
Contratos activos con banda MJS → mar/jue/sáb
        ↓
servicios en estado 'programado'
        ↓
Enviar a SimpliRoute para armar rutas
        ↓
Notificar a Iván el total programado de la semana
```

**Prerrequisito:** cambiar el default de `servicios.completado` a `false`
(ver `04-modelo-datos` §Cambio 11). Hoy nace en `true`, y sin eso no se puede
distinguir lo planeado de lo hecho.

**Sinergia con AUT-07.** Si el calendario se manda a SimpliRoute con el
`contrato_id` en la referencia de la visita, el amarre de vuelta queda resuelto
de origen: el servicio sale de Supabase, se ejecuta en SimpliRoute y regresa
identificado. **Vale la pena construir AUT-10 y AUT-07 juntas, no en serie.**

**Métrica de éxito:** cumplimiento semanal = completados ÷ programados.
Es el KPI operativo que hoy no existe.

---

## AUT-09 · Conciliación de pagos

**Qué resuelve.** Los 337 cobros pendientes por $1,925,770 sin un solo pago registrado.

```text
Movimiento bancario / captura de administración
        ↓
Identificar contrato y periodo
        ↓
UPDATE cobros SET estado='pagado', fecha_pago=..., metodo_pago=...
        ↓
Emitir 'cobro.pagado'
        ↓
   ├─► Habilita generar órdenes de servicio (regla de prepago)
   └─► Dispara la emisión del comprobante mensual (AUT-01)
```

**Decisión pendiente de Eduardo:** ¿la captura sigue en Google Sheets con
sincronía hacia Supabase, o administración captura directo en Supabase?
Lo segundo es más limpio; lo primero es menos disruptivo para el equipo.

**Riesgo:** si la conciliación se hace mal, el flujo de facturación emite
comprobantes de contratos no pagados. La regla de prepago es la protección —
no debilitarla para "destrabar" el flujo.

---

## AUT-01 · Facturación — construida con la granularidad equivocada

Detalle en `gp-flujo-facturacion/`. **Se construyó emitiendo un comprobante por
cada servicio completado.** Eduardo confirmó (2026-08-17) que GP factura
**mensual por contrato**. Hay que corregirlo antes de activarlo.

### Por qué importa
Un contrato `TERCIADO` son 3 servicios por semana ≈ **12 comprobantes al mes para
un solo cliente**. Con 156 contratos facturables, serían ~1,900 CFDI mensuales en
vez de ~156. No es una diferencia de detalle: es otro proceso, otro costo de
timbrado y otra relación con el cliente.

### Lo que ya está bien y se conserva
- `calcular_tarifa_servicio()` — la fórmula (base × modificador + recargo de
  geocerca + IVA si es fiscal) es correcta y está validada con 13 pruebas contra
  casos reales. Solo cambia **cuándo** se invoca.
- La rama CFDI / Remisión.
- La regla de cobro anticipado.
- `facturas.cobro_id` — la columna del modelo correcto **ya existe**.

### Flujo corregido
```text
Inicio de mes (n8n)
        ↓
cobros del periodo con estado='pagado'   ← 1 por contrato por mes (verificado)
        ↓
monto = contratos.monto_mensual (coincide al centavo en los 126 verificados)
        ↓
   ├─ es_fiscal  → Facturama timbra CFDI 4.0 → factura.cobro_id → WhatsApp
   └─ REMISION   → comprobante no fiscal → registra → WhatsApp
```

Los **servicios** dejan de ser el disparador de la factura y pasan a ser lo que
deben ser: el registro operativo (cumplimiento, productividad, insumos, evidencia
ante reclamos). Es una separación más limpia que la que se construyó.

⚠️ **Excepción a confirmar:** los servicios `EXTRA` tienen modificador 1.50 en el
catálogo, lo que sugiere que **sí** se cobran aparte del mensual. Si es así, el
flujo por servicio no se tira: se conserva **solo para los EXTRA**.

⚠️ **Solo se factura por GP.** Los contratos de las empresas hermanas (Torreón y
Saltillo) deben quedar fuera de este flujo — su administración es aparte.
Ver `04-modelo-datos` §Cambio 3.

**Pendientes que siguen vigentes:**
1. Datos fiscales del receptor (RFC, régimen, uso CFDI, CP) — se resuelven con
   `clientes` (`04-modelo-datos` §Cambio 1).
2. Polígonos y recargos reales (hoy solo 2 geocercas de ejemplo).
3. Conectar credenciales y probar con **un** cobro real.

⚠️ **No activar hasta tener AUT-09** (conciliación). Sin cobros pagados no emite
nada, y activarlo antes solo da falsa sensación de avance.

---

## AUT-11 y AUT-12 · Contratos y cobranza

Ambas dependen de columnas que no existen todavía.

**AUT-11 · Contrato por vencer** — requiere `contratos.fecha_fin`:
```text
Diario 7:00 → contratos con fecha_fin <= hoy + 7
        ↓
WhatsApp al contacto de oficina + lista a Eduardo
```

**AUT-12 · Cobranza de vencidos** — requiere conciliación (AUT-09):
```text
cobro.vencido
   ↓ consultar cliente e historial
   ↓ clasificar riesgo
   ↓ generar mensaje
   ↓ WhatsApp (Troncalnet)
   ↓ registrar acción en collection_actions
   ↓ programar seguimiento
```

Esta última es donde un agente de IA aporta valor real — pero **solo cuando haya
historial de pagos que leer**. Hoy leería 337 filas idénticas en `pendiente`.

---

## Agentes de IA (§22 de EcoSan)

### Estado
Solo el chatbot de WhatsApp: 18 FAQ, 5 tarifas, 0 conversaciones.

### Principio que sí hay que respetar desde el día uno
EcoSan lo dice bien: el agente **no debe tener acceso directo ilimitado**.
Debe usar herramientas específicas.

Para GP, las herramientas mínimas:

```text
consultar_contrato(numero)
consultar_saldo_cliente(cliente_id)
consultar_estado_unidad(codigo)
consultar_servicios_pendientes(fecha, plaza)
consultar_disponibilidad(tipo_unidad, plaza)
consultar_tarifa(tipo_unidad, zona, frecuencia)
```

Nunca `SELECT` libre sobre la base. Un agente con acceso abierto a `contratos`
expone precios de todos los clientes en una sola respuesta mal formulada — y
además los de las empresas hermanas, que ni siquiera son de GP.

### Cuándo
**Después de la fase 1.** Un agente sobre tablas vacías inventa o contesta "no sé".
Las dos respuestas erosionan la confianza del equipo en el sistema, y esa
confianza es más cara de recuperar que de construir.

---

## Base de conocimiento (§23)

Ya existe, dispersa:

| Contenido | Dónde |
|---|---|
| Rutas, flota, contratos, mantenimiento | Skill `mod-operaciones-gp` (4 referencias) |
| Proceso de geocercas | Skill `geocercas-intellihub` |
| Corte semanal | Skill `reporte-semanal-gp` |
| SOP de cierre de jornada | `operaciones/inventario-insumos/docs/` |
| Diseño de facturación | `gp-flujo-facturacion/docs/` |
| FAQ de clientes | `chatbot_faq` (18 filas) |
| Modelo de empresa | Este directorio |

**Está mejor de lo que parece.** Falta consolidar en un índice y decidir qué
alimenta el RAG del chatbot. La `chatbot_faq` con 18 filas ya es el primer paso.

⚠️ La skill `mod-operaciones-gp` dice que AppSheet es la app de campo. Tras la
decisión de Eduardo, eso hay que corregirlo ahí también: quien registra el
servicio es SimpliRoute.
