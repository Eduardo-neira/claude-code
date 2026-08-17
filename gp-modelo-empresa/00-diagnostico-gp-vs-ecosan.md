# 00 · Diagnóstico — Grupo Portátil frente al blueprint EcoSan

> Comparación del blueprint ficticio *EcoSan Servicios Móviles* contra la realidad
> operativa y de datos de Grupo Portátil.
>
> **Fecha del corte:** 2026-08-17
> **Fuente de verdad de este documento:** proyecto Supabase `gp-inventario`
> (`dflfvqiwvwvpzspspjfd`), consultado directamente. Ningún número de aquí es
> estimado ni proyectado. Lo que no se pudo medir está marcado `[?]`.

---

## Resumen en una frase

**GP tiene el catálogo, no tiene el flujo.** Sabemos *qué* tenemos (437 unidades,
194 contratos, 192 colocaciones) pero no registramos *qué pasó* (0 servicios,
0 rutas, 0 facturas, 0 cobros conciliados). El blueprint EcoSan vale justo por la
capa que a GP le falta.

---

## 1. Estado real de la base de datos

Conteo real (no estimado) al 2026-08-17:

| Tabla | Filas | Lectura |
|---|---:|---|
| `unidades` | **437** | Catálogo cargado y confiable |
| `cobros` | **337** | Cargados, **ninguno conciliado** |
| `contratos` | **194** | Cargados, con huecos (ver §4) |
| `contrato_unidades` | **192** | Colocaciones vigentes |
| `chatbot_faq` | 18 | Base de conocimiento incipiente |
| `insumos` | 9 | Catálogo listo, sin movimientos |
| `operadores` | 5 | Alberto, Emmanuel, Meñito, Juan Pablo, Extra |
| `tipos_servicio_modificador` | 5 | Listo (LIMPIEZA/ENTREGA/RETIRO/EXTRA/INSPECCION) |
| `geocercas` | 2 | Solo el seed de ejemplo, no las zonas reales |
| `sucursales` | **1** | **Solo MTY** |
| `perfiles` | 1 | Un solo usuario |
| `servicios` | **0** | ⛔ **La tabla madre del negocio, vacía** |
| `rutas` / `ruta_servicios` | 0 | Se opera en SimpliRoute, no se persiste |
| `facturas` | 0 | Se factura en Facturama, no se persiste |
| `mantenimientos` | 0 | No se registra |
| `movimientos_insumo` | 0 | Módulo construido, nunca alimentado |
| `alertas` / `event_log` | 0 | Sin uso |
| `chatbot_solicitudes` | 0 | Sin uso |

### El hallazgo que manda sobre todos los demás

`servicios` está en **0 filas**. Tres módulos ya construidos y desplegados
dependen de esa tabla:

- `vista_desempeno_operadores` → el dashboard de operadores muestra vacío.
- `servicios_por_facturar` → el flujo de facturación automática nunca dispara.
- `movimientos_insumo` (cierre de ruta) → el inventario de insumos nunca descuenta.

No es que estén mal hechos. Es que **están construidos sobre un río que todavía
no corre**. Cualquier inversión en IA, BI o forecasting antes de resolver esto
automatiza el vacío.

---

## 2. El flujo de negocio: EcoSan vs GP

| # | Etapa EcoSan | ¿Existe en GP? | Dónde vive hoy |
|---|---|---|---|
| 1 | Lead | ❌ No | WhatsApp de Eduardo. `chatbot_solicitudes` existe pero vacía |
| 2 | Cliente | ⚠️ Parcial | **No hay tabla `clientes`.** Es `contratos.cliente`, texto libre |
| 3 | Cotización | ❌ No | Se manda por WhatsApp, no queda registro estructurado |
| 4 | Contrato | ✅ Sí | `contratos` (194) — pero sin fecha de fin ni ciclo de vida |
| 5 | Ubicación/Sitio | ⚠️ Embebido | `direccion_obra` + `latitud`/`longitud` dentro del contrato |
| 6 | Asignación de unidades | ✅ Sí | `contrato_unidades` (192 vigentes) |
| 7 | Programación de servicios | ⚠️ Implícito | `frecuencia` = texto `LMV` / `MJS`. No hay calendario |
| 8 | Ruta | ⚠️ Fuera | SimpliRoute. `rutas` vacía |
| 9 | Servicio realizado | ⚠️ Fuera | **SimpliRoute.** `servicios` = 0 filas |
| 10 | Evidencia | ⚠️ Fuera | SimpliRoute. En la base, un solo campo `foto_url` |
| 11 | Factura | ⚠️ Fuera | Facturama manual. `facturas` = 0 filas |
| 12 | Cobranza | ⚠️ Fuera | Google Sheets `GP_Control_Financiero_2026`. `cobros` sin conciliar |
| 13 | Renovación / seguimiento | ❌ No | **`contratos` no tiene `fecha_fin`.** Imposible calcular vencimientos |

