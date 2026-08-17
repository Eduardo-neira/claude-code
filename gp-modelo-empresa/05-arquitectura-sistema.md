# 05 · Arquitectura del sistema — Grupo Portátil

> Equivalente GP de las §2, §3, §4 y §24 del blueprint EcoSan.

---

## Las cinco capas, con lo que GP realmente tiene

```text
EXPERIENCIA
├── Dashboard de operadores        ✅ construido (vacío)
├── SimpliRoute (campo)            ✅ en uso — aquí vive el servicio ejecutado
├── AppSheet                       ⚠️ en uso, papel por aclarar
├── Chatbot WhatsApp               ⚠️ 18 FAQ + 5 tarifas, 0 conversaciones
├── Portal de cliente              ❌ no existe
└── Tablero ejecutivo              ⚠️ corte semanal manual

APLICACIÓN
├── n8n (workflows)                ✅ en uso
├── Funciones SQL de dominio       ✅ calcular_tarifa_servicio()
├── Vistas de negocio              ✅ servicios_por_facturar, desempeño
└── API propia                     ❌ no existe (se usa PostgREST de Supabase)

DOMINIO
├── Clientes                       ❌
├── Contratos                      ✅
├── Flota                          ✅
├── Servicios                      ⚠️ modelado, sin datos (viven en SimpliRoute)
├── Rutas                          ⚠️ modelado, sin datos (viven en SimpliRoute)
├── Insumos                        ✅ modelado, sin datos
└── Dinero                         ⚠️ parcial

DATOS
├── PostgreSQL (Supabase)          ✅ gp-inventario
├── PostGIS                        ✅ instalado y en uso
├── Storage                        ⚠️ solo foto_url suelta
├── Data warehouse                 ❌
└── Logs                           ⚠️ event_log vacío

INTELIGENCIA
├── Automatizaciones n8n           ⚠️ construidas, sin activar
├── Agentes IA                     ⚠️ chatbot incipiente
├── RAG                            ⚠️ knowledge en skills
├── Forecasting                    ❌
└── BI                             ❌
```

**Patrón:** GP está fuerte en las capas de abajo (datos, dominio) y en las
herramientas de arriba. **Lo que falta es el cableado del medio** — que lo que
pasa en campo llegue a la base.

---

## Stack real vs stack EcoSan

| Componente | EcoSan propone | GP tiene | Veredicto |
|---|---|---|---|
| Base de datos | PostgreSQL | ✅ Supabase Postgres 17 | Igual |
| Backend platform | Supabase | ✅ Supabase | Igual |
| Auth | Supabase Auth | ✅ `perfiles` + RLS | Falta ampliar roles |
| Storage | Supabase Storage / S3 | ⚠️ parcial | Formalizar para evidencias |
| Automatización | n8n | ✅ n8n | Igual |
| Geoespacial | *(no lo contempla)* | ✅ **PostGIS** | **GP va adelante** |
| Facturación | *(genérico)* | ✅ Facturama CFDI 4.0 | GP va adelante |
| App de campo | driver-app propia | ✅ **SimpliRoute** | Suficiente. No construir app propia |
| Ruteo | routing service propio | ✅ **SimpliRoute** | Suficiente. Falta sincronizar |
| GPS | *(no lo contempla)* | ✅ Intellihub/Troncalnet | GP va adelante |
| Frontend | Next.js + TypeScript | ⚠️ HTML suelto (dashboard) | Solo si hace falta portal |
| Cache / queues | Redis | ❌ | **No se necesita a esta escala** |
| Agentes | LangGraph | ❌ | Prematuro |
| Analítica | Metabase / Power BI | ❌ | Fase 3 |
| dbt | dbt | ❌ | Fase 3 |
| Testing | Vitest / Playwright / Pytest | ⚠️ `node --test` (13 pruebas) | Suficiente por ahora |
| CI/CD | GitHub Actions | ✅ | Igual |
| Monitoring | Sentry + OpenTelemetry | ❌ | Fase 3 |

### Conclusión sobre el stack
**GP no necesita herramientas nuevas.** En varios puntos (PostGIS, GPS,
facturación fiscal mexicana) está por delante del blueprint. Redis, LangGraph,
dbt y un frontend propio son destino, no necesidad. Agregar herramientas ahora
aumenta superficie sin resolver el cuello de botella.

EcoSan propone construir una `driver-app` propia. **GP no la necesita:**
SimpliRoute ya cumple ese papel y además rutea. Construir una app de campo
sería reemplazar algo que funciona y que el equipo ya usa a diario.

---

## El cableado que falta

**Dos puentes** (no tres: SimpliRoute resuelve ruta y servicio en la misma
integración). Son el proyecto entero de la fase 1:

