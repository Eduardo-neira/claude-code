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
| `sucursales` | **1** | **Solo MTY. Querétaro no existe en la base** |
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
| 9 | Servicio realizado | ❌ **No se registra** | `servicios` = 0 filas |
| 10 | Evidencia | ⚠️ Mínimo | Un solo campo `servicios.foto_url` |
| 11 | Factura | ⚠️ Fuera | Facturama manual. `facturas` = 0 filas |
| 12 | Cobranza | ⚠️ Fuera | Google Sheets `GP_Control_Financiero_2026`. `cobros` sin conciliar |
| 13 | Renovación / seguimiento | ❌ No | **`contratos` no tiene `fecha_fin`.** Imposible calcular vencimientos |

**Cinco etapas de trece no existen. Cinco están fuera del sistema.**
Solo dos (contrato y asignación) viven realmente en la base.

---

## 3. Fuentes de verdad partidas

La sección 32 de EcoSan advierte: *"no crearía un sistema separado para cada
departamento"*. En GP eso ya está pasando:

| Qué | Dónde vive | Quién lo mantiene |
|---|---|---|
| Contratos y unidades | Supabase `gp-inventario` | Sistema |
| Dinero (facturado, cobrado, banco) | Google Sheets `GP_Control_Financiero_2026` | Administración |
| Ejecución de campo | AppSheet | Operadores |
| Rutas | SimpliRoute | Iván / operadores |
| Geocercas / GPS | Intellihub (Troncalnet) | Manual, vía navegador |
| Rutas del mes | Excel `RUTAS WC <mes>.xlsx` | Manual |
| CFDI | Facturama | Administración |

Nada de esto se concilia solo. El corte semanal existe justamente porque hay que
pegar a mano lo que el sistema debería tener junto.

---

## 4. Calidad de los datos que sí tenemos

Medido sobre los 194 contratos activos:

| Hallazgo | Cifra | Impacto |
|---|---:|---|
| Contratos **sin sucursal asignada** | **194 de 194** | Ningún análisis por plaza es posible en la base |
| Contratos sin coordenadas | 60 | La tarifa por geocerca no puede resolverse para ellos |
| Contratos sin `monto_mensual` | 33 | La facturación contratada no se puede sumar |
| Contratos sin contacto de oficina | 32 | Cobranza automatizada sin destinatario |
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
   Con cero pagados, **el flujo de facturación automática nunca emitirá nada**,
   aunque se conecte perfecto.

### `datos_fiscales` está cargando tres cosas a la vez

| Valor | Contratos |
|---|---:|
| `FACTURA` | 158 |
| `REMISION` | 25 |
| `FACTURA TORREON` | 8 |
| `FACTURA SALTILLO` | 2 |
| `nan` | 1 |

Un solo campo de texto está mezclando **(a)** si el comprobante es fiscal,
**(b)** qué razón social lo emite (Torreón / Saltillo) y **(c)** basura de importación.

Verificado: los contratos "TORREON" y "SALTILLO" tienen **obras en Nuevo León**
(Santa Catarina, Guadalupe, Juárez, San Pedro). No son plazas de operación —
son **entidades emisoras distintas**. Para timbrar CFDI reales hace falta saber
qué RFC emite, y hoy esa información solo está insinuada dentro de un string.

### Querétaro no existe en la base

- Las **437 unidades** tienen prefijo de código `MTY`. Ninguna QRO.
- Todas las coordenadas caen en el área metropolitana de Monterrey
  (lat 25.43–25.93, lng −100.53 a −100.34).
- `sucursales` tiene **una sola fila**: Monterrey.

La operación es de dos plazas; **la base es de una**. Todo reporte comparativo
MTY vs QRO hoy se arma fuera del sistema.

---

## 5. Lo que GP tiene y EcoSan no contempla

El blueprint no es superior en todo. Hay cosas reales de GP que EcoSan ignora y
que **no debemos perder** al migrar:

| Concepto GP | Qué es | Por qué importa |
|---|---|---|
| **`frecuencia` LMV / MJS** | Bandas fijas de día de semana (Lun-Mié-Vie / Mar-Jue-Sáb): 106 y 85 contratos | EcoSan asume frecuencia genérica ("semanal"). GP opera con días fijos. El calendario de servicios debe generarse de aquí |
| **`tipo_servicio` TERCIADO** | 3 servicios por semana — 175 de 194 contratos | Es el producto dominante de GP. No aparece en EcoSan |
| **Cobro anticipado** | Sin pago no hay servicio | EcoSan factura *después* del servicio. En GP la regla es al revés |
| **`propietario` GP/CLIENTE** | 8 unidades son del cliente; damos servicio sin ser dueños | Cambia el cálculo de "Revenue per Active Asset": no todas las unidades son activo de GP |
| **`modalidad`** renta / venta / solo_servicio | 189 renta + 5 solo_servicio | EcoSan solo modela renta |
| **`monto_mensual` vs `monto_unico`** | Ya separa recurrente de no recurrente | Es más fino que EcoSan; conservarlo |
| **Recargo por geocerca** | Tarifa que depende de la zona (PostGIS ya instalado) | EcoSan no tiene pricing geográfico. GP sí, y ya está construido |
| **FACTURA vs REMISION** | No todo cliente pide CFDI | EcoSan asume que todo se factura |

---

## 6. Veredicto por sección del blueprint

