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


---

# Segunda vuelta · conciliación del catálogo (2026-08-19)

## 7. `contratos.num_sanitario` es una segunda fuente

El hallazgo que ordenó todo lo demás. Ese campo dice qué unidad tiene cada
contrato, es **independiente de `contrato_unidades`**, cubre **193 de 194**
contratos activos, y está escrito en el mismo estilo desordenado que la
referencia de SimpliRoute:

| `num_sanitario` | Se lee como |
|---|---|
| `3 BAÑOS 1034,1035,1036  Y 1 LAVAMANOS 428  DE SU PROPIEDAD` | 1034, 1035, 1036, 428 |
| `101310301032 1 LAVAMANOS 427` | 1013, 1030, 1032, 427 |
| `862819736880` | 862, 819, 736, 880 |
| `1 BAÑO ESTANDAR` | (ningún número) |

`gp_numeros_unidad()` lo parsea. Extrae 195 números de los contratos activos y
**los 195 existen en `unidades`** — parseo limpio, sin basura.

Con tres fuentes (SimpliRoute, `contrato_unidades`, `num_sanitario`) ya se
puede arbitrar en vez de suponer.

## 8. Corrección: `contrato_unidades` no estaba desincronizada

En la primera vuelta reporté que las 8 colocaciones en conflicto significaban
que `contrato_unidades` estaba desactualizada. **Es incorrecto.** Al arbitrar
con `num_sanitario`, las dos fuentes internas de GP **coinciden en los 8
casos**. No hay desincronía entre tablas: el contrato completo dice lo mismo.

La discrepancia es entre **Supabase y la realidad de campo**. Dos son
concluyentes por distancia:

| Unidad | Se sirvió a | El contrato dice | Distancia a la obra registrada |
|---|---|---|---|
| 1085 | CARLOS AUGUSTO LARA TORRES | JOEL MUÑOZ | **28.4 km** |
| 869 | SUMINISTROS Y SERVICIOS ELECTRICOS | CONSTRUCCIONES Y URBANIZACIONES AL MAXIMO | **24.0 km** |

Otras dos (733, 1015) son solo ortografía: `CARRELLO` contra `CARELLO`.
Las cuatro restantes no se pueden verificar porque **el contrato no tiene
coordenada** — el problema de los 60 contratos sin geolocalizar, mordiendo.

## 9. Lavamanos: dados de alta

Se cerró el hueco. Ocho lavamanos entraron a `unidades` con categoría
`LAVAMANOS` y su colocación:

| Número | Contrato | Cliente | Propietario |
|---|---|---|---|
| 402 | 115 | SLYRSA | GP |
| 406 | 126 | SLYRSA | GP |
| 420 | 96 | CARVID | GP |
| 421 | 139 | GRUPO MYTE | GP |
| 424 | 70 | FRIOCAL | GP |
| 425 | 127 | SLYRSA | GP |
| 427 | 194 | SOLUMAX | GP |
| 428 | 58 | SOLUMAX | **CLIENTE** |

El propietario no se supuso: `DE SU PROPIEDAD` en el texto del contrato →
CLIENTE; `precio_lavamanos > 0` → GP.

**El 302 no se dio de alta.** Aparece solo en SimpliRoute para SLYRSA, que en
el contrato 115 tiene el 402. Es probable error de dedo en uno de los dos
sistemas y crear ambos inventaría una unidad. **Requiere que alguien lo mire.**

Efecto: el amarre pasó de **13.0 % a 10.4 %** sin amarrar, y los servicios de
86 a **90** (4 de ellos de lavamanos, que antes no se registraban).

## 10. Un cambio de unidad no registrado, confirmado

`gp_cambios_de_unidad_no_registrados` clasifica en vez de afirmar, porque con
un solo día de datos "la unidad registrada no se sirvió hoy" es lo **normal**:
LC INFRAESTRUCTURA tiene 8 obras, la mitad en banda LMV y la otra en MJS.

Solo hay un caso concluyente — cliente con una unidad registrada y una
distinta servida, donde la banda no puede explicarlo:

| Contrato | Cliente | Registrada | Servida |
|---|---|---|---|
| 120 | CONSTRUCCIONES Y PROYECTOS AXAN | **939** (EN_CAMPO desde abril) | **833** (dice BODEGA) |