```text
┌─────────────┐   PUENTE 1 (crítico)   ┌──────────────┐
│ SimpliRoute │ ─────────────────────► │   Supabase   │
│   (campo)   │   ruta + paradas       │   rutas      │
│             │   servicio ejecutado   │   servicios  │
│             │   evidencia + GPS      │   evidencias │
└─────────────┘   + tiempos reales     └──────────────┘

┌─────────────┐   PUENTE 2             ┌──────────────┐
│ Banco/Sheet │ ─────────────────────► │   Supabase   │
│ (cobranza)  │   pago conciliado      │   cobros     │
└─────────────┘                        └──────────────┘
```

**Confirmado por Eduardo (2026-08-17):** el operador cierra la visita en
**SimpliRoute**, no en AppSheet. Eso simplifica la arquitectura: una sola
integración trae la ruta, sus paradas, los tiempos reales, el checkout con GPS y
la evidencia.

**Puente 1 es el que manda.** Sin él no hay dashboard, ni facturación, ni
insumos, ni KPIs. Los campos de destino ya existen y fueron diseñados para esto:
`servicios.simpliroute_visit_id`, `servicios.source`, `servicios.checkout_lat/lng`,
`servicios.checkout_time`, `servicios.hora_llegada`, `rutas.simpliroute_id`,
`rutas.simpliroute_url`.

### Ventaja frente al plan anterior
SimpliRoute expone API REST y webhooks: el dato se jala por sistema, sin depender
de que el operador capture dos veces. Un puente desde una app de campo genérica
habría requerido cambiar el hábito en campo; este no.

⚠️ **Pendiente:** aclarar qué papel cumple **AppSheet** hoy, si no es el cierre
de servicio. Hasta saberlo no se puede decidir si se conserva, se reduce o se retira.

---

## Repositorio — dos opciones

### Opción A · Monorepo `gp-platform` (lo que propone EcoSan)
```text
gp-platform/
├── apps/          admin · portal-cliente · dashboard
├── modules/       clientes · contratos · flota · servicios · rutas · dinero
├── packages/      database · auth · ui · validacion
├── services/      notificaciones · documentos · integraciones
├── supabase/      migrations · seeds · functions
├── automation/    n8n
├── docs/          este directorio
└── tests/
```
**A favor:** una sola fuente de verdad, refactor global fácil.
**En contra:** GP no tiene apps propias todavía. Sería una estructura vacía.

### Opción B · Módulos en este repo (lo que hay hoy)
```text
claude-code/
├── gp-modelo-empresa/       ← documentación (este directorio)
├── gp-flujo-facturacion/    ← facturación
└── operaciones/
    ├── inventario-insumos/
    └── dashboard-desempeno-operadores/
```
**A favor:** ya funciona, cero migración.
**En contra:** este repo es un fork de `claude-code` — mezcla código de GP con
código ajeno. A mediano plazo confunde.

### Recomendación
**Opción B hasta terminar la fase 1; después migrar a un repo `gp-platform` propio.**
Motivo: la fase 1 es SQL, n8n e integración con SimpliRoute — casi no toca
estructura de repo. Reorganizar antes gasta tiempo en carpetas en vez de en el
cuello de botella.

⚠️ Independientemente de la opción: **el código de GP debería salir del fork de
`claude-code`**. Hoy convive con `examples/`, `plugins/` y el `CHANGELOG.md` de
Anthropic, y eso ya es ruido.

---

## Data warehouse (§24) — todavía no

EcoSan propone modelo estrella con `fact_services`, `fact_invoices`,
`dim_customer`, etc.

**Para GP es prematuro.** Un warehouse carga hechos, y los hechos son
`servicios`, `facturas` y `cobros` conciliados — las tres tablas vacías.

Cuando existan, la ruta correcta:
1. Vistas materializadas en el mismo Postgres (suficiente hasta ~10M filas).
2. Metabase apuntando a esas vistas.
3. Solo entonces, si hace falta, warehouse aparte + dbt.

A la escala de GP (194 contratos, ~500 servicios/semana), **Postgres solo aguanta
años de analítica.** Separar el warehouse antes de necesitarlo es complejidad sin retorno.

---

## Seguridad

| Tema | Estado |
|---|---|
| RLS habilitado | ✅ en todas las tablas de negocio |
| `spatial_ref_sys` sin RLS | ⚠️ tabla de sistema PostGIS, riesgo bajo (ver `00-diagnostico` §7) |
| Vista expuesta a `anon` | ⚠️ `vista_desempeno_operadores` — solo agregados, aceptable |
| Roles de aplicación | ⚠️ solo `admin` y `oficina` |
| Auditoría de cambios | ❌ no existe |
| Credenciales de SimpliRoute | `[?]` a resguardar en n8n al construir el puente |

**Prioridad de seguridad:** ampliar roles **antes** de que el chatbot y las
integraciones escriban en Supabase. Un token con la llave equivocada puede leer
precios y cartera completa.
