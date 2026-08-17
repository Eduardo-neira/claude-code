# 01 · Modelo de empresa — Grupo Portátil

> Equivalente GP de la §1 del blueprint EcoSan. Describe la empresa **como es**,
> no como debería verse en un organigrama.

---

## Identidad

| Campo | Valor |
|---|---|
| Giro | Renta, servicio y fabricación de sanitarios portátiles |
| Antigüedad | +7 años de operación |
| Plazas | Monterrey, N.L. (principal) · Santiago de Querétaro, Qro. (sucursal) |
| Flota | 437 unidades registradas (429 propias de GP, 8 propiedad de cliente) |
| Cartera activa | 194 contratos · ~100 clientes reales |
| Modelo de cobro | **Anticipado (prepago)** — sin pago confirmado no se genera servicio |
| Facturación contratada | $1,925,770 MXN en cobros julio–septiembre 2026 |

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

| Tipo | Contratos | Lleva IVA | Documento |
|---|---:|---|---|
| `FACTURA` | 158 | Sí (16%) | CFDI 4.0 timbrado |
| `REMISION` | 25 | No | Comprobante interno |
| `FACTURA TORREON` | 8 | Sí | CFDI de **otra razón social** `[?]` |
| `FACTURA SALTILLO` | 2 | Sí | CFDI de **otra razón social** `[?]` |
| `nan` | 1 | — | Basura de importación, eliminar |

`[?]` **Pendiente de confirmar con Eduardo:** si Torreón y Saltillo son entidades
emisoras con RFC propio. Las obras de esos contratos están en Nuevo León, así que
**no** son plazas de operación.

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
4. **La plaza importa.** MTY y QRO tienen rutas, tiempos y operadores distintos.
   Toda métrica debe poder separarse por plaza — hoy no puede.
5. **No toda unidad en campo es activo de GP.** Las 8 de `propietario = CLIENTE`
   se excluyen del cálculo de utilización y de ingreso por activo.

---

## Métrica central propuesta

EcoSan propone *Revenue per Active Asset*. Para GP la traducción correcta es:

```
Ingreso mensual recurrente
÷
unidades PROPIAS de GP en campo
```

Numerador: `SUM(contratos.monto_mensual)` de contratos activos.
Denominador: `COUNT(unidades)` con `estatus='EN_CAMPO' AND propietario='GP'`.

⚠️ Hoy no es calculable con confianza: **33 contratos no tienen `monto_mensual`**.
Completar esos 33 campos es el trabajo más barato con mayor retorno analítico
de toda la lista.
