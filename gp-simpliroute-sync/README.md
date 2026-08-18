# GP · Puente SimpliRoute → Supabase

Trae a Supabase las visitas que los operadores **ya cierran** en SimpliRoute.

Es el cuello de botella identificado en
[`gp-modelo-empresa/00-diagnostico`](../gp-modelo-empresa/00-diagnostico-gp-vs-ecosan.md):
`servicios` está en 0 filas y de esa tabla dependen el dashboard de operadores,
el descuento de insumos y la facturación. **El dato existe; lo que falta es el
puente.**

---

## Lo que ya está construido

| Pieza | Dónde | Estado |
|---|---|---|
| Workflow de ingesta | n8n · [`MElK9Ce7E4ydHnGf`](https://grupoportatil.app.n8n.cloud/workflow/MElK9Ce7E4ydHnGf) | 🟡 Creado, **inactivo** |
| Tabla de staging + config | `supabase/migrations/0001_staging_simpliroute.sql` | 🟢 **Aplicada** en `gp-inventario` (2026-08-17) |
| Consultas de descubrimiento | `supabase/02_descubrimiento.sql` | Listas |
| Amarre y promoción | `supabase/03_amarre_y_promocion.sql` | 🔴 **Sin aplicar** |

---

## El diseño, y por qué es en dos etapas

```text
SimpliRoute API
      │  (n8n, cada hora)
      ▼
simpliroute_visitas_raw     ← JSON crudo, append-only. NO toca servicios.
      │
      │  (SQL, cuando el amarre esté confirmado)
      ▼
servicios                   ← solo visitas con contrato resuelto
```

**No mapeo campos en n8n.** La documentación pública de SimpliRoute no fue
accesible al construir esto, así que el payload entra íntegro a una columna
`jsonb` y los nombres reales se descubren con datos reales (`02`).

Esto es deliberado: el módulo `gp-flujo-facturacion` ya se construyó una vez
sobre un supuesto equivocado —emitía un comprobante por servicio cuando GP
factura mensual— y no se detectó hasta preguntarlo. Aquí el schema sale de los
datos, no de una suposición.

**El problema difícil no es traer los datos, es el amarre.** SimpliRoute
identifica sus visitas con su propio id; Supabase identifica contratos con
`contratos.id`. Nada los liga todavía. Por eso la promoción a `servicios` es un
paso aparte y explícito: una visita sin contrato **no** se promueve, se queda en
la bandeja de revisión.

---

## Puesta en marcha

### Paso 1 · Aplicar el staging — ✅ HECHO

Aplicado a `gp-inventario` el 2026-08-17 en tres migraciones:
`staging_simpliroute`, `staging_simpliroute_endurecer` y
`staging_simpliroute_desempate_determinista`.

Creó `simpliroute_visitas_raw`, `simpliroute_config`, la vista
`simpliroute_visitas_ultima`, la función `sr_config()` y dos índices únicos
sobre `servicios` y `rutas` que garantizan idempotencia.

Verificado tras aplicar:

- Datos existentes intactos: 437 unidades, 194 contratos, 337 cobros,
  192 colocaciones. `servicios` y `rutas` siguen en 0.
- Prueba de humo en transacción con `rollback`: la deduplicación funciona y
  la consulta de descubrimiento encuentra campos. La tabla quedó vacía.
- El asesor de seguridad de Supabase quedó **sin hallazgos nuevos**.

Dos defectos salieron en esa verificación y ya están corregidos:

1. **La vista heredaba `SECURITY DEFINER`** (default de Supabase para vistas
   creadas por el rol `postgres`), lo que anulaba el RLS de la tabla de abajo.
   Ahora es `security_invoker`.
2. **`distinct on ... order by ingestado_en desc` no era determinista.**
   `now()` es la hora de inicio de transacción, así que dos versiones de la
   misma visita en el mismo lote empataban y podía ganar la vieja. Se agregó
   desempate por `id`.

### Paso 2 · Crear la credencial de SimpliRoute en n8n

El único paso que no pude dejar hecho — no hay credencial de SimpliRoute en la
instancia. En n8n, credencial tipo **Header Auth**:

| Campo | Valor |
|---|---|
| Name | `Authorization` |
| Value | `Token <tu_api_key>` |

Y asignarla al nodo *Traer Visitas de SimpliRoute*.

✅ **Esquema confirmado** (2026-08-18): `authorization: Token <api_key>`, contra
`https://api.simpliroute.com/v1/`. Ya no es una suposición.

⚠️ La API de SimpliRoute **no es alcanzable desde las sesiones de Claude Code**:
el proxy de egreso responde 403 al CONNECT hacia `api.simpliroute.com:443`. Por
eso las llamadas las hace n8n, que tiene su propia salida a internet — y por eso
el descubrimiento del schema (paso 4) se hace leyendo Supabase, no la API.

### Paso 3 · Una corrida manual

Ejecutar el workflow a mano (**sin activarlo**) y revisar:

```sql
select count(*), min(fecha_planeada), max(fecha_planeada)
from simpliroute_visitas_raw;
```

Si trae 0 filas, el problema es la credencial o el nombre del parámetro de
fecha; el nodo *Registrar Falla de API* captura el error sin escribir nada.

### Paso 4 · Descubrir el schema real

```sql
-- supabase/02_descubrimiento.sql
```

La consulta 1 lista **todos** los campos que trae una visita, con tipo y
ejemplo. La consulta 2 es la importante: busca cuál de esos campos sirve para
amarrar contra `contratos`, probando contra `cliente`, `contrato_num`, `id` y
`unidades.codigo`.

Con eso se llena `simpliroute_config`:

```sql
update simpliroute_config set valor = 'reference'      where clave = 'path_contrato';
update simpliroute_config set valor = 'checkout_time'  where clave = 'path_checkout_ts';
update simpliroute_config set valor = 'checkout_latitude'  where clave = 'path_checkout_lat';
update simpliroute_config set valor = 'checkout_longitude' where clave = 'path_checkout_lng';
update simpliroute_config set valor = 'status'         where clave = 'path_estado';
update simpliroute_config set valor = 'completed'      where clave = 'valor_completado';
```

*(Los valores de ejemplo son plausibles pero **no verificados** — usar los que
devuelva la consulta 1.)*

### Paso 5 · Amarre

```sql
-- supabase/03_amarre_y_promocion.sql
select * from simpliroute_salud_amarre;
select * from simpliroute_sin_amarre limit 20;
```

`simpliroute_salud_amarre` da el porcentaje sin amarrar por día. **Meta: menos
del 5%.** Si sale mucho más alto, el problema es la configuración del paso 4, no
el código.

La cascada de amarre es: referencia explícita → coordenada (PostGIS, radio
configurable) → nada.

⚠️ Los **60 contratos activos sin coordenadas** nunca amarrarán por la segunda
vía. Completarlos es prerrequisito si no hay campo de referencia utilizable.

### Paso 6 · Promover un día

```sql
select * from simpliroute_promover(current_date - 1);
```

Devuelve `promovidos / actualizados / omitidos`. Revisar en `servicios` que las
filas se vean bien antes de seguir.

Se puede deshacer sin perder nada:

```sql
delete from servicios where source = 'simpliroute';
```

El crudo queda intacto, así que se reprocesa cuando quieras.

### Paso 7 · Activar

Solo cuando los pasos 3–6 se vean limpios: activar el workflow en n8n y
programar la promoción.

---

## Lo que este puente deliberadamente NO hace

- **No escribe en `servicios` desde n8n.** Esa decisión vive en SQL, donde se
  puede auditar y revertir.
- **No inventa `contrato_id`.** Sin amarre, la visita se queda en revisión.
- **No borra ni actualiza el crudo.** Es append-only; reprocesar agrega filas y
  la vista `..._ultima` se queda con la más reciente.
- **No trae Querétaro.** QRO se lleva aparte por decisión de Eduardo. Si la
  cuenta de SimpliRoute mezcla ambas plazas, hay que filtrar por sucursal.

---

## Pendientes conocidos

1. **Credencial de SimpliRoute** — paso 2, es lo único que bloquea la primera corrida.
2. **Cómo se amarra cada visita** — se resuelve con datos en el paso 4. Si
   SimpliRoute permite guardar una referencia por cliente/visita, lo más robusto
   es meter ahí el `contrato_id` de GP y cerrar el problema de raíz.
3. **`servicios.completado` nace en `true`** por default del schema
   ([`04-modelo-datos` §Cambio 11](../gp-modelo-empresa/04-modelo-datos.md)).
   La función de promoción lo fija explícitamente, pero conviene corregir el
   default para que el calendario semanal funcione.
4. **Rutas.** Este puente trae visitas. Poblar `rutas` con tiempos y distancias
   reales es el siguiente paso, sobre el mismo endpoint.
5. **Evidencia.** Falta decidir si las fotos se copian a Supabase Storage o solo
   se guarda la URL de SimpliRoute (ver `04-modelo-datos` §Cambio 7).
