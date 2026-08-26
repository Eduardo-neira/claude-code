# GP · Puente SimpliRoute → Supabase

Trae a Supabase las visitas que los operadores **ya cierran** en SimpliRoute.

Es el cuello de botella identificado en
[`gp-modelo-empresa/00-diagnostico`](../gp-modelo-empresa/00-diagnostico-gp-vs-ecosan.md):
`servicios` estaba en 0 filas y de esa tabla dependen el dashboard de
operadores, el descuento de insumos y la facturación.

**Ya no está en 0.** Al 2026-08-26 lleva **727 servicios** de 9 días de operación.

---

## Estado

| Pieza | Dónde | Estado |
|---|---|---|
| Workflow de ingesta | n8n · [`MElK9Ce7E4ydHnGf`](https://grupoportatil.app.n8n.cloud/workflow/MElK9Ce7E4ydHnGf) | 🟢 **Activo**, cada hora |
| Staging + config | `supabase/migrations/0001_staging_simpliroute.sql` | 🟢 Aplicada (2026-08-17) |
| Descubrimiento del schema | `supabase/02_descubrimiento.sql` | 🟢 Corrido (2026-08-19) → [`HALLAZGOS.md`](HALLAZGOS.md) |
| Amarre y promoción | `supabase/migrations/0002_amarre_y_promocion.sql` | 🟢 Aplicada (2026-08-19) |
| Mapa de operadores | `supabase/migrations/0003_mapa_operadores.sql` | 🟢 Aplicada (2026-08-19) |
| Conciliación del catálogo | `supabase/migrations/0004_conciliacion_catalogo.sql` | 🟢 Aplicada (2026-08-19) |
| Correcciones con 9 días | `supabase/migrations/0005_correcciones_9_dias.sql` | 🟢 Aplicada (2026-08-26) |

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

### Resultado tras 9 días (2026-08-26)

| | |
|---|---|
| Visitas ingestadas | 1,116 |
| Fuera de alcance (paradas, fosa, QRO) | 459 |
| En alcance | 657 |
| Amarradas | 572 |
| Sin amarrar | 85 (12.9 %) |
| **Servicios creados** | **727** |

El 10.4 % del primer día era una muestra favorable: el 18 de agosto fue un día
de banda MJS, y los días LMV amarran sistemáticamente peor.

De las 85 sin amarrar, **42 son de clientes que no tienen contrato en la
base** — ver `HALLAZGOS.md` §18. Eso no es un problema del puente.

<details>
<summary>Resultado de la primera corrida (2026-08-18)</summary>

De 123 visitas:

| | |
|---|---|
| Fuera de alcance (paradas de ruta, fosa, QRO) | 46 |
| En alcance | 77 |
| Amarradas | 69 |
| Sin amarrar | 8 (10.4 %) |
| **Servicios creados** | **90** |

90 servicios de 69 visitas porque una visita cubre varias unidades.

</details>
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

Todo esto está en `HALLAZGOS.md` §12 con el detalle de por qué.

### 1. Un error de dedo por resolver: 302 vs 402

SLYRSA aparece con el lavamanos **302** en SimpliRoute y **402** en el
contrato 115. Se dio de alta el 402 (viene del contrato) y **no** el 302, para
no inventar una unidad. Alguien tiene que decir cuál es.

### 2. Siete unidades sin colocación, en clientes con varias obras

```sql
select * from simpliroute_unidades_faltantes;
```

CARVID y SOLUMAX tienen 3 obras activas cada uno; no se puede deducir en cuál
está cada unidad.

### 3. Tres clientes que se sirven sin contrato en la base

CRAS ARQUITECTOS, JESÚS EDUARDO VÁZQUEZ AVALOS y MANTENIMIENTO Y
CONSTRUCCIONES GMOAL. Dar de alta el contrato es decisión de negocio
(precio, fechas).

### 4. Dos categorías que mueven precio

```sql
-- 978 dice DUPLICADO, el operador dice EJECUTIVO
-- 1019 dice ESTANDARD, el operador dice PREMIUM
```

No se corrigieron porque cambiar la categoría cambia lo que se cobra.

### 5. Un cambio de unidad confirmado

```sql
select * from gp_cambios_de_unidad_no_registrados where confianza like 'alta%';
```

AXAN tiene registrado el **939** desde abril, pero se sirve el **833**.

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

-- conciliación del catálogo
select * from simpliroute_unidades_faltantes;           -- unidades que el catálogo no ubica
select * from simpliroute_conflictos_colocacion;        -- servida a otro cliente
select * from gp_colocaciones_discrepantes;             -- las dos fuentes internas no coinciden
select * from gp_cambios_de_unidad_no_registrados;      -- cambios de unidad (ver `confianza`)
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