**Tres etapas de trece no existen. Seis están fuera del sistema.**
Solo dos (contrato y asignación) viven realmente en la base.

---

## 3. Fuentes de verdad partidas

La sección 32 de EcoSan advierte: *"no crearía un sistema separado para cada
departamento"*. En GP eso ya está pasando:

| Qué | Dónde vive | Quién lo mantiene |
|---|---|---|
| Contratos y unidades | Supabase `gp-inventario` | Sistema |
| Dinero (facturado, cobrado, banco) | Google Sheets `GP_Control_Financiero_2026` | Administración |
| **Rutas y servicios ejecutados** | **SimpliRoute** | Iván / operadores |
| Geocercas / GPS | Intellihub (Troncalnet) | Manual, vía navegador |
| Rutas del mes | Excel `RUTAS WC <mes>.xlsx` | Manual |
| CFDI | Facturama | Administración |
| Querétaro | Aparte, por decisión | — |

Nada de esto se concilia solo. El corte semanal existe justamente porque hay que
pegar a mano lo que el sistema debería tener junto.

---

## 4. Calidad de los datos que sí tenemos

Medido sobre los 194 contratos activos:

| Hallazgo | Cifra | Impacto |
|---|---:|---|
| Contratos **sin sucursal asignada** | **194 de 194** | Ningún análisis por plaza es posible en la base |
| Contratos sin coordenadas | 60 | Sin recargo por geocerca **y** sin amarre por coordenada con SimpliRoute |
| Contratos sin `monto_mensual` | 33 | La facturación contratada no se puede sumar |
| Contratos sin contacto de oficina | 32 | Cobranza automatizada sin destinatario |
| Contratos activos **sin cobro de agosto** | 38 | ¿Hueco de captura o excepción legítima? |
| Contratos activos **sin unidad asignada** | 12 | ¿Contrato fantasma o colocación no registrada? |
| Unidades `EN_CAMPO` sin colocación vigente | 11 | La unidad está en la calle sin contrato que la respalde |
| Colocaciones vigentes de unidad que **no** está `EN_CAMPO` | 16 | El estatus y la colocación se contradicen |
| Clientes como texto distinto | 106 | Se normalizan a ~100 ⇒ **~6 duplicados** por escritura |
| Contratos sin fecha | 1 | Fila basura (`cliente = ''`, `datos_fiscales = 'nan'`) |

### Cobros: el problema más caro

- **337 cobros**, periodos julio–septiembre 2026, por **$1,925,770 MXN**.
- **337 de 337 en estado `pendiente`. Cero con `fecha_pago`.**

Consecuencias directas:
1. El modelo de negocio de GP es **cobro anticipado**, y la base no tiene ni un
   solo pago registrado. La regla más importante del negocio no está en los datos.
2. La vista `servicios_por_facturar` exige `cobros.estado = 'pagado'`.
   Con cero pagados, **el flujo de facturación nunca emitirá nada**, aunque se
   conecte perfecto.

**Lo que sí está bien:** `cobros` es exactamente **1 por contrato por periodo**
(156 en agosto, 156 en septiembre) y el monto **coincide al centavo** con
`contratos.monto_mensual` en los 126 casos donde ese campo existe. Cero
discrepancias. La estructura mensual es correcta; falta conciliarla.

### `datos_fiscales` está cargando tres cosas a la vez

| Valor | Contratos |
|---|---:|
| `FACTURA` | 158 |
| `REMISION` | 25 |
| `FACTURA TORREON` | 8 |
| `FACTURA SALTILLO` | 2 |
| `nan` | 1 |

