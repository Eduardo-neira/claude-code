# Qué dijeron los datos reales

Corrida del 2026-08-19 sobre **123 visitas del 2026-08-18** traídas por el
workflow de n8n. Todo lo de aquí está medido, no supuesto.

---

## 1. El amarre: `reference` trae los números de sanitario

Ningún campo de SimpliRoute trae el contrato de GP. Pero `reference` sí trae
los **números de sanitario**, y eso alcanza:

```
reference  →  unidades.numero  →  contrato_unidades  →  contratos.id
"#774"          774                colocación activa       contrato
```

Ejemplos reales del campo:

| `reference` | `title` |
|---|---|
| `#774` | TREBA PROYECTOS S.A DE C. V |
| `#726#831` | NEGOCIACION INDUSTRIAL CARVID |
| `#715-716-717-718` | CONSORCIO DE INGENIERIA |
| `#1058#769#809 Y 2 LAVAMANOS #406#425` | SLYRSA GRUPO INDUSTRIAL |
| `3 BAÑOS 1034,1035,1036 Y 1 LAVAMANOS #428` | CONSTRUCCIONES Y ACABADOS SOLUMAX |

Descartados como amarre:

- **`notes` no es un id, es la cantidad.** Trae `1` (59 visitas), `2` (9), `3`,
  y números grandes como `100`, `113`, `95`. Parecía coincidir con
  `contratos.id` solo por ser numérico. También trae `BAJA` y `ENTREGA`, que
  sí sirven — para el *tipo* de servicio.
- **`title` solo, no basta.** Coincide exacto con `contratos.cliente` en 39 de
  123; con normalización sube a 68, pero 47 de esas son **ambiguas** (el mismo
  cliente tiene varias obras activas). Sirve como confirmación, no como llave.
- **La coordenada casi no sirve.** Solo **4 de 123** caen dentro de 150 m de un
  contrato. Los 60 contratos activos sin coordenada capturada son la causa.
  Quedó como último recurso de la cascada.

## 2. Una visita ≠ un servicio

Una visita cubre **varias unidades**, y en GP cada unidad colocada cuelga de su
propio contrato. Las 123 visitas producen **86 servicios**.

Esto obligó a corregir el grano de `servicios`, que estaba mal en dos índices
únicos preexistentes:

| Índice | Qué asumía | Qué se hizo |
|---|---|---|
| `servicios_simpliroute_visit_id_uidx` | un servicio por visita | **eliminado**, reemplazado por `(simpliroute_visit_id, unidad_id)` |
| `ux_servicios_tracking` | un servicio por tracking de SimpliRoute | se conserva; el puente **no llena** `tracking_id` |

`servicios` estaba en 0 filas, así que el cambio no tocó ningún dato.

## 3. 46 de 123 visitas no son servicios

Promoverlas habría inflado los conteos y la facturación:

| Categoría | Visitas | Qué son |
|---|---|---|
| Paradas operativas | 36 | `INICIO/FINAL DE GASOLINA`, `TRANSITO`, `ESTACION DE GAS`, `PUNTO EMERGENTE`, `PLANTA NORTE`, `DESCARGA PTAR` |
| Servicios de fosa | 8 | `reference` = `FOSA 302`, `FOSA 343`… otra línea de negocio |
| Querétaro | 2 | latitud ~20.5; se lleva aparte por decisión tuya |
| **En alcance** | **77** | servicio de sanitario en MTY |

Los patrones viven en la tabla `simpliroute_exclusiones`, editable sin migración.

## 4. Resultado del amarre

De las **77 visitas en alcance**:

| | Visitas |
|---|---|
| Amarradas por número de sanitario | 66 |
| Amarradas por nombre inequívoco | 1 |
| **Sin amarrar** | **10 (13.0 %)** |

Las 10 no son un fallo del código — son huecos del catálogo, y están
identificadas una por una en `simpliroute_sin_amarre`.

## 5. Lo que el puente encontró en el catálogo

Esto es lo valioso: **el puente delata datos que faltaban y nadie sabía.**

### 5.1 · Los lavamanos no existen en `unidades`

`unidades` solo tiene números **≥ 700** (sanitarios). Los lavamanos que los
operadores sirven a diario están numerados **300–430** y **no están en el
catálogo**:

