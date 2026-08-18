# Automatización · n8n

El dashboard es automatizado: lee la vista `vista_desempeno_operadores` (sobre la tabla
real `servicios`), que se puebla desde AppSheet/SimpliRoute sin captura manual. n8n cierra
el ciclo con el reporte semanal. Todo se ancla al stack de GP.

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

1. **Zona horaria:** fijar el timezone del workflow a **America/Monterrey** (Settings) para
   que dispare a las 08:00 locales; por defecto usa el del instance (UTC).
2. **Datos:** que los operadores registren servicios en AppSheet para poblar la vista. Con la
   tabla `servicios` vacía, el reporte no envía correo (nada que reportar).

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

Fijar el timezone del workflow a America/Monterrey y confirmar la captura en AppSheet para
que el reporte empiece a salir con datos reales cada lunes.
