# 02 · Procesos de negocio — Grupo Portátil

> Equivalente GP de la §1 (flujo principal) y §28 del blueprint EcoSan.
> Cada etapa indica: quién la ejecuta, en qué herramienta, y **si queda registro**.

---

## Flujo principal — cómo es hoy

```text
Lead (WhatsApp)                       ✗ sin registro
  ↓
Cliente                               ⚠ texto dentro del contrato
  ↓
Cotización (WhatsApp/PDF)             ✗ sin registro
  ↓
Contrato                              ✓ contratos (194)
  ↓
Obra/Sitio                            ⚠ embebido en el contrato
  ↓
Asignación de unidades                ✓ contrato_unidades (192)
  ↓
Programación (banda LMV/MJS)          ⚠ texto, sin calendario
  ↓
Ruta                                  ⚠ SimpliRoute, fuera de la base
  ↓
Servicio realizado                    ⚠ SimpliRoute · 0 filas en Supabase ← ROMPE AQUÍ
  ↓
Evidencia                             ⚠ SimpliRoute · un campo foto_url en la base
  ↓
Factura mensual                       ⚠ Facturama, fuera de la base
  ↓
Cobranza                              ⚠ Google Sheets
  ↓
Renovación                            ✗ no hay fecha_fin
```

**La cadena se rompe en "Servicio realizado"** — no porque el dato no exista,
sino porque vive en SimpliRoute y nunca cruza a Supabase. Todo lo que va después
se reconstruye a mano cada semana.

---

## Flujo objetivo — a dónde vamos

```text
Solicitud (chatbot / WhatsApp)  →  solicitudes
  ↓
Cliente                         →  clientes            [CREAR]
  ↓
Cotización                      →  cotizaciones        [CREAR, fase 2]
  ↓
Contrato                        →  contratos           [MODIFICAR]
  ↓
Sitio de obra                   →  sitios              [CREAR]
  ↓
Colocación de unidades          →  contrato_unidades   [OK]
  ↓
Calendario de servicios         →  servicios (planeados)  [GENERAR]
  ↓
Ruta del día                    →  rutas + ruta_servicios [SINCRONIZAR]
  ↓
Servicio ejecutado              →  servicios (completado) [ALIMENTAR]
  ↓
Evidencia                       →  servicio_evidencias [CREAR]
  ↓
Comprobante mensual             →  facturas ← cobros   [ALIMENTAR]
  ↓
Cobro conciliado                →  cobros              [CONCILIAR]
  ↓
Renovación                      →  contratos.fecha_fin [CREAR]
```

---

## P-01 · Alta de contrato

| Paso | Responsable | Herramienta | Registro |
|---|---|---|---|
| 1. Recibir solicitud | Eduardo / Iván | WhatsApp | ✗ |
| 2. Cotizar (tipo, cantidad, zona, frecuencia) | Eduardo | Manual | ✗ |
| 3. Confirmar y capturar contrato | Administración | Supabase | ✓ `contratos` |
| 4. Registrar datos fiscales | Administración | Supabase | ⚠ campo sobrecargado |
| 5. Generar cobro del periodo | — | — | ⚠ `cobros` existe, sin conciliar |
| 6. Confirmar pago **antes** de entregar | Administración | Banco → Sheet | ✗ en la base |
| 7. Asignar unidades disponibles | Iván | Supabase | ✓ `contrato_unidades` |
| 8. Programar entrega | Iván | SimpliRoute | ✗ |
| 9. Entregar y colocar | Operador | SimpliRoute | ⚠ fuera de la base |

**Regla dura:** el paso 7 no debe poder ejecutarse si el paso 6 no ocurrió.
Hoy nada lo impide porque el pago no se registra.

---

## P-02 · Servicio periódico (el proceso central)

Es el proceso que más veces ocurre en GP: 194 contratos, la mayoría `TERCIADO`
(3 por semana) ⇒ del orden de **500+ servicios por semana** `[?]` — cifra no
verificable hasta que `servicios` se alimente.

| Paso | Responsable | Herramienta | Registro |
|---|---|---|---|
| 1. Generar el calendario de la semana desde la banda LMV/MJS | Sistema | *(a construir)* | ✗ |
| 2. Armar la ruta del día por zona | Iván | SimpliRoute | ✗ |
| 3. Asignar ruta a operador | Iván | SimpliRoute | ✗ |
| 4. Ejecutar servicio en sitio | Operador | **SimpliRoute** | ⚠ vive en SimpliRoute |
| 5. Capturar evidencia (foto, firma) | Operador | **SimpliRoute** | ⚠ vive en SimpliRoute |
| 6. Checkout con GPS | Operador | **SimpliRoute** | ⚠ campos listos en Supabase, sin datos |
| 7. Cerrar la ruta | Operador | **SimpliRoute** | ✗ |
| 8. Descontar insumos consumidos | Sistema | n8n | ✗ (módulo listo, sin usar) |
| 9. Emitir comprobante mensual | Sistema | n8n + Facturama | ✗ (workflow listo, granularidad equivocada) |

**Confirmado por Eduardo (2026-08-17):** el registro del servicio ejecutado
**queda en SimpliRoute**, no en AppSheet. El operador cierra la visita ahí mismo.

**Diagnóstico:** el dato *sí existe* — está completo en SimpliRoute, con hora,
coordenada y evidencia. Simplemente nunca viaja a Supabase. Los pasos 8 y 9 están
construidos y probados, e inertes por esa única razón.