Un solo campo de texto está mezclando **(a)** si el comprobante es fiscal,
**(b)** qué razón social lo emite y **(c)** basura de importación.

**Confirmado por Eduardo:** Torreón y Saltillo son **empresas hermanas de
familiares, con administración y finanzas aparte**. No son plazas de operación
(sus obras están en Nuevo León) ni divisiones de GP. Ver §9.

### Querétaro no está en la base — y así se queda

- Las **437 unidades** tienen prefijo de código `MTY`. Ninguna QRO.
- Todas las coordenadas caen en el área metropolitana de Monterrey
  (lat 25.43–25.93, lng −100.53 a −100.34).
- `sucursales` tiene **una sola fila**: Monterrey.

**Decisión de Eduardo:** QRO opera pero se lleva aparte. Este sistema es de
Monterrey. Consecuencia asumida: la métrica MTY+QRO del corte semanal seguirá
armándose a mano.

---

## 5. Lo que GP tiene y EcoSan no contempla

El blueprint no es superior en todo. Hay cosas reales de GP que EcoSan ignora y
que **no debemos perder** al migrar:

| Concepto GP | Qué es | Por qué importa |
|---|---|---|
| **`frecuencia` LMV / MJS** | Bandas fijas de día de semana (Lun-Mié-Vie / Mar-Jue-Sáb): 106 y 85 contratos | EcoSan asume frecuencia genérica ("semanal"). GP opera con días fijos. El calendario de servicios debe generarse de aquí |
| **`tipo_servicio` TERCIADO** | 3 servicios por semana — 175 de 194 contratos | Es el producto dominante de GP. No aparece en EcoSan |
| **Cobro anticipado** | Sin pago no hay servicio | EcoSan factura *después* del servicio. En GP la regla es al revés |
| **Facturación mensual por contrato** | El comprobante no sigue al servicio | EcoSan liga factura a servicio. En GP son ciclos distintos |
| **`propietario` GP/CLIENTE** | 8 unidades son del cliente; damos servicio sin ser dueños | Cambia el cálculo de "Revenue per Active Asset" |
| **`modalidad`** renta / venta / solo_servicio | 189 renta + 5 solo_servicio | EcoSan solo modela renta |
| **`monto_mensual` vs `monto_unico`** | Ya separa recurrente de no recurrente | Es más fino que EcoSan; conservarlo |
| **Recargo por geocerca** | Tarifa que depende de la zona (PostGIS ya instalado) | EcoSan no tiene pricing geográfico. GP sí, y ya está construido |
| **FACTURA vs REMISION** | No todo cliente pide CFDI | EcoSan asume que todo se factura |
| **SimpliRoute como app de campo** | Rutea *y* registra la ejecución | EcoSan propone construir una `driver-app` propia. GP no la necesita |

---

## 6. Veredicto por sección del blueprint

