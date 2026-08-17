# 01 · Modelo de empresa — Grupo Portátil

> Equivalente GP de la §1 del blueprint EcoSan. Describe la empresa **como es**,
> no como debería verse en un organigrama.

---

## Identidad

| Campo | Valor |
|---|---|
| Giro | Renta, servicio y fabricación de sanitarios portátiles |
| Antigüedad | +7 años de operación |
| Plazas | Monterrey, N.L. (esta base) · Santiago de Querétaro, Qro. (**se lleva aparte**) |
| Flota | 437 unidades registradas en MTY (429 propias de GP, 8 propiedad de cliente) |
| Cartera activa | 194 contratos · ~100 clientes reales |
| Modelo de cobro | **Anticipado (prepago)** — sin pago confirmado no se genera servicio |
| Ciclo de facturación | **Mensual por contrato** (no por servicio) |
| Renta mensual contratada | $1,028,964 MXN, de los cuales **$1,006,808 son de GP** y $22,156 de empresas hermanas |
| Registro de campo | **SimpliRoute** (rutas y servicios ejecutados) |

### Segmentos que atendemos
Construcción y obra · industrial · eventos · gobierno.
Dominante: **obra en el área metropolitana de Monterrey**.

---

## Áreas reales

EcoSan lista 16 áreas. GP no las tiene y **no debe fingir que sí**. El sistema se
diseña para las que existen:

| Área EcoSan | En GP | Quién |
|---|---|---|
| Dirección | ✅ | Eduardo |
| Operaciones | ✅ | Iván + operadores |
| Logística / Rutas | ✅ (dentro de operaciones) | Iván, SimpliRoute |
| Inventario | ✅ (dentro de operaciones) | Iván |
| Flotilla / Mantenimiento | ⚠️ informal | Emmanuel / Alberto |
| Facturación | ✅ | Administración |
| Cobranza | ✅ | Administración |
| Finanzas | ⚠️ mezclado con cobranza | Eduardo + administración |
| Atención al cliente | ⚠️ informal (WhatsApp) | Eduardo / Iván |
| Comercial | ❌ no formalizada | Eduardo |
| Compras | ❌ no formalizada | Eduardo |
| Recursos Humanos | ❌ no formalizada | — |
| Datos e Inteligencia | ⚠️ emergente | Eduardo |
| Tecnología | ⚠️ emergente | Eduardo |

**Consecuencia de diseño:** el sistema no puede asumir que hay un vendedor, un
comprador y un analista distintos. Una sola persona cruza varios roles. Los
permisos (§29 de EcoSan) deben modelarse por **permiso**, no por puesto.

---

## Equipo de campo

| Operador | Rol | Base | En la base de datos |
|---|---|---|---|
| Alberto | Operador senior / rutas | MTY | `operadores.id = 4` |
| Emmanuel | Operador / mantenimiento | MTY | `operadores.id = 1` |
| Meñito | Operador / entregas | MTY | `operadores.id = 3` |
| Juan Pablo | Operador / soporte | QRO | `operadores.id = 2` |
| "Extra" | Comodín / apoyo | — | `operadores.id = 5` |

⚠️ Los 5 tienen `sucursal_id` en **NULL**. No se puede saber por la base quién
opera en qué plaza.

⚠️ **Juan Pablo opera en QRO**, que se lleva aparte. Marcarlo como MTY ensuciaría
la productividad por operador; hay que decidir si se desactiva en esta base o se
deja sin plaza a propósito. Ver `04-modelo-datos` §Cambio 5.

---

## Productos y modalidades

### Modalidad de contrato (`contratos.modalidad`)
| Modalidad | Contratos | Descripción |
|---|---:|---|
| `renta` | 189 | GP es dueña de la unidad y la renta |
| `solo_servicio` | 5 | La unidad es del cliente; GP solo da el servicio |
| `venta` | 0 | Venta de equipo (existe el catálogo, sin uso todavía) |

### Tipo de servicio (`contratos.tipo_servicio`)
| Tipo | Contratos | Significado |
|---|---:|---|
| `TERCIADO` | **175** | 3 servicios por semana — **el producto dominante** |
| `2X_SEMANA` | 14 | 2 servicios por semana |
| `1X_SEMANA` | 3 | 1 servicio por semana |
| `DIARIO` | 1 | Servicio diario |
| (nulo) | 1 | Fila a limpiar |

### Bandas de frecuencia (`contratos.frecuencia`)
| Banda | Contratos | Días |
|---|---:|---|
| `LMV` | 106 | Lunes · Miércoles · Viernes |
| `MJS` | 85 | Martes · Jueves · Sábado |
| `EXTRA` | 3 | Fuera de banda, bajo demanda |