**El cuello de botella es el puente SimpliRoute → Supabase.** Es una sola
integración, no dos: la misma llamada trae la ruta *y* los servicios ejecutados.
La tabla ya lo anticipaba — `servicios.simpliroute_visit_id`, `servicios.source`,
`rutas.simpliroute_id` y `rutas.simpliroute_url` existen desde el día uno.

⚠️ **Queda por aclarar el papel de AppSheet.** Si no captura el cierre de
servicio, ¿para qué se usa hoy? (¿alta de contratos, inventario, incidencias?)
No lo asumo.

---

## P-03 · Facturación y cobranza

**Confirmado por Eduardo (2026-08-17): la facturación es MENSUAL POR CONTRATO**,
no por servicio realizado.

| Paso | Responsable | Herramienta | Registro |
|---|---|---|---|
| 1. Determinar qué se factura del periodo | Administración | Manual / Sheet | ⚠ `cobros` ya lo modela |
| 2. Timbrar CFDI (o emitir remisión) | Administración | Facturama | ⚠ fuera de la base |
| 3. Enviar al cliente | Administración | Correo / WhatsApp | ✗ |
| 4. Registrar el pago recibido | Administración | Google Sheets | ✗ en la base |
| 5. Conciliar banco vs facturado | Eduardo | Google Sheets | ✗ |
| 6. Perseguir vencidos | Administración | WhatsApp | ✗ |

**Los seis pasos ocurren fuera de Supabase.** El corte semanal existe para
reconstruir a mano este proceso.

### `cobros` ya es la unidad de facturación correcta

Verificado en la base: **exactamente 1 cobro por contrato por periodo**
(156 contratos → 156 cobros en agosto, 156 en septiembre), y el monto **coincide
al centavo** con `contratos.monto_mensual` en los 126 casos donde ese campo
existe. Cero discrepancias.

Es decir: el modelo mensual ya está bien estructurado en los datos. Lo que falta
es que la factura se cuelgue del **cobro** — y la columna `facturas.cobro_id`
ya existe para eso.

⚠️ 38 contratos activos **no tienen cobro de agosto**. Hay que entender si es
un hueco de captura o contratos que no se facturan ese mes.

Regla fiscal ya implementada en la base:
- `datos_fiscales LIKE '%FACTURA%'` → IVA 16% + CFDI
- `REMISION` → sin IVA, comprobante no fiscal

---

## P-04 · Mantenimiento

| Paso | Responsable | Registro |
|---|---|---|
| 1. Detectar daño en campo | Operador | ✗ |
| 2. Retirar unidad y sustituir | Operador / Iván | ✗ |
| 3. Reparar en patio | Emmanuel / Alberto | ✗ |
| 4. Liberar a `disponible` | Iván | ⚠ solo cambia `estatus` |

`mantenimientos` tiene **0 filas**. No hay historial de reparaciones, ni costo de
mantenimiento por unidad, ni forma de saber qué unidades dan más problemas.
Toda la §16 y §26 de EcoSan (costo por activo, mantenimiento predictivo) está
bloqueada por esto.

---

## P-05 · Geocercas y GPS

Proceso ya documentado y automatizado parcialmente (skill `geocercas-intellihub`):

```text
Excel RUTAS WC <mes>  →  parse  →  cruce contra Intellihub  →  auditoría  →  escritura
```

Las cinco comprobaciones de la auditoría (duplicada / revisar / **reubicación** /
cliente de baja / confirmar) son conocimiento operativo real de GP que **debe
preservarse** en el modelo nuevo. La comprobación por *número de sanitario* —no
por coordenada— es la que evita duplicados y no existe en ningún blueprint genérico.

⚠️ Hoy las geocercas viven en Intellihub. La tabla `geocercas` de Supabase tiene
2 filas de ejemplo. Son dos sistemas con la misma información y ninguna sincronía.

---

## P-06 · Corte semanal

| Paso | Responsable | Herramienta |
|---|---|---|
| 1. Leer unidades en renta MTY/QRO | Eduardo | Google Sheets |
| 2. Leer facturado vs cobrado | Eduardo | Google Sheets |
| 3. Calcular las 5 métricas fijas | Eduardo | Manual |
| 4. Identificar las 3 excepciones más caras | Eduardo | Manual |
| 5. Mandar mensajes a Iván y administración | Eduardo | WhatsApp |

Este proceso es **el síntoma**, no el problema. Existe porque el sistema no puede
responder solo. Cuando `servicios` y `cobros` estén vivos, los pasos 2 y 3 se
vuelven una consulta.

⚠️ El paso 1 **no** se automatiza del todo: como QRO se lleva aparte (decisión de
Eduardo), la cifra MTY+QRO seguirá armando dos fuentes a mano.

---

## Eventos del dominio (§20 de EcoSan)

Eventos que GP debería emitir, en orden de valor:

| Evento | Dispara |
|---|---|
| `cobro.pagado` | Habilita generar órdenes de entrega/servicio y emitir el comprobante |
| `servicio.completado` | Evidencia → insumos → cumplimiento → notificación |
| `servicio.fallido` | Alerta a Iván, reprogramación |
| `unidad.colocada` | `unidades.estatus = EN_CAMPO` + colocación vigente |
| `unidad.retirada` | Libera unidad, dispara mantenimiento post-retiro |
| `unidad.dañada` | Mantenimiento correctivo + evaluar sustitución |
| `contrato.por_vencer` | Aviso de renovación (requiere `fecha_fin`) |
| `cobro.vencido` | Secuencia de cobranza |
| `factura.timbrada` | Envío al cliente |

⚠️ `event_log` existe pero es un log de idempotencia de webhooks, no un bus de
eventos de dominio. Ver `04-modelo-datos`.
