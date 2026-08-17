# gp-modelo-empresa

Modelo de empresa de **Grupo Portátil**, construido trasladando el blueprint
ficticio *EcoSan Servicios Móviles* a la realidad de GP.

Ese blueprint describe una empresa ideal. Estos documentos describen **la
empresa real**, medida contra la base de datos de producción, y el camino de
una a otra.

---

## Documentos

| Doc | Contenido | Base |
|---|---|---|
| [`00-diagnostico-gp-vs-ecosan.md`](00-diagnostico-gp-vs-ecosan.md) | **Empieza aquí.** Qué tenemos, qué no, y qué hay que modificar | Datos reales |
| [`01-modelo-empresa.md`](01-modelo-empresa.md) | Identidad, áreas, equipo, productos, reglas | Datos reales |
| [`02-procesos-negocio.md`](02-procesos-negocio.md) | Los 6 procesos, con dónde se rompe cada uno | Datos + skills |
| [`03-modelo-dominio.md`](03-modelo-dominio.md) | Entidades, estados, reglas y eventos por dominio | Datos reales |
| [`04-modelo-datos.md`](04-modelo-datos.md) | 13 cambios de schema con SQL. **Nada aplicado** | Schema real |
| [`05-arquitectura-sistema.md`](05-arquitectura-sistema.md) | Capas, stack, los puentes que faltan, repo | Stack real |
| [`06-mapa-automatizacion.md`](06-mapa-automatizacion.md) | 11 automatizaciones y qué bloquea cada una | n8n + módulos |
| [`07-roadmap.md`](07-roadmap.md) | Fases 0 a 4, con métricas de avance | — |

---

## Cómo se levantó este diagnóstico

Consultando directamente el proyecto Supabase **`gp-inventario`**
(`dflfvqiwvwvpzspspjfd`) el **2026-08-17**: conteos reales de filas, restricciones,
calidad de campos e invariantes cruzadas entre tablas.

Se cruzó además con:
- Los módulos ya construidos en este repo (`gp-flujo-facturacion/`, `operaciones/`).
- El conocimiento operativo de las skills `mod-operaciones-gp`,
  `geocercas-intellihub` y `reporte-semanal-gp`.

**Regla que se siguió:** ninguna cifra estimada. Lo que no se pudo medir está
marcado `[?]`. Cero proyecciones.

---

## Estado de la base al 2026-08-17

```text
CATÁLOGO (cargado)              FLUJO (vacío)
unidades              437       servicios              0   ← el cuello de botella
cobros                337       rutas                  0
contratos             194       facturas               0
contrato_unidades     192       mantenimientos         0
insumos                 9       movimientos_insumo     0
operadores              5       domain events          0
sucursales              1       clientes          (no existe)
```

**GP sabe qué tiene. No sabe qué pasó.**

---

## Decisiones de Eduardo · 2026-08-17

| Pregunta | Respuesta | Efecto |
|---|---|---|
| ¿Dónde se registra un servicio? | **SimpliRoute** | El dato ya existe: hay que traerlo, no crearlo |
| ¿Torreón y Saltillo? | **Empresas hermanas de familiares, finanzas aparte** | $22,156/mes que hoy cuenta la base **no son ingresos de GP** |
| ¿Querétaro? | **Opera, pero se lleva aparte** | Este sistema es de Monterrey |
| ¿Facturación? | **Mensual por contrato** | El flujo ya construido emite por servicio: hay que corregirlo |
| ¿Cobranza a Supabase? | ⏳ Pendiente | Bloquea la conciliación y con ella la facturación |

---

## Advertencias

1. **Nada de `04-modelo-datos.md` está aplicado.** Es un plan para revisar. La
   base tiene 437 unidades, 194 contratos y 337 cobros reales en producción.
2. La fase 1 **no agrega ninguna función nueva** y es la más valiosa: enciende
   tres módulos ya construidos que hoy muestran vacío.
3. `gp-flujo-facturacion/` está construido con la **granularidad equivocada**
   (por servicio, debe ser mensual por contrato). La fórmula de tarifa se
   conserva; el disparador cambia. Ver `06-mapa-automatizacion` §AUT-01.