| Número | Cliente que lo tiene |
|---|---|
| 302, 406, 425 | SLYRSA GRUPO INDUSTRIAL |
| 420 | NEGOCIACION INDUSTRIAL CARVID |
| 428 | CONSTRUCCIONES Y ACABADOS SOLUMAX |

No hay categoría `LAVAMANOS` en `unidades`. Es una clase de activo completa
fuera del inventario.

### 5.2 · 11 sanitarios se sirven sin colocación registrada

Existen en `unidades` pero no tienen fila activa en `contrato_unidades`:

`714`, `726`, `831`, `833`, `871`, `1017`, `1019`, `1025`, `1034`, `1035`, `1036`

Peor: **9 de los 11 están marcados `BODEGA`** en el catálogo mientras
SimpliRoute los reporta servidos en obra. `unidades.estatus` no refleja la
realidad.

Vista para trabajar esto: `simpliroute_unidades_faltantes` (16 filas).

### 5.3 · 8 colocaciones apuntan al cliente equivocado

La unidad se sirvió a un cliente distinto del que dice `contrato_unidades` —
se movió y nadie lo registró:

| Sanitario | En SimpliRoute | En `contrato_unidades` |
|---|---|---|
| 761 | ARKEF | CHAVEZ Y ASOCIADOS CONSTRUCCION |
| 1085 | CARLOS AUGUSTO LARA TORRES | JOEL MUÑOZ |
| 842 | DESARRIKER | FRANCISCO AZAEL GUERRERO MOLINA |
| 728 | MA. OFELIA IBARRA HERNANDEZ | TEITER CONSTRUCCIONES ELECTROMECANICAS |

Vista: `simpliroute_conflictos_colocacion`. **Si estas colocaciones están mal,
la facturación de esos contratos también.**

### 5.4 · Los nombres están escritos distinto en los dos sistemas

Dos patrones, los dos resueltos con `gp_norm()`:

- Sufijos operativos en el título: `(MYJ)`, `(NUEVO)`, `(MARTES)`, `(BAJA)`.
  Son etiquetas del **cliente**, no del servicio — por eso el tipo se lee de
  `notes` y no del título: `RAMOGO NORTH AMERICA (BAJA FOSA)` se habría
  marcado como RETIRO siendo una visita de fosa.
- Forma societaria con comas: `LC INFRAESTRUCTURA S,A DE C,V` contra
  `LC INFRAESTRUCTURA S.A DE C.V`.

## 6. Operadores: resuelto (2026-08-19)

SimpliRoute usa **7 ids de driver**; GP tenía **5 operadores** registrados.
La correspondencia no se puede deducir de los datos — la dio Eduardo:

| Driver | Vehículo | Operador | Trabajo |
|---|---|---|---|
| 385815 | 437587 | **Manuel (Meñito)** | ruta grande MTY |
| 309312 | 424913 | **Juan Pablo** | ruta grande MTY |
| 309311 | 424914 | **Emmanuel** | ruta grande MTY |
| 324472 | 424912 | **Alberto** | fosas / pipa |
| 309316 | 424910 | **Christian** | entregas y bajas |
| 376983 | 437588 | — | Querétaro |
| 327288 | 424911 | — | Querétaro |

Dos ajustes al catálogo de operadores:

- **Manuel es Meñito.** No se creó operador nuevo: al id 3 se le puso el
  nombre real y el apodo quedó de alias.
- **Christian se dio de alta** como operador propio, no como el comodín
  "Extra" (id 5), que está marcado como cobertura temporal y no como persona.

Los dos drivers de Querétaro quedan sin operador a propósito.

### Lo que hay que cuidar al medir

| Operador | Servicios | Pero además |
|---|---|---|
| Meñito, Emmanuel, Juan Pablo | 25 c/u | ruta de limpieza |
| Alberto | 6 | **+7 fosas** que el modelo no representa |
| Christian | 5 | son **retiros**, no ruta |

Comparar a Alberto y a Christian contra los 25 de una ruta de limpieza haría
ver bajo rendimiento donde hay otro trabajo. La métrica de desempeño necesita
separarse por tipo antes de publicarse.
