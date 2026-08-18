# Automatización · n8n

El dashboard es automatizado: lee la vista `vista_desempeno_operadores` (sobre la tabla
real `servicios`), que se puebla desde AppSheet/SimpliRoute sin captura manual. n8n cierra
el ciclo con dos flujos: la **ingesta de visitas de SimpliRoute** (entrada de datos) y el
**reporte semanal** (salida). Todo se ancla al stack de GP.

---

## Reporte semanal de desempeño — CONSTRUIDO Y ACTIVO

**Workflow:** `GP · Reporte semanal de operadores` (n8n, proyecto personal de Eduardo)
**ID:** `pP9C4HLxVH7aP7fU` · estado: **activo**

**Objetivo:** cerrar la semana con el ranking de operadores (completados, puntualidad y
calidad) y enviarlo por correo. Lee la misma vista que el dashboard, así que nunca se
contradicen.

```
[Schedule] Lunes 08:00
   │
   ▼
[Supabase] Leer vista de KPIs
   getAll de vista_desempeno_operadores (returnAll, orderBy semana.desc)
   │
   ▼
[Code] Armar reporte semanal (runOnceForAllItems)
   - toma la semana ISO más reciente
   - ranking por servicios_completados + Δ vs. semana previa
   - puntualidad_pct y calidad_score por operador ("sin captura" si aún no hay datos)
   - arma asunto + cuerpo HTML
   - si la vista viene vacía → return [] (no se envía nada esa semana)
   │
   ▼
[Gmail] Enviar por Gmail
   a eduardo.neira@gportatil.com (HTML, executeOnce)
```

> **Nota de canal:** el envío es por **Gmail** porque es la credencial de mensajería
> conectada hoy en n8n (no hay Troncalnet/WhatsApp). Cuando se conecte WhatsApp, se agrega
> un nodo en paralelo después de "Armar reporte semanal" — el resto no cambia.

### Pendientes de configuración

1. **Zona horaria:** ✅ configurada — el workflow usa **America/Monterrey**, dispara a las
   08:00 locales.
2. **Datos:** que los operadores registren servicios (AppSheet o la ingesta de SimpliRoute,
   abajo) para poblar la vista. Con la tabla `servicios` vacía, el reporte no envía correo.

---

## Fase 2 · Puntualidad y calidad (activa)

Los campos de Fase 2 ya existen en `servicios` y la vista entrega `puntualidad_pct` y
`calidad_score`. En cuanto AppSheet capture hora programada, check-in, checklist y
calificación, el reporte los muestra automáticamente (hoy salen como "sin captura"). El
cuerpo puede resaltar operadores bajo meta:

```
A reforzar: {operador} bajo meta de puntualidad ({pct}%) / calidad ({score}).
```

sin cambios en el dashboard ni en el resto del flujo.

---

## Ingesta de visitas de SimpliRoute → servicios — CONSTRUIDO (inactivo)

**Workflow:** `GP · SimpliRoute → servicios (visitas del día)` (proyecto personal de Eduardo)
**ID:** `uKk5cyy1JZoGkOZY` · timezone: **America/Monterrey** · estado: **inactivo** (activar tras probar)

**Objetivo:** poblar la tabla `servicios` con las visitas del día que SimpliRoute ya ejecuta,
sin captura manual — así el dashboard y el reporte semanal se alimentan solos.

```
[Schedule] Diario 21:00
   │
   ▼
[HTTP GET] SimpliRoute · visitas del día
   GET https://api.simpliroute.com/v1/routes/visits/?planned_date=<hoy>
   Auth: Header Auth  (Authorization: Token <token>)
   │
   ▼
[Code] Mapear a servicios (runOnceForAllItems)
   por cada visita → fila de servicios:
     simpliroute_visit_id, tracking_id, fecha_servicio,
     checkout_time / checkout_lat / checkout_lng,
     completado (status = 'completed'), operador (best-effort),
     notas (title), tipo='LIMPIEZA', source='simpliroute'
   si no hay visitas → return []  (no escribe nada)
   │
   ▼
[HTTP POST] Upsert en servicios
   POST {SUPABASE_URL}/rest/v1/servicios?on_conflict=simpliroute_visit_id
   Header: Prefer: resolution=merge-duplicates,return=minimal
   Auth: credencial Supabase del proyecto (predefinedCredentialType)
   executeOnce
```

**Idempotencia:** índice único parcial `servicios_simpliroute_visit_id_uidx`
(`on servicios(simpliroute_visit_id) where simpliroute_visit_id is not null`). Re-ejecutar
hace UPSERT (no duplica). El merge solo toca las columnas del payload, así que **no pisa**
los FKs enriquecidos después (`operador_id`, `unidad_id`, `contrato_id`).

### Pendientes de configuración

1. **Credencial SimpliRoute:** crear en n8n una credencial **Header Auth** `SimpliRoute Token`
   (`Name: Authorization`, `Value: Token <token>`) y asignarla al nodo de SimpliRoute. La
   credencial de Supabase ya está enlazada al nodo de upsert.
2. **Primera corrida en vivo:** ejecutar manualmente para ver el payload real de SimpliRoute
   y afinar el mapeo — sobre todo `operador` (SimpliRoute suele traer el *driver* como **id**,
   no nombre → mapear driver→`operadores`) y `unidad`/`contrato` (si vienen en `reference`/`title`).
3. **Permisos de escritura:** el upsert usa la credencial Supabase del proyecto; debe tener
   permiso de escritura sobre `servicios` (service role o policy RLS que lo permita).
4. **Activar** el workflow cuando la prueba se vea correcta.

> Alcance actual del mapeo: campos nativos de SimpliRoute + `source='simpliroute'`, dejando
> `operador_id`/`unidad_id`/`contrato_id` en null para enriquecer después.

---

## Ideas de flujos adicionales (no construidos)

- **Alerta de baja actividad (cron diario):** detectar operadores activos sin servicios
  registrados en el día y avisar a Eduardo. Requiere definir el canal de aviso.
- **Snapshot histórico:** anexar el corte semanal a Google Sheets como respaldo (requiere
  conectar la credencial de Google Sheets; hoy solo hay Google Drive).

---

## Notas de implementación

- **RLS:** el dashboard consulta la vista con la `anon key` (solo lectura, conteos
  agregados). Las escrituras a `servicios` siguen su flujo actual (AppSheet/SimpliRoute); el
  reporte de n8n usa la credencial de Supabase del proyecto.
- **Zona horaria:** los `timestamptz` se guardan en UTC; el corte semanal ISO es consistente.
- **Refresco:** la vista es en vivo (no materializada); si el volumen crece, evaluar
  `MATERIALIZED VIEW` + `REFRESH` en un cron de n8n.

## Siguiente acción

Crear la credencial `SimpliRoute Token`, correr la ingesta en vivo una vez para afinar el
mapeo y activarla — así `servicios` empieza a poblarse y el reporte semanal sale con datos
reales cada lunes.
