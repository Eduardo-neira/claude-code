# 07 · Roadmap — Grupo Portátil

> Equivalente GP de las §33 y §34 del blueprint EcoSan.
> Ordenado por dependencia, no por atractivo.

---

## Principio

EcoSan lo cierra bien:

> *Sin datos limpios, IDs consistentes, eventos, historial y reglas,
> la IA solo automatiza desorden.*

GP tiene IDs consistentes y reglas. **Le faltan los datos, los eventos y el historial.**
Todo el roadmap va de conseguir esas tres cosas antes de construir encima.

---

## Fase 0 · Decisiones — RESUELTAS 2026-08-17

| # | Pregunta | Respuesta de Eduardo | Consecuencia |
|---|---|---|---|
| 1 | ¿Dónde queda el registro de un servicio hecho? | **SimpliRoute** | El puente es SimpliRoute → Supabase, no AppSheet. **El dato ya existe: hay que traerlo, no crearlo.** AUT-07 y AUT-08 se fusionan |
| 2 | ¿Torreón y Saltillo? | **Razones sociales distintas — empresas hermanas de familiares, con administración y finanzas aparte** | No son plazas ni emisores de GP. Su facturación **no la emite GP** y sus ingresos **no son de GP** |
| 3 | ¿Querétaro? | **Opera, pero se lleva aparte** | El sistema es de MTY. QRO no se carga. Se deja la puerta abierta sin construir para ella |
| 4 | ¿Comprobante por servicio o mensual? | **Mensual por contrato** | AUT-01 está construida con la granularidad equivocada. Se corrige: la factura cuelga del `cobro`, no del `servicio` |
| 5 | ¿La cobranza migra de Sheets a Supabase? | **Pendiente** | Sigue bloqueando AUT-09 |

### Lo que estas respuestas cambiaron del plan original
- **Se simplificó:** dos puentes en vez de tres; el registro de campo ya existe.
- **Se corrigió un error:** el flujo de facturación ya construido emite por
  servicio. Debe emitir mensual por contrato.
- **Apareció un tema nuevo:** separar los ingresos de las empresas hermanas de
  los de GP. Ver Fase 1.

### Decisión que sigue abierta
**#5 · ¿El `GP_Control_Financiero_2026` sigue siendo la fuente de verdad del
dinero, o administración empieza a capturar los pagos en Supabase?**
Bloquea AUT-09, y AUT-09 bloquea toda la facturación automática.

---

## Fase 1 · Que el río corra (4–6 semanas)

**Objetivo único: que `servicios` y `cobros` reflejen la realidad.**

| Entregable | Detalle | Éxito |
|---|---|---|
| **Puente SimpliRoute → Supabase** | AUT-07 | `servicios` y `rutas` con datos reales cada día |
| **Resolver el amarre visita ↔ contrato** | AUT-07 | <5% de visitas sin ligar a un contrato |
| Corregir AUT-01 a facturación mensual | `06` §AUT-01 | La factura cuelga del `cobro`, no del `servicio` |
| **Marcar las empresas hermanas** | Ver abajo | Los ingresos de GP dejan de mezclarse con los de terceros |
| Calendario semanal | AUT-10 + `generar_servicios_semana()` | Servicios programados cada domingo |
| `completado` default `false` | `04` §Cambio 11 | Se distingue planeado de ejecutado |
| Poblar `sucursal_id` = MTY | `04` §Cambio 5 | 0 contratos sin plaza (hoy 194) |
| Conciliación de cobros | AUT-09 | Cobros `pagado` con `fecha_pago` |
| Completar 33 `monto_mensual` | Captura manual | Ingreso recurrente calculable |
| Completar 60 coordenadas | Captura manual | Amarre por coordenada + recargo por zona |
| Revisar 38 contratos sin cobro de agosto | Captura / criterio | Se entiende si es hueco o excepción |
| Limpiar la fila basura (`nan`) | 1 registro | — |

### Separar a las empresas hermanas (nuevo, tras la decisión #2)

Torreón y Saltillo son empresas de familiares con **finanzas aparte**. Hoy sus
contratos están mezclados con los de GP en la misma tabla:

| Emisor | Contratos | Clientes | Renta mensual | Unidades colocadas |
|---|---:|---:|---:|---:|
| GP (`FACTURA`) | 158 | 81 | $934,628 | 157 |
| GP (`REMISION`) | 25 | 18 | $72,180 | 26 |
| **Torreón** | 8 | 4 | **$19,836** | 8 |
| **Saltillo** | 2 | 2 | **$2,320** | 1 |

**$22,156 al mes (2.2% del total) no son ingresos de GP.** Es poco en proporción,
pero mientras estén mezclados toda cifra de facturación de GP está inflada, y el
día que se automatice el timbrado se emitirían CFDI con el RFC equivocado.

Tres cosas a decidir con Eduardo, ninguna urgente pero sí antes de la fase 2:
1. ¿GP le da el servicio operativo y ellos solo facturan aparte? (Entonces las
   9 unidades **sí** son activo de GP y sí cuentan para utilización.)
