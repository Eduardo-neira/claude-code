# 06 · Mapa de automatización — Grupo Portátil

> Equivalente GP de las §21 y §22 del blueprint EcoSan.

---

## Inventario de automatizaciones

| ID | Nombre | Estado | Bloqueado por |
|---|---|---|---|
| AUT-01 | Facturación automática post-servicio | 🟡 Construida, sin activar | Sin servicios y sin cobros pagados |
| AUT-02 | Descuento de insumos al cerrar ruta | 🟡 Construida, sin activar | Sin rutas |
| AUT-03 | Dashboard de desempeño de operadores | 🟡 Desplegado, muestra vacío | Sin servicios |
| AUT-04 | Chatbot de atención WhatsApp | 🟡 18 FAQ + 5 tarifas cargadas | Sin conversaciones |
| AUT-05 | Auditoría de geocercas Intellihub | 🟢 **Operando** (skill + scripts) | — |
| AUT-06 | Corte semanal | 🟠 Manual, desde Google Sheets | — |
| AUT-07 | Sincronización AppSheet → Supabase | 🔴 **No existe** | **Es el cuello de botella** |
| AUT-08 | Sincronización SimpliRoute → Supabase | 🔴 No existe | — |
| AUT-09 | Conciliación de pagos | 🔴 No existe | — |
| AUT-10 | Calendario semanal de servicios | 🔴 No existe | — |
| AUT-11 | Alertas de contrato por vencer | 🔴 No existe | Falta `fecha_fin` |
| AUT-12 | Cobranza automática de vencidos | 🔴 No existe | Falta conciliación |

🟢 operando · 🟡 construido sin datos · 🟠 manual · 🔴 no existe

**Lectura:** cuatro automatizaciones ya construidas están inertes por la misma
causa. No hay que construir más — hay que destrabar AUT-07.

---

## AUT-07 · AppSheet → Supabase (prioridad absoluta)

**Qué resuelve.** Que un servicio hecho en campo quede registrado.

```text
Operador cierra servicio en AppSheet
        ↓
Webhook → n8n
        ↓
Validar: contrato existe · operador existe · unidades del sitio
        ↓
INSERT/UPDATE servicios
   completado, checkout_lat, checkout_lng, checkout_time,
   hora_llegada, checklist_ok, operador_id, unidad(es)
        ↓
INSERT servicio_evidencias (fotos, firma)
        ↓
Emitir domain_event 'servicio.completado'
        ↓
   ├─► AUT-02 descuenta insumos
   ├─► AUT-01 evalúa comprobante
   └─► Actualiza estado de unidad
```

**Responsables:** Eduardo (configurar webhook en AppSheet) · sistema (n8n).

**Riesgos:**
- Servicio sin señal en campo → AppSheet encola y reenvía. n8n debe ser idempotente
  (usar `event_log` con `event_id`, que para eso existe).
- Operador captura mal el contrato → validar contra `contratos` antes de insertar
  y rechazar con aviso, no insertar basura.

**Métrica de éxito:** `servicios` con más de 400 filas la primera semana y
el dashboard de operadores mostrando datos reales.

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
   └─► Libera el contrato en servicios_por_facturar
```

**Decisión pendiente:** ¿la captura sigue en Google Sheets con sincronía hacia
Supabase, o administración captura directo en Supabase? Lo segundo es más limpio;
lo primero es menos disruptivo para el equipo.

**Riesgo:** si la conciliación se hace mal, el flujo de facturación emite
comprobantes de servicios no pagados. La regla de prepago es la protección —
no debilitarla para "destrabar" el flujo.

---

## AUT-01 · Facturación post-servicio (ya construida)

Detalle completo en `gp-flujo-facturacion/`. Resumen:

```text
servicios.completado = true  (y cobro pagado)
        ↓
n8n cada 10 min → vista servicios_por_facturar
        ↓
calcular_tarifa_servicio()   ← PostGIS resuelve la geocerca
   base(contrato) × modificador + recargo_zona (+ IVA si FACTURA)
        ↓
   ├─ FACTURA  → Facturama timbra CFDI 4.0 → registra → WhatsApp
   └─ REMISION → comprobante no fiscal → registra → WhatsApp
```

**Estado:** migración aplicada y validada, 13 pruebas pasando, incluidos dos
casos reales de la base (FACTURA foránea = $3,770 · REMISION zona base = $2,100).

**Pendientes propios (del README del módulo):**
1. Datos fiscales del receptor (RFC, régimen, uso CFDI, CP) — no existen
   estructurados. Se resuelve con `clientes` (`04-modelo-datos` §Cambio 1).
2. Confirmar el modelo: ¿comprobante por servicio o mensual por cobro?
3. Polígonos y recargos reales (hoy solo 2 geocercas de ejemplo).
4. Conectar credenciales y probar con **un** servicio real.

⚠️ **No activar hasta tener AUT-07 y AUT-09.** Activarla antes no rompe nada
(la vista devuelve vacío), pero da falsa sensación de avance.

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
expone precios de todos los clientes en una sola respuesta mal formulada.

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