Alguien cambió la unidad en la obra y nadie lo registró. El 939 lleva desde
abril marcado en campo sin que SimpliRoute lo vea nunca.

## 11. Dos categorías mal en el catálogo

La referencia de SimpliRoute también nombra la categoría, lo que permite
auditarla. Solo dos discrepancias sobrevivieron a una verificación estricta
(usando únicamente referencias con **un número y una etiqueta**, para no
atribuir mal la etiqueta en referencias de varias unidades):

| Unidad | Dice el operador | Dice el catálogo |
|---|---|---|
| 978 | EJECUTIVO | `DUPLICADO` |
| 1019 | PREMIUM | `ESTANDARD` |

**Las dos afectan precio**: PREMIUM y EJECUTIVO se cobran distinto que
ESTANDARD. No se corrigieron — cambiar la categoría mueve la facturación y
eso lo decide Eduardo.

`DUPLICADO` y `TRIPLICADOS` no parecen categorías reales sino restos de
captura; hay además 33 unidades con categoría nula.

## 12. Lo que sigue necesitando decisión humana

| Qué | Cuántos | Por qué no lo puedo resolver solo |
|---|---|---|
| 302 vs 402 (SLYRSA) | 1 | No sé cuál sistema tiene el error de dedo |
| Unidades de CARVID y SOLUMAX sin colocación | 7 | El cliente tiene 3 obras activas; no sé en cuál está cada una |
| Clientes sin contrato (CRAS ARQUITECTOS, JESÚS EDUARDO VÁZQUEZ AVALOS, GMOAL) | 3 | Alta de contrato = precio y fechas, decisión de negocio |
| Categorías 978 y 1019 | 2 | Cambiarlas mueve la facturación |
| Colocaciones en conflicto sin coordenada | 4 | El contrato no tiene geolocalización para verificar |
| Cambio de unidad AXAN 939 → 833 | 1 | Confirmar y cerrar/abrir la colocación |


---

# Tercera vuelta · 9 días de datos (2026-08-26)

El workflow corrió sin fallar: **1,116 visitas en 9 días** contra las 123 del
primer día. `servicios` pasó de 90 a **727**.

Con 9 días salieron tres defectos que con uno no se veían — y uno de
razonamiento mío.

## 13. Corrección: `num_sanitario` NO era una segunda fuente

En la vuelta anterior traté `contratos.num_sanitario` como una fuente
**independiente** de `contrato_unidades`, y usé su acuerdo para arbitrar los 8
conflictos de colocación.

**Es falso.** Las 192 colocaciones originales tienen notas
`backfill desde contratos.num_sanitario` y fecha **2026-08-12**: una fue
derivada de la otra. Que coincidan no prueba nada.

Por eso `gp_colocaciones_discrepantes` da **0 filas** — no porque el problema
se haya resuelto, sino porque compara un dato consigo mismo. La vista quedó
marcada como no apta para arbitrar.

Lo que sí sigue siendo válido: **la verificación por distancia** contra
`contratos.direccion_obra`, que es la que sostiene los dos casos confirmados
(1085 a 28 km de su obra registrada, 869 a 24 km). SimpliRoute es la única
fuente genuinamente independiente.

## 14. PostGIS no estaba en el `search_path` — la rama de coordenada nunca corrió

Defecto propio y silencioso. PostGIS está en el esquema `extensions`, no en
`public`. Al fijar `search_path = public, pg_temp` en `simpliroute_amarrar()`
—correcto por seguridad— quedó fuera, y el tipo `geography` dejó de
resolverse dentro de la función.

**La rama 3 del amarre nunca pudo ejecutarse.** No se detectó con un día
porque todas las visitas amarraban antes de llegar ahí. Ya corregido: ahora
amarra 3 visitas a 3-5 m, distancias muy ajustadas.

## 15. Unidades en dos obras a la vez

Dos unidades tienen **dos colocaciones activas simultáneas**, lo que es
físicamente imposible:

| Unidad | Colocación A | Colocación B |
|---|---|---|
| **807** | TEITER (2025-03-21) | TREVA (2025-12-08) |
| **863** | contrato 99 · VICENTE SALAZAR (FERIA) | contrato 66 · **mismo cliente, misma fecha** |

El 863 es un **contrato duplicado**. El 807 es un traslado donde nadie cerró
la colocación anterior — y encima SimpliRoute lo reporta en **TREVA y en
CAGPA la misma semana**, un tercer cliente que no aparece en ninguna de las
dos colocaciones.