| § | Tema EcoSan | Estado GP | Acción |
|---|---|---|---|
| 1 | Áreas de la empresa | Parcial — GP no tiene comercial, RH, compras ni datos formalizados | Documentar el organigrama real, no el ideal |
| 2 | 5 capas conceptuales | Existe de facto, sin nombrarse | Formalizar en `05-arquitectura` |
| 3 | Stack | **Muy avanzado**: Supabase, n8n, PostGIS, Facturama, SimpliRoute ya operan | No agregar herramientas. Conectar las que hay |
| 4 | Monorepo `ecosan-platform` | ❌ No existe. Hoy son carpetas sueltas en `claude-code` | Decisión pendiente |
| 5 | `customers` | ❌ **No existe la tabla** | **Crear. Prioridad 1** |
| 6 | `contacts` | ⚠️ 3 campos sueltos en contrato | Extraer a tabla |
| 7 | `sites` | ⚠️ Embebido en contrato | Extraer a tabla |
| 8 | `assets` | ✅ **Sí, 437 unidades con código único** | Mantener. Falta `qr_code` y desgaste |
| 9 | `asset_movements` (historial) | ❌ No hay historial, solo estado actual | **Crear. Prioridad 2** |
| 10 | `quotes` | ❌ No existe | Crear (fase 3) |
| 11 | `contracts` | ✅ Sí, pero sin `fecha_fin` ni ciclo de vida | **Modificar** |
| 12 | `service_orders` | ⚠️ Tabla existe y bien diseñada, **0 filas** | **Alimentarla desde SimpliRoute. Prioridad 1** |
| 13 | Detalle por activo | ❌ `servicios` liga a *una* unidad | Modificar a relación N:N |
| 14 | `service_evidence` | ⚠️ Un campo `foto_url` | **Extraer a tabla** |
| 15 | `routes` / `route_stops` | ⚠️ Tablas existen vacías; se opera en SimpliRoute | Sincronizar (mismo puente que §12) |
| 16 | `vehicles` | ❌ **No existe ninguna tabla de vehículos** | Crear (fase 3) |
| 17 | `invoices` | ⚠️ Tabla lista con `cobro_id`, 0 filas | Alimentar desde Facturama, mensual |
| 18 | `payments` | ⚠️ `cobros` bien estructurado, sin conciliar | **Conciliar. Prioridad 1** |
| 19 | `collection_actions` | ❌ No existe | Crear (fase 3) |
| 20 | `domain_events` | ⚠️ `event_log` existe pero es log de webhooks, vacío | Diseñar bus aparte |
| 21 | Automatización n8n | ⚠️ Construida, pero AUT-01 con granularidad equivocada | Corregir y activar |
| 22 | Agentes IA | ⚠️ Chatbot con 18 FAQ y 5 tarifas | Base lista, sin conversaciones |
| 23 | Knowledge base | ⚠️ Vive en skills y SOPs | Consolidar y corregir (dice AppSheet) |
| 24 | Data warehouse | ❌ No existe | Fase 3 |
| 25 | Dashboard ejecutivo | ⚠️ Existe el de operadores (vacío) + corte semanal manual | Fase 2 |
| 26 | KPIs | ⚠️ Definidos en skills, no calculables por falta de datos | Se desbloquean al llenar `servicios` |
| 27-28 | Documentación | ❌ No existía estructura formal | **Este directorio la inicia** |
| 29 | Permisos | ⚠️ `perfiles.rol` = solo `admin` / `oficina` | Faltan operaciones, cobranza, cliente, dirección |
| 30 | Convenciones | ⚠️ Mezcla `integer` y `uuid`; `numeric` correcto; sin auditoría | Fijar convención (ver `04-modelo-datos`) |
| 31 | Relaciones | Núcleo correcto, faltan las entidades de §5-7 | — |
| 32 | Antipatrones | ⚠️ Ya presente: fuentes partidas y `datos_fiscales` sobrecargado | Corregir |
| 33 | Sofisticación futura | Prematuro | Después de fase 1 |

---

## 7. Riesgo de seguridad detectado

El asesor de Supabase reporta: **`public.spatial_ref_sys` tiene RLS deshabilitado**.
Es una tabla de sistema de PostGIS (catálogo de sistemas de coordenadas), así que
el riesgo real es bajo — no contiene datos de GP. Aun así queda expuesta a la
llave anónima.

```sql
-- Presentado para decisión, NO aplicado:
ALTER TABLE public.spatial_ref_sys ENABLE ROW LEVEL SECURITY;
```

⚠️ Activar RLS sin políticas **bloquea todo acceso** a esa tabla, y las funciones
PostGIS la consultan. No se aplicó. Recomendación: dejarla como está y, si se
quiere cerrar el hallazgo, habilitar RLS con una política de solo lectura pública.

Nota aparte: `vista_desempeno_operadores` está expuesta a `anon` a propósito
(el dashboard la consulta con la llave pública). Solo expone conteos agregados
por operador y semana. Es aceptable hoy, pero conviene revisarlo si el dashboard
se publica fuera de la empresa.

---

## 8. Las tres cosas que hay que arreglar primero

Todo lo demás depende de estas. En este orden:

### 1. Que `servicios` deje de estar vacía
Es la bisagra de todo el negocio. Sin ella no hay dashboard, ni facturación
automática, ni consumo de insumos, ni un solo KPI.

**Resuelto (2026-08-17):** el registro vive en **SimpliRoute**. El dato existe y
está completo — hora, coordenada, evidencia. Falta el puente
**SimpliRoute → Supabase**, que la tabla ya anticipaba con
`servicios.simpliroute_visit_id`, `servicios.source`, `rutas.simpliroute_id` y
`rutas.simpliroute_url`.

