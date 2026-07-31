# Reporte Diario Automatizado de Rutas — SimpliRoute → Google Sheets

> Grupo Portátil · Operaciones (MTY / QRO)
> Estado: **DISEÑO PARA VALIDAR** (aún no construido en n8n)
> Fuente de datos: export manual CSV/Excel de SimpliRoute → Google Drive
> Entrega: Google Sheets (histórico) + Drive

---

## OBJETIVO OPERATIVO

Convertir el export diario de SimpliRoute en un reporte automático de una hoja que
mida **desempeño por operador**, **tiempos de servicio** y **desviaciones de ruta**,
sin captura manual. Indicador que mejora: **tasa de cumplimiento de visitas** y
**puntualidad**, con visibilidad diaria por plaza y operador.

Responsable del proceso: Eduardo (revisión) · Ejecución: sistema automático (n8n).

---

## 1. SPEC DEL REPORTE

El reporte se genera **por día y por plaza (MTY / QRO)**, con un bloque por operador
(Alberto, Emmanuel, Meñito, Juan Pablo) y un resumen consolidado.

### A. KPIs de desempeño por operador

| KPI | Fórmula | Fuente (SimpliRoute) | Meta sugerida |
|---|---|---|---|
| Cumplimiento de visitas | visitas completadas / visitas programadas | status de cada parada | ≥ 95% |
| Puntualidad (on-time) | llegadas dentro de ventana / total llegadas | hora real vs ventana | ≥ 90% |
| Paradas fallidas | count(status = failed / no visitada) | status | ≤ 1 por ruta |
| Reprogramaciones | count(visitas movidas a otro día) | status + fecha | tendencia a la baja |
| Km recorridos vs planeados | km real / km planeado | distancia ruta | ≤ 1.15 (15% margen) |
| Duración de ruta real vs plan | duración real / duración planeada | inicio/fin ruta | ≤ 1.20 |

### B. Tiempos de servicio (por parada)

Tiempo en sitio = `hora_salida_parada − hora_llegada_parada` (check-in / check-out).
Se compara contra el estándar por tipo de visita:

| Tipo de visita | Estándar | Bandera si… |
|---|---|---|
| Limpieza / bombeo | 15–30 min/unidad | > 40 min o < 8 min |
| Entrega | 45–90 min | fuera de rango |
| Retiro | 30–60 min | fuera de rango |
| Inspección | 20–30 min | fuera de rango |

Salidas: tiempo promedio por servicio y por operador, y lista de paradas fuera de
estándar (posible incidencia en campo o captura incorrecta).

### C. Desviaciones de ruta

| Métrica | Cómo se calcula |
|---|---|
| Retraso/adelanto de llegada | hora real − hora planeada, por parada (min) |
| Reordenamiento de secuencia | # paradas donde orden real ≠ orden planeado |
| Km extra | km real − km planeado |
| Paradas fuera de ventana | llegada fuera de la ventana horaria del cliente |
| Tiempo muerto entre paradas | traslado real vs traslado estimado |

**Semáforo por operador/ruta:** 🟢 dentro de metas · 🟡 1–2 desviaciones · 🔴 ≥ 3 o
paradas fallidas.

### D. Layout del reporte (Google Sheet)

- **Pestaña `Histórico`** — una fila por operador-plaza-día (append, nunca sobrescribe).
  Columnas: `fecha · plaza · operador · visitas_prog · visitas_compl · cumplimiento% ·
  puntualidad% · km_real · km_plan · dur_real · dur_plan · t_servicio_prom ·
  paradas_fuera_estandar · desviaciones · semaforo`.
- **Pestaña `Detalle_día`** — una fila por parada del día (para auditar incidencias).
- **Pestaña `Dashboard`** — tabla dinámica + gráficas (tendencia de cumplimiento y
  puntualidad por operador; se arma una vez sobre el histórico).

---

## 2. DISEÑO DEL FLUJO n8n