| § | Tema EcoSan | Estado GP | Acción |
|---|---|---|---|
| 1 | Áreas de la empresa | Parcial — GP no tiene comercial, RH, compras ni datos formalizados | Documentar el organigrama real, no el ideal |
| 2 | 5 capas conceptuales | Existe de facto, sin nombrarse | Formalizar en `05-arquitectura` |
| 3 | Stack | **Muy avanzado**: Supabase, n8n, PostGIS, Facturama, AppSheet, SimpliRoute ya operan | No agregar herramientas. Conectar las que hay |
| 4 | Monorepo `ecosan-platform` | ❌ No existe. Hoy son carpetas sueltas en `claude-code` | Decisión pendiente (§ Decisiones) |
| 5 | `customers` | ❌ **No existe la tabla** | **Crear. Prioridad 1** |
| 6 | `contacts` | ⚠️ 3 campos sueltos en contrato | Extraer a tabla |
| 7 | `sites` | ⚠️ Embebido en contrato | Extraer a tabla |
| 8 | `assets` | ✅ **Sí, 437 unidades con código único** | Mantener. Falta `qr_code` y desgaste |
| 9 | `asset_movements` (historial) | ❌ No hay historial, solo estado actual | **Crear. Prioridad 2** |
| 10 | `quotes` | ❌ No existe | Crear (fase 2) |
| 11 | `contracts` | ✅ Sí, pero sin `fecha_fin` ni ciclo de vida | **Modificar** |
| 12 | `service_orders` | ⚠️ Tabla existe, **0 filas** | **Alimentarla. Prioridad 1** |
| 13 | Detalle por activo | ❌ `servicios` liga a *una* unidad | Modificar a relación N:N |
| 14 | `service_evidence` | ⚠️ Un campo `foto_url` | **Extraer a tabla** |
| 15 | `routes` / `route_stops` | ⚠️ Tablas existen vacías; se opera en SimpliRoute | Sincronizar desde SimpliRoute |
| 16 | `vehicles` | ❌ **No existe ninguna tabla de vehículos** | Crear (fase 2) |
| 17 | `invoices` | ⚠️ Tabla lista, 0 filas | Alimentar desde Facturama |
| 18 | `payments` | ⚠️ `cobros` sin conciliar | **Conciliar. Prioridad 1** |
| 19 | `collection_actions` | ❌ No existe | Crear (fase 2) |
| 20 | `domain_events` | ⚠️ `event_log` existe pero es log de webhooks, vacío | Rediseñar como bus de eventos |
| 21 | Automatización n8n | ✅ Parcial: workflow de facturación construido, sin activar | Activar cuando haya servicios y cobros |
| 22 | Agentes IA | ⚠️ Chatbot con 18 FAQ y 5 tarifas | Base lista, sin conversaciones |
| 23 | Knowledge base | ⚠️ Vive en skills (`mod-operaciones-gp`) y SOPs | Consolidar |
| 24 | Data warehouse | ❌ No existe | Fase 3 |
| 25 | Dashboard ejecutivo | ⚠️ Existe el de operadores (vacío) + corte semanal manual | Fase 2 |
| 26 | KPIs | ⚠️ Definidos en skills, no calculables por falta de datos | Se desbloquean solos al llenar `servicios` |
| 27-28 | Documentación | ❌ No existe estructura formal | **Este documento la inicia** |
| 29 | Permisos | ⚠️ `perfiles.rol` = solo `admin` / `oficina` | Faltan operador, cobranza, cliente, dirección |
| 30 | Convenciones | ⚠️ Mezcla `integer` y `uuid`; `numeric` correcto para dinero; sin auditoría | Fijar convención (ver `04-modelo-datos`) |
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
automática, ni consumo de insumos, ni un solo KPI. La pregunta a resolver no es
técnica sino operativa: **¿dónde queda hoy el registro de un servicio hecho, y
cómo llega a Supabase?** (AppSheet ya lo captura — falta el puente.)

### 2. Que los cobros se concilien
337 pendientes por $1.93M y cero pagos registrados. Mientras la base no sepa
quién pagó, la regla de cobro anticipado no se puede aplicar automáticamente y
el flujo de facturación queda inerte por diseño.

### 3. Que exista `clientes` como entidad
Hoy el cliente es un texto dentro del contrato. Eso impide: saldo por cliente,
concentración de ingresos (métrica #5 del corte semanal), historial, RFC para
CFDI, y detectar que `GTC TERMO CONTROL` son 4 contratos del mismo cliente y no 4 clientes.

---

## 9. Decisiones que necesito de Eduardo

Estas cambian el diseño y no las puedo asumir:

1. **¿Dónde se registra hoy un servicio realizado?** ¿AppSheet ya lo captura y
   solo falta sincronizar, o se sigue anotando en papel/Excel?
2. **Razones sociales:** ¿"FACTURA TORREON" y "FACTURA SALTILLO" son empresas
   distintas de GP con su propio RFC? ¿Cuántas entidades emisoras hay en total?
3. **Querétaro:** ¿la operación de QRO debe entrar a esta misma base, o se lleva
   aparte a propósito?
4. **Cobranza:** ¿el Google Sheet `GP_Control_Financiero_2026` sigue siendo la
   fuente de verdad del dinero, o migramos a Supabase?
5. **Repositorio:** ¿armamos el monorepo `gp-platform` o seguimos con módulos
   sueltos dentro de este repo?

---

## 10. Lo que NO recomiendo hacer todavía

- No construir data warehouse ni BI: no hay hechos que cargar.
- No agregar agentes de IA sobre operaciones: consultarían tablas vacías.
- No comprar ni integrar herramientas nuevas: el stack actual está sobrado para
  el tamaño del problema. Lo que falta es **conectarlo**, no ampliarlo.
- No migrar a monorepo antes de resolver el punto 8.1.