El problema real no es traer los datos, es **amarrar cada visita de SimpliRoute
con su contrato de GP**. Ver `06-mapa-automatizacion` §AUT-07.

### 2. Que los cobros se concilien
337 pendientes por $1.93M y cero pagos registrados. Mientras la base no sepa
quién pagó, la regla de cobro anticipado no se puede aplicar automáticamente y
el flujo de facturación queda inerte por diseño.

### 3. Que exista `clientes` como entidad
Hoy el cliente es un texto dentro del contrato. Eso impide: saldo por cliente,
concentración de ingresos (métrica #5 del corte semanal), historial, RFC para
CFDI, y detectar que `GTC TERMO CONTROL` son 4 contratos del mismo cliente y no 4 clientes.

---

## 9. Decisiones — resueltas 2026-08-17

| Pregunta | Respuesta de Eduardo |
|---|---|
| ¿Dónde se registra un servicio realizado? | **SimpliRoute** |
| ¿"FACTURA TORREON" / "FACTURA SALTILLO"? | **Razones sociales distintas — empresas hermanas de familiares, con administración y finanzas aparte** |
| ¿Querétaro entra a esta base? | **No. Opera, pero se lleva aparte** |
| ¿Comprobante por servicio o mensual? | **Mensual por contrato** |
| ¿La cobranza migra de Sheets a Supabase? | ⏳ **Pendiente** |

### Cómo cambió el diagnóstico

**Mejoró.** El registro del servicio **sí existe** — está en SimpliRoute con
hora, coordenada y evidencia. No hay que crear el dato ni cambiar hábitos en
campo: hay que traerlo. El trabajo es de integración, y SimpliRoute tiene API.

Además los dos puentes que planteaba se vuelven **uno solo**: la misma
integración trae la ruta, sus paradas, los tiempos reales y los servicios
ejecutados.

**Y apareció un error propio.** El flujo `gp-flujo-facturacion` se construyó
emitiendo **un comprobante por servicio**. GP factura **mensual por contrato**.
Con contratos `TERCIADO` (3 servicios/semana) eso son ~12 documentos al mes por
cliente en vez de 1. La buena noticia: la tabla `cobros` **ya es la unidad
mensual correcta** (verificado: exactamente 1 cobro por contrato por periodo, y
el monto coincide al centavo con `monto_mensual` en los 126 casos donde existe),
y `facturas.cobro_id` ya está en el schema. Lo que se corrige es el disparador,
no el modelo.

**Y apareció un tema nuevo.** Con las hermanas siendo empresas de terceros,
**$22,156 mensuales de los que hoy cuenta esta base no son ingresos de GP**
(8 contratos de Torreón por $19,836 + 2 de Saltillo por $2,320 — 2.2% del total).
Mientras estén mezclados, toda cifra de facturación de GP está inflada.
Ver `04-modelo-datos` §Cambio 3.

### Lo que sigue abierto

1. **Cobranza:** ¿el Google Sheet `GP_Control_Financiero_2026` sigue siendo la
   fuente de verdad del dinero, o administración captura en Supabase?
   Bloquea la conciliación, y la conciliación bloquea toda la facturación.
2. **¿Qué hace AppSheet hoy?** Si no captura el cierre de servicio, hay que saber
   para qué se usa antes de decidir si se conserva.
3. **Las hermanas:** ¿GP les da el servicio operativo (y entonces sus 9 unidades
   sí son activo de GP), o es operación ajena que solo comparte la base?
4. **Repositorio:** ¿monorepo `gp-platform` o seguimos con módulos sueltos aquí?

---

## 10. Lo que NO recomiendo hacer todavía

- No construir data warehouse ni BI: no hay hechos que cargar.
- No agregar agentes de IA sobre operaciones: consultarían tablas vacías.
- No construir una app de campo propia: SimpliRoute ya cumple ese papel y además
  rutea. Reemplazarla sería tirar algo que el equipo ya usa a diario.
- No comprar ni integrar herramientas nuevas: el stack actual está sobrado para
  el tamaño del problema. Lo que falta es **conectarlo**, no ampliarlo.
- No migrar a monorepo antes de resolver el punto 8.1.