**Este es el concepto operativo más importante de GP y no existe en EcoSan.**
La operación no se programa "cada 7 días" sino en dos bandas fijas de días.
El calendario de servicios se genera desde aquí.

---

## Comprobación fiscal

| Tipo | Contratos | Lleva IVA | Documento | ¿Es de GP? |
|---|---:|---|---|---|
| `FACTURA` | 158 | Sí (16%) | CFDI 4.0 timbrado | ✅ |
| `REMISION` | 25 | No | Comprobante interno | ✅ |
| `FACTURA TORREON` | 8 | Sí | CFDI de **empresa hermana** | ❌ |
| `FACTURA SALTILLO` | 2 | Sí | CFDI de **empresa hermana** | ❌ |
| `nan` | 1 | — | Basura de importación, eliminar | — |

**Confirmado por Eduardo (2026-08-17):** Torreón y Saltillo son **razones sociales
de empresas hermanas de familiares, con administración y finanzas aparte**.
No son plazas de operación (sus obras están en Nuevo León) ni divisiones de GP.

**Consecuencia:** sus 10 contratos comparten esta base pero **su dinero no es de
GP**. Toda métrica de ingreso debe excluirlos. Ver `04-modelo-datos` §Cambio 3.

### Facturación: mensual por contrato

**Confirmado por Eduardo:** GP emite **un comprobante mensual por contrato**, no
uno por servicio realizado. La tabla `cobros` ya lo refleja correctamente —
exactamente 1 cobro por contrato por periodo, con el monto igual a
`monto_mensual` al centavo en los 126 casos donde ese campo existe.

Los servicios `EXTRA` (modificador 1.50) probablemente sí se cobran aparte;
falta confirmarlo.

---

## Estado de la flota

| Estatus | Propietario | Unidades |
|---|---|---:|
| `BODEGA` | GP | 241 |
| `EN_CAMPO` | GP | 185 |
| `BODEGA` | CLIENTE | 6 |
| `EN_VENTA` | CLIENTE | 2 |
| `BAJA` | GP | 2 |
| `EN_VENTA` | GP | 1 |

**Utilización de flota propia: 185 / 429 = 43.1%.**
Menos de la mitad de las unidades de GP están generando ingreso. Es el número más
accionable del negocio y hoy no lo reporta ningún tablero.

⚠️ Inconsistencia: 185 unidades `EN_CAMPO` contra 192 colocaciones vigentes en
`contrato_unidades`. Los dos números deberían ser iguales.

---

## Reglas de negocio permanentes

1. **Sin pago confirmado no hay orden de trabajo.** El prepago no es una
   preferencia administrativa, es la regla que gobierna la programación.
2. **Una unidad no pasa de un contrato a otro sin volver a bodega.** Limpieza y
   revisión obligatorias entre colocaciones.
3. **Toda unidad tiene código único** (`MTY-XXX`). Es la identidad que cruza
   Supabase, el Excel de rutas y las geocercas del GPS.
4. **Esta base es de Monterrey.** QRO opera pero se lleva aparte (decisión de
   Eduardo, 2026-08-17). Aun así toda entidad lleva `sucursal_id`, para que
   incorporar QRO algún día sea un `INSERT` y no una migración.
5. **No toda unidad en campo es activo de GP.** Las 8 de `propietario = CLIENTE`
   se excluyen del cálculo de utilización y de ingreso por activo.
6. **No todo contrato en esta base es de GP.** Los 10 de las empresas hermanas
   (Torreón y Saltillo) se excluyen de toda métrica de ingreso.
7. **El registro de campo vive en SimpliRoute.** El operador cierra ahí su visita
   con hora, coordenada y evidencia. Supabase debe recibirlo por integración, no
   pedirle al operador que capture dos veces.

---

## Métrica central propuesta

EcoSan propone *Revenue per Active Asset*. Para GP la traducción correcta es:

```
Ingreso mensual recurrente
÷
unidades PROPIAS de GP en campo
```

Numerador: `SUM(contratos.monto_mensual)` de contratos activos **de GP**
(excluyendo los 10 de las empresas hermanas: −$22,156 al mes).
Denominador: `COUNT(unidades)` con `estatus='EN_CAMPO' AND propietario='GP'`.

Dos exclusiones, dos motivos distintos:
- **Unidades de cliente** (8): no son activo de GP, no van en el denominador.
- **Contratos de las hermanas** (10): su dinero no es de GP, no va en el numerador.

⚠️ Hoy no es calculable con confianza: **33 contratos no tienen `monto_mensual`**,
así que las cifras de renta contratada de este documento son el piso, no el total.
Completar esos 33 campos es el trabajo más barato con mayor retorno analítico
de toda la lista.