Esto hacía tronar la promoción (`ON CONFLICT DO UPDATE cannot affect row a
second time`). La corrección no fue elegir un contrato —sería facturarle a
quien no es— sino marcar la unidad como ambigua y mandarla a revisión.

Vista nueva: `gp_unidades_en_dos_contratos`.

## 16. Las exclusiones se burlaban solas

Los operadores escriben el título distinto cada vez, y los patrones fallaban:

| Escrito | Patrón que no pegaba |
|---|---|
| `TRÁNSITO` (con acento) | `TRANSITO` |
| `ESTACION GAS` | `ESTACION DE GAS` |
| `CHECKLIST MANTENIMIENTO` | `CHECK LIST` |
| `EMERGENTE` | `PUNTO EMERGENTE` |

Más categorías que no existían el primer día: `REVISION DE ...`,
`COBRANZA ...`, `ENTREGA E INSTALACION DE FOSA DE ...`.

Ahora la comparación usa `gp_norm()`, así que el acento deja de importar.
Verificado antes de aplicar: los 19 títulos afectados tienen **cero contratos
activos**, así que no se excluye ningún cliente real.

## 17. La tasa real de amarre es 12.9 %, no 10.4 %

El 10.4 % de la vuelta anterior era una muestra favorable: el 18 de agosto fue
martes, un día de banda **MJS**. Los días LMV amarran sistemáticamente peor.

| Banda | Visitas por día | % sin amarrar |
|---|---|---|
| LMV (lun/mié/vie) | 164-177 | 12.5 – 20.4 % |
| MJS (mar/jue/sáb) | 92-123 | 10.4 – 14.3 % |

Sobre los 9 días: **657 visitas en alcance, 572 amarradas, 85 sin amarrar
(12.9 %)**.

## 18. El hallazgo de fondo: clientes servidos sin contrato

De las 85 sin amarrar, la mayor parte no es un problema técnico:

| | Clientes | Visitas |
|---|---|---|
| Cliente **sin contrato activo** en la base | 17 | 42 |
| Cliente con contrato, pero la unidad no amarra | 8 | 31 |
| Lavamanos aún no dado de alta | 2 | 12 |

Ocho clientes reciben servicio de forma regular y **no tienen contrato en
Supabase**:

| Cliente | Días servido | Unidad |
|---|---|---|
| JESÚS EDUARDO VÁZQUEZ AVALOS | 5 | #871 |
| CRAS ARQUITECTOS | 4 | #1017 |
| OSCAR SAUL MARTINEZ SALINA | 4 | #790 |
| DIOSDADO EDUARDO AGUIRRE PADILLA (CAGPA) | 3 | #807 |
| MANTENIMIENTO Y CONSTRUCCIONES GMOAL | 2 | #1019 PREMIUM |
| JESUS ALEJANDRO RIVERA CORONEL | 2 | #859 |
| COCONAL | 2 | #1021 #1026 PREMIUM |
| CORPORACION ELÉCTRICA DEL BRAVO | 2 | — |

**`cobros` cuelga de `contrato_id`.** Sin contrato no puede haber cobro en
este sistema. Falta confirmar si se les está facturando por otra vía (Sheets,
Facturama directo) o si de plano no se les está cobrando.

Dos que *parecían* estar en esta lista sí tienen contrato y lo que falla es el
nombre — vale la pena arreglarlo antes de dar de alta nada:

- `VICENTE SALAZAR VALENCIA (FERIA) SE REUBICO AQUÍ 07-08-2026` → contratos
  66 y 99. El texto de reubicación pegado al nombre rompe la comparación.
- `FLETES INDUSTRIALES` → contrato 84 `FLETES INDUSTRIALES REGIOMONTANOS`.

## 19. Sigue pendiente de decisión humana

Nada de esto se resolvió solo con más días, porque no era cuestión de datos:

| Qué | Estado |
|---|---|
| 302 vs 402 de SLYRSA | igual, sigue sin resolverse |
| Categorías 978 y 1019 (mueven precio) | igual, sin tocar |
| 8 clientes sin contrato | **creció**: eran 3, ahora son 8 |
| Unidades 807 y 863 en dos obras | **nuevo** |
| CARVID: 20 visitas en 8 días sin amarrar | el más grande; tiene 3 obras activas |
