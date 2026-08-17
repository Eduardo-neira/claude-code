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

## Fase 0 · Decisiones (esta semana)

Ninguna línea de código depende de esto, pero el diseño sí.

| # | Decisión | Quién | Bloquea |
|---|---|---|---|
| 1 | ¿Dónde queda hoy el registro de un servicio hecho? | Eduardo | AUT-07, toda la fase 1 |
| 2 | ¿Torreón y Saltillo son razones sociales con RFC propio? | Eduardo | Modelo fiscal, CFDI |
| 3 | ¿QRO entra a esta base o va aparte? | Eduardo | Modelo de plazas |
| 4 | ¿La cobranza migra de Sheets a Supabase? | Eduardo + administración | AUT-09 |
| 5 | ¿Comprobante por servicio o mensual por cobro? | Eduardo | AUT-01 |

---

## Fase 1 · Que el río corra (4–6 semanas)

**Objetivo único: que `servicios` y `cobros` reflejen la realidad.**

| Entregable | Detalle | Éxito |
|---|---|---|
| Puente AppSheet → Supabase | AUT-07 | `servicios` con datos reales cada día |
| Calendario semanal | AUT-10 + `generar_servicios_semana()` | Servicios programados cada domingo |
| `completado` default `false` | `04` §Cambio 11 | Se distingue planeado de ejecutado |
| Alta de sucursal QRO + poblar `sucursal_id` | `04` §Cambio 5 | 0 contratos sin plaza (hoy 194) |
| Conciliación de cobros | AUT-09 | Cobros `pagado` con `fecha_pago` |
| Completar 33 `monto_mensual` | Captura manual | Ingreso recurrente calculable |
| Completar 60 coordenadas | Captura manual | Recargo por zona resoluble |
| Limpiar la fila basura (`nan`) | 1 registro | — |

### Se desbloquea solo al terminar
- Dashboard de operadores con datos (ya construido).
- Descuento de insumos (ya construido).
- Facturación automática (ya construida).
- Cumplimiento semanal: completados ÷ programados.
- Utilización de flota real y auditable.

**Esta fase no construye nada nuevo. Enciende lo que ya está construido.**

---

## Fase 2 · Las entidades que faltan (6–10 semanas)

| Entregable | Referencia | Desbloquea |
|---|---|---|
| Tabla `clientes` + contactos | `04` §Cambio 1 | Cartera, concentración de ingresos, RFC para CFDI |
| Tabla `sitios` | `04` §Cambio 2 | Varias obras por cliente sin duplicar contratos |
| `emisores` + `es_fiscal` | `04` §Cambio 3 | CFDI con la razón social correcta |
| `fecha_fin` + estados de contrato | `04` §Cambio 4 | Renovaciones, churn, alertas |
| Evidencias en tabla propia | `04` §Cambio 7 | Regla "sin foto no se completa" |
| Servicio ↔ unidades N:N | `04` §Cambio 6 | Una visita sirve varias unidades |
| Limpiar los 39 descuadres de flota | `04` §Cambio 10 | Integridad; después el trigger |
| Sincronía SimpliRoute → Supabase | AUT-08 | Km, tiempos, costo por ruta |
| Roles y RLS ampliados | `04` §Cambio 13 | Operador y cliente pueden escribir seguro |

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
Semana 0     ████                          Decisiones
Semanas 1-6  ████████████████              FASE 1 · Que el río corra
Semanas 5-14 ░░░░██████████████████      FASE 2 · Entidades faltantes
Mes 4-9      ░░░░░░░░██████████████████  FASE 3 · Historial e inteligencia
Mes 9+       ░░░░░░░░░░░░░░░░████████████  FASE 4 · Sofisticación
```

---

## Las tres métricas del roadmap

Cómo saber que esto va bien, sin abrir un tablero:

| Métrica | Hoy | Meta fase 1 | Meta fase 2 |
|---|---:|---:|---:|
| Servicios registrados por semana | **0** | > 400 | > 500 |
| Cobros conciliados | **0 / 337** | > 90% | 100% |
| Contratos con plaza asignada | **0 / 194** | 194 / 194 | — |
| Contratos con `monto_mensual` | 161 / 194 | 194 / 194 | — |
| Descuadres de flota | 39 | < 10 | 0 |
| Clientes como entidad | 0 | 0 | ~100 |

---

## El error a evitar

El patrón de GP hasta hoy ha sido **construir adelante de los datos**: el módulo
de insumos, el dashboard de operadores y el flujo de facturación están bien
hechos, probados y desplegados — y los tres muestran vacío.

No es tiempo perdido: cuando el río corra, tres cosas encienden solas. Pero
repetir el patrón sí lo sería. **La fase 1 no agrega ninguna función nueva a GP,
y es la más valiosa de todo el roadmap.**

---

## Siguiente acción concreta

Responder la decisión #1: **¿dónde queda hoy el registro de un servicio hecho?**

- Si **AppSheet ya lo captura** → el trabajo es un webhook a n8n. Días, no semanas.
- Si **se anota en papel o Excel** → primero hay que llevar la captura a AppSheet,
  y eso es cambio de hábito en campo, no software.

Todo el roadmap cambia de tamaño según esa respuesta.