2. ¿O son operación totalmente ajena que solo comparte la base?
3. ¿El sistema de GP debe emitir sus comprobantes, o eso lo hace su propia
   administración? (Si es lo segundo — lo más probable dado que las finanzas van
   aparte — GP nunca timbra por ellos y basta con marcarlos y excluirlos.)

### Se desbloquea solo al terminar
- Dashboard de operadores con datos (ya construido).
- Descuento de insumos (ya construido).
- Facturación mensual automática (corregida).
- Cumplimiento semanal: completados ÷ programados.
- Utilización de flota real y auditable.

**Esta fase casi no construye nada nuevo. Enciende lo que ya está construido.**

---

## Fase 2 · Las entidades que faltan (6–10 semanas)

| Entregable | Referencia | Desbloquea |
|---|---|---|
| Tabla `clientes` + contactos | `04` §Cambio 1 | Cartera, concentración de ingresos, RFC para CFDI |
| Tabla `sitios` | `04` §Cambio 2 | Varias obras por cliente sin duplicar contratos |
| `entidades_facturacion` + `es_fiscal` | `04` §Cambio 3 | Ingresos de GP separados de los de las hermanas |
| `fecha_fin` + estados de contrato | `04` §Cambio 4 | Renovaciones, churn, alertas |
| Evidencias en tabla propia | `04` §Cambio 7 | Regla "sin foto no se completa" |
| Servicio ↔ unidades N:N | `04` §Cambio 6 | Una visita sirve varias unidades |
| Limpiar los 39 descuadres de flota | `04` §Cambio 10 | Integridad; después el trigger |
| Roles y RLS ampliados | `04` §Cambio 13 | Integraciones y clientes escriben seguro |

### KPIs que se vuelven calculables
`Ingreso por unidad activa` · `Costo por servicio` · `Servicios por ruta` ·
`Utilización de flota` · `Productividad por operador` · `Concentración de cliente` ·
`Antigüedad de cartera` · `Margen por contrato`

---

## Fase 3 · Historial e inteligencia (3–6 meses)

| Entregable | Referencia |
|---|---|
| `unidad_movimientos` (historial de activo) | `04` §Cambio 8 |
| `domain_events` como bus real | `04` §Cambio 12 |
| Registro de mantenimientos en uso | Dominio Flota |
| `collection_actions` + cobranza automatizada | AUT-12 |
| Cotizaciones | Dominio Comercial |
| Vistas materializadas + Metabase | `05` §Warehouse |
| Corte semanal automático (reemplaza el manual) | AUT-06 |

---

## Fase 4 · Lo sofisticado (6–12 meses)

Solo después de las tres anteriores:

GPS en tiempo real · optimización automática de rutas · forecast de demanda ·
mantenimiento predictivo · detección de anomalías · pricing inteligente ·
predicción de churn · agentes de IA operativos · document intelligence / OCR

Cada uno de estos necesita **meses de historial limpio**. Empezarlos antes es
construir sobre datos que todavía no existen.

---

## Cronograma

```text
Semana 0     ████                          Decisiones (resueltas)
Semanas 1-6  ████████████████              FASE 1 · Que el río corra
Semanas 5-14 ░░░░██████████████████      FASE 2 · Entidades faltantes
Mes 4-9      ░░░░░░░░██████████████████  FASE 3 · Historial e inteligencia
Mes 9+       ░░░░░░░░░░░░░░░░████████████  FASE 4 · Sofisticación
```

---

## Las métricas del roadmap

Cómo saber que esto va bien, sin abrir un tablero:

| Métrica | Hoy | Meta fase 1 | Meta fase 2 |
|---|---:|---:|---:|
| Servicios registrados por semana | **0** | > 400 | > 500 |
| Visitas de SimpliRoute sin amarrar a contrato | n/a | < 5% | < 1% |
| Cobros conciliados | **0 / 337** | > 90% | 100% |
| Contratos con plaza asignada | **0 / 194** | 194 / 194 | — |
| Contratos con `monto_mensual` | 161 / 194 | 194 / 194 | — |
| Ingresos de terceros mezclados con los de GP | **$22,156/mes** | $0 (marcados) | $0 |
| Descuadres de flota | 39 | < 10 | 0 |
| Clientes como entidad | 0 | 0 | ~100 |

---

## El error a evitar

El patrón de GP hasta hoy ha sido **construir adelante de los datos**: el módulo
de insumos, el dashboard de operadores y el flujo de facturación están bien
hechos, probados y desplegados — y los tres muestran vacío. El de facturación,
además, se construyó sobre un supuesto equivocado que solo se detectó al
preguntar.

No es tiempo perdido: cuando el río corra, dos encienden solas y una se corrige.
Pero repetir el patrón sí lo sería. **La fase 1 casi no agrega funciones nuevas,
y es la más valiosa de todo el roadmap.**

---

## Siguiente acción concreta

Dos cosas, en paralelo:

1. **Conseguir las credenciales de API de SimpliRoute** y ver qué campo se puede
   usar para amarrar cada visita con su contrato de GP. Eso define si el puente
   se construye en días o en semanas.
2. **Responder la decisión #5** (cobranza en Sheets o en Supabase). Sin eso, la
   facturación automática sigue bloqueada aunque el puente ya funcione.
