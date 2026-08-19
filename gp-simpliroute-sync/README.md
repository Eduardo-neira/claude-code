# GP · Puente SimpliRoute → Supabase

Trae a Supabase las visitas que los operadores **ya cierran** en SimpliRoute.

Es el cuello de botella identificado en
[`gp-modelo-empresa/00-diagnostico`](../gp-modelo-empresa/00-diagnostico-gp-vs-ecosan.md):
`servicios` estaba en 0 filas y de esa tabla dependen el dashboard de
operadores, el descuento de insumos y la facturación.

**Ya no está en 0.** El 2026-08-19 se promovieron los primeros **86 servicios**
del día 2026-08-18.

---

## Estado

| Pieza | Dónde | Estado |
|---|---|---|
| Workflow de ingesta | n8n · [`MElK9Ce7E4ydHnGf`](https://grupoportatil.app.n8n.cloud/workflow/MElK9Ce7E4ydHnGf) | 🟢 **Activo**, cada hora |
| Staging + config | `supabase/migrations/0001_staging_simpliroute.sql` | 🟢 Aplicada (2026-08-17) |
| Descubrimiento del schema | `supabase/02_descubrimiento.sql` | 🟢 Corrido (2026-08-19) → [`HALLAZGOS.md`](HALLAZGOS.md) |
| Amarre y promoción | `supabase/migrations/0002_amarre_y_promocion.sql` | 🟢 Aplicada (2026-08-19) |
| Mapa de operadores | `supabase/migrations/0003_mapa_operadores.sql` | 🟢 Aplicada (2026-08-19) |

---

## Cómo quedó

```text
SimpliRoute API
      │  n8n, cada hora
      ▼
simpliroute_visitas_raw          JSON crudo, append-only
      │
      │  sr_clasificar()         descarta paradas de ruta, fosa y QRO
      ▼
simpliroute_visitas_amarradas    una fila por UNIDAD servida
      │
      │  simpliroute_promover()  solo lo que tiene contrato
      ▼
servicios
```

Lo que no amarra **no se promueve**: se queda en `simpliroute_sin_amarre`.

### Resultado de la primera corrida

De 123 visitas del 2026-08-18:

| | |
|---|---|
| Fuera de alcance (paradas de ruta, fosa, QRO) | 46 |
| En alcance | 77 |
| Amarradas | 67 |
| Sin amarrar | 10 (13.0 %) |
| **Servicios creados** | **86** |

86 servicios de 67 visitas porque una visita cubre varias unidades.
82 completados, 4 fallidos; 81 LIMPIEZA y 5 RETIRO. Todos con operador:

| Operador | Servicios | Completados | Tipo |
|---|---|---|---|
| Meñito (Manuel) | 25 | 24 | limpieza |
| Emmanuel | 25 | 25 | limpieza |
| Juan Pablo | 25 | 24 | limpieza |
| Alberto | 6 | 4 | limpieza (+7 fosas fuera de alcance) |
| Christian | 5 | 5 | retiros |

**Cuidado al comparar.** Alberto hizo además 7 fosas que el modelo todavía no
representa, y Christian hace movimientos, no ruta. Medirlos contra los 25 de
una ruta de limpieza sería engañoso.

El detalle de por qué, y qué salió mal en el catálogo, está en
**[`HALLAZGOS.md`](HALLAZGOS.md)**. Vale la pena leerlo: el puente encontró
cosas que nadie sabía que faltaban.

---

## Lo que falta, en orden

### 1. Dar de alta los lavamanos

No existen en `unidades`. Números 302, 406, 420, 425, 428 — y no hay categoría
`LAVAMANOS`. Ver `HALLAZGOS.md` §5.1.

### 2. Revisar 16 unidades que el catálogo no ubica

```sql
select * from simpliroute_unidades_faltantes;
```

11 sanitarios se sirven sin colocación registrada, y 9 de ellos dicen `BODEGA`
mientras se sirven en obra.

### 3. Corregir 8 colocaciones que apuntan al cliente equivocado

```sql
select * from simpliroute_conflictos_colocacion;
```

**Si estas colocaciones están mal, la facturación de esos contratos también.**

### 4. Programar la promoción

Hoy la ingesta es automática pero la promoción se corre a mano. Cuando los
puntos 1-3 estén cerrados, agregar al workflow un nodo que llame a
`simpliroute_promover()` después de guardar el crudo.

---

## Operación diaria

```sql
select * from simpliroute_salud_amarre;              -- ¿cómo va el puente?
select * from simpliroute_sin_amarre;                -- qué no amarró
select * from simpliroute_promover(current_date - 1);
```

Todo se deshace sin perder nada — el crudo queda intacto:

```sql
delete from servicios where source = 'simpliroute';
```

---

## Lo que este puente deliberadamente NO hace

- **No escribe en `servicios` desde n8n.** Esa decisión vive en SQL, donde se
  puede auditar y revertir.
- **No inventa `contrato_id`.** Sin amarre, la visita se queda en revisión.
- **No borra ni actualiza el crudo.** Es append-only.
- **No trae Querétaro** ni los servicios de fosa. QRO se lleva aparte por
  decisión tuya; las fosas son otra línea que el modelo de datos todavía no
  representa.
- **No llena `tracking_id`.** Hay un índice único preexistente sobre esa
  columna que asume un servicio por visita, y los datos dicen otra cosa.

---

## Notas de seguridad

- El token de SimpliRoute **no está en este repo** ni en el historial. Vive en
  n8n. Como se compartió en una conversación, conviene **rotarlo**.
- En el nodo HTTP el token quedó pegado como parámetro del header en vez de en
  la credencial `Header Auth`. Conviene moverlo a la credencial para que no
  aparezca en el JSON del workflow.
- La API de SimpliRoute **no es alcanzable desde las sesiones de Claude Code**:
  el proxy de egreso responde 403 al CONNECT hacia `api.simpliroute.com:443`.
  Por eso las llamadas las hace n8n y el descubrimiento se hizo leyendo
  Supabase, no la API.
- Staging y config tienen RLS activo sin políticas: solo `service_role` entra.
