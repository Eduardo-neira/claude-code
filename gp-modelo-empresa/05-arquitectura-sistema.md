# 05 · Arquitectura del sistema — Grupo Portátil

> Equivalente GP de las §2, §3, §4 y §24 del blueprint EcoSan.

---

## Las cinco capas, con lo que GP realmente tiene

```text
EXPERIENCIA
├── Dashboard de operadores        ✅ construido (vacío)
├── AppSheet (campo)               ✅ en uso
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
├── Servicios                      ⚠️ modelado, sin datos
├── Rutas                          ⚠️ modelado, sin datos
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
| App de campo | driver-app propia | ✅ **AppSheet** | Suficiente. No construir app propia |
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

---

## El cableado que falta

Tres puentes. Son el proyecto entero de la fase 1:

```text
┌────────────┐   PUENTE 1 (crítico)   ┌─────────────┐
│  AppSheet   │ ───────────────────► │   Supabase   │
│  (campo)    │   servicio ejecutado   │  servicios   │
└─────────────┘   + evidencia + GPS    └─────────────┘

┌────────────┐   PUENTE 2             ┌─────────────┐
│ SimpliRoute │ ───────────────────► │   Supabase   │
│  (rutas)    │   ruta + paradas       │ rutas        │
└─────────────┘   + tiempos reales     └─────────────┘

┌────────────┐   PUENTE 3             ┌─────────────┐
│ Banco/Sheet │ ───────────────────► │   Supabase   │
│ (cobranza)  │   pago conciliado      │ cobros       │
└─────────────┘                        └─────────────┘
```

**Puente 1 es el que manda.** Sin él no hay dashboard, ni facturación, ni
insumos, ni KPIs. Los campos de destino ya existen (`checkout_lat`,
`checkout_lng`, `checkout_time`, `simpliroute_visit_id`, `checklist_ok`).

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
├── gp-flujo-facturacion/    ← facturación post-servicio
└── operaciones/
    ├── inventario-insumos/
    └── dashboard-desempeno-operadores/
```
**A favor:** ya funciona, cero migración.
**En contra:** este repo es un fork de `claude-code` — mezcla código de GP con
código ajeno. A mediano plazo confunde.

### Recomendación
**Opción B hasta terminar la fase 1; después migrar a un repo `gp-platform` propio.**
Motivo: la fase 1 es SQL, n8n y AppSheet — casi no toca estructura de repo.
Reorganizar antes gasta tiempo en carpetas en vez de en el cuello de botella.

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
| Secretos | `[?]` no auditado en este corte |

**Prioridad de seguridad:** ampliar roles **antes** de que AppSheet y el chatbot
escriban en Supabase. Un operador con la llave equivocada puede leer precios y
cartera completa.