```
Trigger: Schedule — todos los días 19:00 (MTY) / 20:00 (QRO), después de cierre de rutas
  → Google Drive: buscar archivo del día en carpeta "SimpliRoute/Exports"
        (nombre esperado: ruta_YYYY-MM-DD_{MTY|QRO}.csv)
  → IF: ¿existe archivo del día?
        NO → notificar "falta export de SimpliRoute" y detener
        SÍ ↓
  → Extract From File: parsear CSV/Excel a filas
  → Code (JS): normalizar columnas + calcular KPIs, tiempos y desviaciones
        (agrupar por operador; aplicar estándares por tipo de visita; semáforo)
  → Google Sheets (append): pestaña "Histórico"  (1 fila por operador-plaza)
  → Google Sheets (append): pestaña "Detalle_día" (1 fila por parada)
  → Google Sheets / Drive: dejar copia del CSV procesado en "SimpliRoute/Procesados"
  → (Opcional futuro) notificación con el resumen del día
```

Nodos n8n: **Schedule Trigger** · **Google Drive** (Search/Download) · **Extract From
File** · **Code** · **Google Sheets** (Append) · **If**. Todo con credenciales Google
ya existentes en GP.

### Decisiones que definen el mapeo (a confirmar con un export real)

1. **Nombres de columna exactos** del CSV de SimpliRoute (varían según plantilla de
   exportación). Necesito un export real de un día para fijar el mapeo.
2. **Cómo viene el operador** en el export: ¿nombre, ID de vehículo, o "driver"?
   Hay que mapear vehículo/driver → Alberto/Emmanuel/Meñito/Juan Pablo.
3. **Tipo de visita**: ¿SimpliRoute trae el tipo (limpieza/entrega/retiro) o hay que
   inferirlo de una etiqueta/tag del cliente?
4. **Ventana horaria del cliente**: ¿está en el export o vive en Supabase/AppSheet?
5. **Un export por plaza** o uno combinado con columna de plaza.

---

## IMPLEMENTACIÓN EN EL STACK GP

- **SimpliRoute** → export manual diario a `Drive/SimpliRoute/Exports` (paso humano;
  responsable a definir: Eduardo o quien cierra rutas).
- **n8n** → workflow programado, en modo borrador/desactivado hasta validar el mapeo.
- **Google Sheets** → libro "Reporte Diario Rutas GP" con las 3 pestañas.
- **Supabase** (opcional fase 2) → si se quiere histórico consultable y cruce con
  contratos/unidades, replicar el `Histórico` a una tabla.

---

## RIESGOS OPERATIVOS

- **Falta el export** un día → el flujo debe avisar, no fallar en silencio.
- **Columnas cambian** en SimpliRoute → el nodo Code debe validar cabeceras y avisar si
  no encuentra una columna esperada.
- **Captura incorrecta en campo** (check-in/out mal marcado) infla tiempos de servicio →
  por eso se listan las paradas fuera de estándar para revisión, no se penaliza automático.
- **Mapeo operador↔vehículo** desactualizado si cambian asignaciones → mantener una
  mini-tabla de mapeo editable (pestaña o Data Table de n8n).

---

## MÉTRICAS DE ÉXITO

- Reporte generado automáticamente **7/7 días** sin captura manual.
- Cumplimiento y puntualidad visibles por operador antes de las 21:00.
- Reducción de paradas fallidas y reprogramaciones mes a mes (tendencia en Dashboard).

---

## SIGUIENTE ACCIÓN

1. **Eduardo:** subir **un export real de SimpliRoute** (un día, MTY y/o QRO) a
   `Drive/SimpliRoute/Exports` para fijar el mapeo de columnas.
2. Confirmar las **5 decisiones de mapeo** de la sección 2.
3. Confirmar la **hora del trigger** y el mapeo **vehículo → operador**.
4. Con eso, construyo el workflow en n8n (desactivado), lo pruebo con el export real y
   te muestro el Google Sheet con datos antes de activarlo.
