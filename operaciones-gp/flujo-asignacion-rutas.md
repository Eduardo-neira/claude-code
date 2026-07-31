# Flujo Automatizado de Asignación de Rutas

> Grupo Portátil · Operaciones (MTY / QRO)
> Estado: **DISEÑO PARA VALIDAR** (aún no construido en n8n)
> Objetivo: asignar rutas por disponibilidad de sanitarios, proximidad de eventos,
> capacidad de vehículos y tiempos de servicio.

---

## OBJETIVO OPERATIVO

Automatizar la planeación diaria de rutas: decidir **qué unidades** y **qué
operador/vehículo** atiende cada evento/servicio, con la **secuencia optimizada** por
proximidad, respetando **capacidad de vehículo** y **tiempos de servicio**. Elimina la
planeación manual en pizarrón y reduce traslados/km.

Indicador que mejora: km y tiempo de traslado por jornada, % de servicios cubiertos a
tiempo, y cero sobre-asignaciones de unidades.

Responsable: Eduardo (aprobación del plan) · Ejecución: sistema automático (n8n + SimpliRoute).

---

## Principio de diseño: SimpliRoute hace la optimización

SimpliRoute ya resuelve el problema de ruteo con capacidad, ventanas horarias, tiempos de
servicio y proximidad. **No reinventamos el solver**: n8n arma la demanda del día desde
Supabase, la manda a SimpliRoute a optimizar, y enruta el resultado a los operadores y de
vuelta a Supabase. (Si el plan de SimpliRoute no incluye API, hay un plan B con heurística
en un nodo Code — ver Riesgos.)

---

## PROCESO / FLUJO (n8n)

```
Trigger:
  A) Programado — 18:00 diario: planea la jornada del día siguiente
  B) On-demand — webhook cuando un contrato pasa a pago_confirmado = TRUE (replanea)

1. RECOLECTAR DEMANDA DEL DÍA (Supabase, por plaza MTY/QRO)
   → Entregas:  contratos pago_confirmado = TRUE, fecha_inicio = mañana, sin unidades asignadas
   → Servicios: unidades estado='rentado' con fecha_proximo_servicio <= mañana
   → Retiros:   contratos estado='vencido' con unidades asignadas > 0
   Cada parada trae: dirección/coords · plaza · #unidades · tipo_visita · ventana horaria

2. RESOLVER TIEMPO DE SERVICIO por parada (tabla estándar)
   limpieza 15-30 min/u · entrega 45-90 · retiro 30-60 · inspección 20-30

3. VERIFICAR DISPONIBILIDAD DE SANITARIOS (solo entregas)
   → Supabase: unidades estado='disponible' AND plaza = plaza_evento AND tipo = tipo_solicitado
     AND mantenimiento al corriente, ordenadas por nivel_desgaste ASC (las más nuevas primero)
   → Reservar tentativamente (estado 'reservado')
   → IF unidades disponibles < requeridas  → ALERTA a Eduardo (WhatsApp) y NO sobre-asignar

4. ARMAR PAYLOAD DE OPTIMIZACIÓN
   Paradas (visits): lat/lng, service_time, load (unidades que ocupan espacio), time_window
   Vehículos: capacidad (máx unidades/servicios por jornada), ventana 7-17h,
              inicio = patio GP, fin = planta tratadora de residuos

5. OPTIMIZAR  → SimpliRoute API (plan/optimize)   [1 corrida por plaza]
   Devuelve: rutas por vehículo con secuencia de paradas y ETAs

6. MAPEAR vehículo → operador (Alberto / Emmanuel / Meñito / Juan Pablo)
   (mini-tabla de mapeo editable — Data Table n8n o pestaña de Sheet)

7. ESCRIBIR RESULTADO
   → Supabase: crear ordenes_trabajo (ruta, secuencia, operador, unidades, ETA); unidades → 'reservado'
   → AppSheet: el operador ve su ruta del día
   → WhatsApp/Troncalnet (opcional): avisar al cliente ventana estimada
   → Guardar el PLAN para cruzarlo contra lo real en el reporte diario (cierra loop con el otro flujo)
```

---

## Restricciones que codifica el flujo

| Restricción | Cómo se aplica |
|---|---|
| **Cobro anticipado** | Solo entran a asignación contratos con `pago_confirmado = TRUE`. Sin pago → no hay parada. |
| **Dos plazas** | Optimización independiente por plaza (MTY / QRO). No se cruzan operadores entre plazas. |
| **Disponibilidad de sanitarios** | Solo unidades `disponible`, misma plaza y tipo; reserva tentativa; alerta si faltan. |
| **Proximidad de eventos** | SimpliRoute agrupa por cercanía; salida desde patio, cierre en planta tratadora. |
| **Capacidad de vehículo** | `load` por parada vs capacidad del vehículo (entregas = # unidades transportables; servicios = # servicios/jornada del camión de vacío). |
| **Tiempos de servicio** | `service_time` por tipo de visita alimenta las ETAs y el cupo de la jornada. |
| **Ventana operativa** | 7:00–17:00 por defecto; ventanas de acceso del cliente (obras 7–16h) por parada. |

> Nota: entregas y servicios de limpieza pueden requerir **vehículos distintos** (camión de
> carga vs camión de vacío). Si es así, se modelan como dos tipos de vehículo en SimpliRoute
> con capacidades diferentes.

---

## IMPLEMENTACIÓN EN EL STACK GP

- **n8n** — orquesta: Schedule/Webhook Trigger · Supabase (queries) · HTTP Request
  (SimpliRoute API) · Code (armar payload / mapear) · Supabase (insert órdenes) · AppSheet.
- **SimpliRoute** — motor de optimización (proximidad, capacidad, ventanas, tiempos).
- **Supabase** — fuente de verdad de disponibilidad (`unidades`), demanda (`contratos`) y
  destino de las `ordenes_trabajo` generadas.
- **AppSheet** — entrega la ruta al operador en campo.
- **Troncalnet/WhatsApp** — aviso opcional de ventana al cliente.

---

## RIESGOS OPERATIVOS

- **Coordenadas faltantes o malas** en direcciones de cliente → paso de geocodificación y
  validación antes de optimizar; si una dirección no geocodifica, se marca para revisión manual.
- **Disponibilidad desactualizada** → la reserva tentativa (`reservado`) evita que dos
  procesos asignen la misma unidad; confirmar al ejecutar la entrega.
- **SimpliRoute sin API** en el plan contratado → **plan B**: heurística en nodo Code
  (agrupar por zona → orden greedy por proximidad → cortar por capacidad y ventana). Menos
  óptimo pero funcional; se migra a API cuando esté disponible.
- **Sobre-asignación** → el flujo nunca asigna más unidades de las disponibles; escala a Eduardo.
- **Mezcla entrega/servicio en un solo camión** cuando no cabe → separar por tipo de vehículo.

---

## MÉTRICAS DE ÉXITO

- % de paradas del día asignadas automáticamente (meta: ≥ 90%).
- Reducción de km y tiempo de traslado planeado por jornada vs planeación manual.
- Cero sobre-asignaciones de unidades.
- Plan generado antes de las 18:30 para revisión de Eduardo.
- Cumplimiento plan vs real medible (se cruza con el reporte diario del otro flujo).

---

## SIGUIENTE ACCIÓN — decisiones para construir

1. **SimpliRoute API**: ¿el plan contratado incluye API/integración? (define motor vs plan B).
2. **Vehículos por plaza**: cuántos camiones/operadores por plaza y la **capacidad real** de
   cada uno (unidades transportables y/o servicios por jornada).
3. **¿Un vehículo o dos?** ¿Entregas y servicios de limpieza se hacen con el mismo camión?
4. **Coordenadas**: ¿las direcciones en Supabase ya traen lat/lng, o hay que geocodificar?
5. **Punto de cierre**: dirección del patio (salida) y de la planta tratadora (descarga).

Con eso construyo el workflow en n8n (desactivado), lo pruebo con la demanda real de un día
y te muestro el plan de rutas generado antes de activarlo.
