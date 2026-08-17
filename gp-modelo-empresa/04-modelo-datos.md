# 04 · Modelo de datos — Grupo Portátil

> Equivalente GP de las §5-§19, §30 y §31 del blueprint EcoSan.
> Plan de migración concreto sobre el schema real de `gp-inventario`.
>
> ⚠️ **Nada de este documento está aplicado.** Es un plan para revisar antes de
> tocar producción. La base tiene 437 unidades, 194 contratos y 337 cobros
> reales.

---

## Principio rector

**Migración aditiva.** No se recrean tablas ni se migran datos a ciegas. Se
agregan entidades y columnas, se rellenan, y solo al final se retiran los campos
viejos. Ese fue el enfoque de la migración `0001` (geocercas + tarifa) y funcionó.

---

## Convenciones (§30 de EcoSan) — decisión para GP

| Tema | EcoSan | GP hoy | Decisión |
|---|---|---|---|
| Identificadores | UUID en todo | Mezcla: `integer` en núcleo, `uuid` en chatbot/perfiles | **Mantener `integer` en el núcleo.** Cambiarlo obliga a reescribir 8 tablas y todas las FK por un beneficio nulo a esta escala |
| Fechas | UTC | `timestamptz` ✅ | Correcto, mantener |
| Dinero | `decimal`, nunca `float` | `numeric` ✅ | Correcto, mantener |
| Soft delete | `deleted_at` | `activo` booleano | Mantener `activo`; agregar `deleted_at` solo donde haga falta |
| Auditoría | `created_by` / `updated_by` | Solo `created_at` / `updated_at` | **Agregar autor** en contratos, cobros y facturas |
| Log de auditoría | `audit_logs` | ❌ | Crear para las tablas de dinero |

**Nota sobre el punto 1:** es la única desviación deliberada del blueprint.
La consistencia interna importa más que seguir la recomendación al pie.

---

## Cambio 1 · Crear `clientes` — Prioridad 1

Hoy: `contratos.cliente` es texto. 106 valores distintos ⇒ ~100 clientes reales.

```sql
create table clientes (
  id                  integer generated always as identity primary key,
  razon_social        text not null,
  nombre_comercial    text,
  rfc                 text,
  regimen_fiscal      text,          -- clave SAT, para CFDI 4.0
  uso_cfdi            text,          -- clave SAT
  codigo_postal       text,          -- obligatorio en CFDI 4.0
  tipo_cliente        text check (tipo_cliente in
                        ('construccion','industrial','evento','gobierno','otro')),
  clasificacion       text check (clasificacion in ('A','B','C')),
  dias_credito        integer not null default 0,   -- 0 = prepago (el estándar GP)
  sucursal_id         integer references sucursales(id),
  activo              boolean not null default true,
  notas               text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table cliente_contactos (
  id           integer generated always as identity primary key,
  cliente_id   integer not null references clientes(id) on delete cascade,
  nombre       text not null,
  rol          text check (rol in ('obra','oficina','pagos','otro')),
  telefono     text,
  whatsapp     text,
  correo       text,
  es_principal boolean not null default false
);

alter table contratos add column if not exists cliente_id integer references clientes(id);
```

### Migración de los 106 textos
No automatizable a ciegas — los ~6 duplicados requieren criterio
(`NEGOCIACION INDUSTRIAL CARVID` vs `NEGOCIACION INDUSTRIAL CARVID (NUEVO)`:
¿mismo cliente o dos?).

**Procedimiento:**
1. Generar el listado de 106 textos con su conteo de contratos.
2. Eduardo marca a mano las agrupaciones (una sesión, ~30 min).
3. Insertar clientes y poblar `contratos.cliente_id`.
4. Conservar `contratos.cliente` como texto histórico hasta validar.

⚠️ Los sufijos `(NUEVO)` y `(SOLO LIMPIEZA)` dentro del nombre son metadatos
disfrazados de nombre. Al normalizar, esa información pasa a columnas propias.

---

## Cambio 2 · Extraer `sitios` — Prioridad 1

Hoy la obra vive dentro del contrato (`direccion_obra`, `latitud`, `longitud`,
`contacto_obra`). Por eso `GTC TERMO CONTROL` tiene 4 contratos: son 4 obras.

```sql
create table sitios (
  id                integer generated always as identity primary key,
  cliente_id        integer not null references clientes(id),
  nombre            text not null,             -- "Torre Vista Norte"
  direccion         text,
  latitud           numeric(10,6),
  longitud          numeric(10,6),
  municipio         text,
  notas_acceso      text,                      -- hoy se pierde en observaciones
  ventana_inicio    time,                      -- obras: 7:00
  ventana_fin       time,                      -- obras: 16:00
  simpliroute_ref   text,                      -- amarre con la visita de SimpliRoute
  sucursal_id       integer references sucursales(id),
  activo            boolean not null default true,
  created_at        timestamptz not null default now()
);

alter table contratos add column if not exists sitio_id integer references sitios(id);
```

**Nota:** 60 contratos activos no tienen coordenadas. Esos sitios nacen sin
geolocalizar y **no podrán resolver recargo por geocerca ni amarrarse por
coordenada con SimpliRoute**. Completarlos es prerrequisito de las dos cosas.

---

## Cambio 3 · Desarmar `datos_fiscales` — Prioridad 1

**Confirmado por Eduardo (2026-08-17):** `TORREON` y `SALTILLO` son **razones
sociales distintas — empresas hermanas de familiares, con administración y
finanzas aparte**. No son plazas de operación ni divisiones de GP.

Eso cambia el propósito de la separación. No se trata solo de timbrar con el RFC
correcto: se trata de que **los ingresos de terceros no se cuenten como de GP**.

Un campo de texto carga tres conceptos. Se separan:

```sql
create table entidades_facturacion (
  id             integer generated always as identity primary key,
  clave          text unique not null,      -- 'GP', 'TORREON', 'SALTILLO'
  razon_social   text not null,
  rfc            text,
  es_grupo_portatil boolean not null default false,  -- ← la columna que importa
  notas          text,
  activo         boolean not null default true
);

insert into entidades_facturacion (clave, razon_social, es_grupo_portatil, notas) values
  ('GP',       'Grupo Portátil',       true,  'Entidad principal'),
  ('TORREON',  '(por confirmar)',      false, 'Empresa hermana, finanzas aparte'),
  ('SALTILLO', '(por confirmar)',      false, 'Empresa hermana, finanzas aparte');

alter table contratos
  add column if not exists es_fiscal boolean,
  add column if not exists entidad_facturacion_id integer
    references entidades_facturacion(id);

-- Poblado desde el texto existente (conteos verificados en la base):
update contratos set es_fiscal = (upper(coalesce(datos_fiscales,'')) like '%FACTURA%');
-- 'FACTURA'          -> GP,       es_fiscal = true   (158 contratos)
-- 'REMISION'         -> GP,       es_fiscal = false  (25 contratos)
-- 'FACTURA TORREON'  -> TORREON,  es_fiscal = true   (8 contratos)
-- 'FACTURA SALTILLO' -> SALTILLO, es_fiscal = true   (2 contratos)
-- 'nan'              -> fila a eliminar               (1: cliente vacío, sin dirección)
```

### La regla que se desprende

Toda métrica de dinero de GP debe filtrar por `es_grupo_portatil = true`:

```sql
-- Ingreso recurrente REAL de Grupo Portátil:
select sum(c.monto_mensual)
from contratos c
join entidades_facturacion e on e.id = c.entidad_facturacion_id
where c.activo and e.es_grupo_portatil;
```

Sin ese filtro, la facturación de GP queda inflada en **$22,156 mensuales**
(8 contratos de Torreón por $19,836 + 2 de Saltillo por $2,320) — 2.2% del total.

⚠️ **No usar `rfc not null`.** Los RFC de las hermanas son de terceros y GP
puede no necesitarlos nunca: si su propia administración timbra, GP solo debe
**marcarlas y excluirlas**, no facturar por ellas.

⚠️ **Pendiente de aclarar:** si GP les da el servicio operativo (entonces las
9 unidades colocadas **sí** son activo de GP y cuentan para utilización) o si es
operación ajena que solo comparte la base.

Al terminar, `calcular_tarifa_servicio()` debe leer `contratos.es_fiscal` en vez
de hacer `LIKE '%FACTURA%'` sobre texto libre.

---

## Cambio 4 · Ciclo de vida del contrato — Prioridad 1

```sql
alter table contratos
  add column if not exists fecha_fin    date,
  add column if not exists estado       text not null default 'activo'
    check (estado in ('borrador','firmado','activo','suspendido',
                      'vencido','cancelado')),
  add column if not exists auto_renueva boolean not null default true,
  add column if not exists created_by   text,
  add column if not exists updated_by   text;
```

**`fecha_fin` es la columna que más análisis desbloquea:** vencimientos,
renovaciones, churn, valor de contrato, alertas anticipadas. Hoy ninguno es
posible. `NULL` = renovación automática mes a mes (el caso normal de GP).

---

## Cambio 5 · Plazas — Prioridad 1

**Confirmado por Eduardo (2026-08-17): Querétaro opera, pero se lleva aparte.**
Esta base es de Monterrey. **No se da de alta la sucursal QRO** ni se cargan sus
unidades o contratos.

Hoy: `sucursales` = 1 fila (MTY). **194 de 194 contratos con `sucursal_id` NULL.**
Los 5 operadores también.

```sql
-- Todo lo que existe en esta base es Monterrey (verificado: coordenadas
-- 25.43-25.93 N, -100.53 a -100.34 W, y los 437 códigos con prefijo MTY):
update contratos  set sucursal_id = 1 where sucursal_id is null;
update unidades   set sucursal_id = 1 where sucursal_id is null;
update operadores set sucursal_id = 1 where sucursal_id is null;
```

### Por qué sí llenar `sucursal_id` aunque solo haya una plaza

Parece trabajo inútil llenar 194 filas con el mismo valor. No lo es:

1. El día que QRO **sí** entre, es un `INSERT` y nada más — no una migración de
   toda la base con riesgo sobre datos de producción.
2. El puente de SimpliRoute necesita filtrar qué visitas son de MTY. Sin
   `sucursal_id` poblado no hay por dónde filtrar.
3. Las vistas y KPIs ya agrupan por plaza (`vista_desempeno_operadores` deriva la
   plaza del contrato y hace *fallback* a `'MTY'` porque hoy siempre es NULL).
   Ese *fallback* es una curita que conviene retirar.

⚠️ **Juan Pablo** está registrado como operador (`id = 2`) pero su base es QRO.
Si QRO se lleva aparte, decidir: ¿se marca inactivo en esta base, o se deja con
`sucursal_id` NULL a propósito? Dejarlo como MTY sería incorrecto y ensuciaría
la productividad por operador.

### Costo aceptado de esta decisión
La métrica #1 del corte semanal (`Unidades en renta MTY+QRO`) **nunca podrá
salir completa de este sistema**. Seguirá armándose a mano juntando dos fuentes.
Es una consecuencia asumida, no un descuido.

---

## Cambio 6 · Servicio ↔ unidades N:N — Prioridad 2

Hoy `servicios.unidad_id` liga a **una** unidad. Una obra con 5 sanitarios se
sirve en una visita.

```sql
create table servicio_unidades (
  id            integer generated always as identity primary key,
  servicio_id   integer not null references servicios(id) on delete cascade,
  unidad_id     integer not null references unidades(id),
  accion        text check (accion in
                  ('limpieza','entrega','retiro','sustitucion','inspeccion')),
  resultado     text check (resultado in
                  ('ok','requiere_mantenimiento','no_encontrada','sin_acceso')),
  observaciones text,
  unique (servicio_id, unidad_id)
);
```

`servicios.unidad_id` se conserva mientras se migra; después se retira.

---

## Cambio 7 · Evidencias — Prioridad 2

Hoy: un `servicios.foto_url`. Un servicio real produce foto antes, foto después,
firma y a veces incidencia — y SimpliRoute ya las captura todas.

```sql
create table servicio_evidencias (
  id           integer generated always as identity primary key,
  servicio_id  integer not null references servicios(id) on delete cascade,
  unidad_id    integer references unidades(id),
  tipo         text not null check (tipo in
                 ('foto_antes','foto_despues','firma','incidencia','documento')),
  storage_url  text not null,
  capturada_por text,
  latitud      numeric(10,6),
  longitud     numeric(10,6),
  capturada_en timestamptz not null default now()
);
create index on servicio_evidencias (servicio_id);
```

**Regla:** un servicio no puede pasar a `completado` sin al menos una evidencia
de tipo `foto_despues`.

⚠️ Decidir si las imágenes se **copian** a Supabase Storage o solo se guarda la
URL de SimpliRoute. Guardar solo la URL es más barato, pero si un día se deja de
pagar SimpliRoute se pierde toda la evidencia histórica — justo la que sirve
ante un reclamo.

---

## Cambio 8 · Historial de unidades — Prioridad 2

§9 de EcoSan: *nunca sobrescribas solo el estado*.

```sql
create table unidad_movimientos (
  id            integer generated always as identity primary key,
  unidad_id     integer not null references unidades(id),
  tipo          text not null check (tipo in
                  ('colocacion','retiro','traslado','mantenimiento',
                   'alta','baja','venta')),
  desde         text,                 -- 'BODEGA MTY' o sitio
  hacia         text,
  contrato_id   integer references contratos(id),
  servicio_id   integer references servicios(id),
  operador_id   integer references operadores(id),
  ocurrido_en   timestamptz not null default now(),
  nota          text
);
create index on unidad_movimientos (unidad_id, ocurrido_en desc);
```

Desbloquea: días ociosos por unidad, ingreso acumulado por unidad, costo de
mantenimiento por unidad, y el escaneo de QR con historial completo (§8 de EcoSan).

---

## Cambio 9 · Estado `MANTENIMIENTO` en unidades — Prioridad 2

Verificado en la base: **`unidades.estatus` no tiene ninguna restricción `CHECK`.**
Es texto libre con default `'BODEGA'`. Hoy nada impide guardar `'EN CAMPO'`
(con espacio), `'en_campo'` o cualquier variante, y esas filas desaparecerían
silenciosamente de todo conteo por estatus. `contratos.modalidad`,
`unidades.propietario` y `cobros.estado` sí están restringidos; `estatus` se quedó fuera.

```sql
-- 1) Revisar primero que no haya variantes fuera del catálogo:
select estatus, count(*) from unidades group by 1 order by 2 desc;

-- 2) Solo si el paso 1 devuelve exactamente los 4 valores esperados:
alter table unidades add constraint unidades_estatus_check
  check (estatus in ('BODEGA','EN_CAMPO','MANTENIMIENTO','EN_VENTA','BAJA'));
```

Al 2026-08-17 los valores presentes son `BODEGA`, `EN_CAMPO`, `EN_VENTA` y `BAJA`
— limpios. Agregar la restricción ahora es barato; después de meses de captura
manual, no.

Además falta el estado `MANTENIMIENTO`: hoy una unidad en reparación se cuenta
como disponible en bodega, lo que infla la disponibilidad y explica parte del
descuadre de §Invariantes.

---

## Cambio 10 · Invariantes de flota — Prioridad 2

Descuadres medidos hoy:

| Inconsistencia | Casos |
|---|---:|
| Unidad `EN_CAMPO` sin colocación vigente | 11 |
| Colocación vigente de unidad que no está `EN_CAMPO` | 16 |
| Contrato activo sin ninguna unidad | 12 |

```sql
-- Vista de control, para revisar antes de imponer la regla:
create or replace view control_descuadres_flota as
select 'unidad_en_campo_sin_colocacion' motivo, u.id, u.codigo, null::int contrato_id
from unidades u
where u.estatus = 'EN_CAMPO'
  and not exists (select 1 from contrato_unidades cu
                  where cu.unidad_id = u.id and cu.fecha_retiro is null)
union all
select 'colocacion_de_unidad_no_en_campo', u.id, u.codigo, cu.contrato_id
from contrato_unidades cu join unidades u on u.id = cu.unidad_id
where cu.fecha_retiro is null and u.estatus <> 'EN_CAMPO'
union all
select 'contrato_activo_sin_unidad', null, null, c.id
from contratos c
where c.activo
  and not exists (select 1 from contrato_unidades cu
                  where cu.contrato_id = c.id and cu.fecha_retiro is null);
```

**Primero se limpian los 39 casos, después se pone el trigger.** Poner la regla
antes bloquea operaciones legítimas y el equipo la va a rodear.

---

## Cambio 11 · Calendario de servicios — Prioridad 1

Es lo que llena `servicios` del lado planeado. Hoy la programación vive en
`frecuencia` (`LMV`/`MJS`) como texto.

```sql
-- Genera los servicios planeados de una semana a partir de la banda del contrato.
-- LMV = lunes(1), miércoles(3), viernes(5)   ISO
-- MJS = martes(2), jueves(4), sábado(6)
create or replace function generar_servicios_semana(p_lunes date)
returns integer language plpgsql as $$
declare v_creados integer := 0;
begin
  insert into servicios (contrato_id, fecha_servicio, tipo, completado, source)
  select c.id,
         p_lunes + (d - 1),
         'LIMPIEZA',
         false,
         'calendario'
  from contratos c
  cross join lateral (
    select unnest(case upper(coalesce(c.frecuencia,''))
                    when 'LMV' then array[1,3,5]
                    when 'MJS' then array[2,4,6]
                    else array[]::int[] end) as d
  ) dias
  where c.activo
    and not exists (
      select 1 from servicios s
      where s.contrato_id = c.id
        and s.fecha_servicio = p_lunes + (dias.d - 1)
    );
  get diagnostics v_creados = row_count;
  return v_creados;
end;
$$;
```

⚠️ **Requiere primero** cambiar el default de `servicios.completado` de `true` a
`false` — hoy un servicio nace marcado como completado, lo que hace imposible
distinguir planeado de ejecutado:

```sql
alter table servicios alter column completado set default false;
```

⚠️ Los 3 contratos con banda `EXTRA` no generan calendario: son bajo demanda.

**Sinergia con el puente de SimpliRoute:** si estos servicios planeados se mandan
a SimpliRoute con el `contrato_id` (o el `servicio.id`) en la referencia de la
visita, el amarre de regreso queda resuelto de origen. Ver `06` §AUT-10.

---

## Cambio 12 · Eventos de dominio — Prioridad 3

`event_log` existe pero es un log de idempotencia de webhooks (PK = `event_id`
de texto, con `origen` y `payload`). No es un bus de eventos de dominio.
Conviene dejarlo como está — el puente de SimpliRoute lo va a necesitar
exactamente para eso — y crear el bus aparte:

```sql
create table domain_events (
  id           bigint generated always as identity primary key,
  tipo         text not null,          -- 'servicio.completado'
  entidad      text not null,          -- 'servicio'
  entidad_id   text not null,
  payload      jsonb not null default '{}'::jsonb,
  ocurrido_en  timestamptz not null default now(),
  procesado_en timestamptz,
  error        text
);
create index on domain_events (tipo, ocurrido_en desc);
create index on domain_events (procesado_en) where procesado_en is null;
```

---

## Cambio 13 · Roles y permisos — Prioridad 3

```sql
alter type rol_app add value if not exists 'direccion';
alter type rol_app add value if not exists 'operaciones';
alter type rol_app add value if not exists 'cobranza';
alter type rol_app add value if not exists 'operador';
alter type rol_app add value if not exists 'cliente';
```

Y políticas RLS por rol. Crítico antes de que las integraciones y el chatbot
escriban directamente en Supabase.

---

## Relaciones objetivo

```text
clientes
   ├── cliente_contactos
   ├── sitios
   └── contratos ──► entidades_facturacion
          ├── contrato_unidades ──► unidades
          │                            ├── unidad_movimientos
          │                            └── mantenimientos
          ├── servicios
          │      ├── servicio_unidades ──► unidades
          │      ├── servicio_evidencias
          │      └── ruta_servicios ──► rutas ──► operadores
          ├── cobros
          │      └── facturas          ← la factura cuelga del COBRO (mensual)
          └── (sitio_id) ──► sitios

geocercas ──(PostGIS)──► tarifa del servicio
insumos ──► insumo_existencias / movimientos_insumo ──► rutas
domain_events (transversal)
```

---

## Lo que NO hay que hacer (§32 de EcoSan)

- **No** convertir `contratos` en la tabla de todo. Ya carga cliente, sitio,
  contacto, fiscal, precio y programación. Es el antipatrón de las 80 columnas.
- **No** guardar la lista de unidades de un contrato como JSON. Ya existe
  `contrato_unidades` y funciona.
- **No** crear una base aparte para cobranza porque hoy vive en Sheets.
  Migrarla al mismo Supabase es el punto.
- **No** cambiar `integer` por `uuid` en el núcleo. Costo alto, beneficio nulo.
- **No** colgar la factura del servicio. GP factura mensual: cuelga del `cobro`.

---

## Orden de ejecución

| Fase | Cambios | Desbloquea |
|---|---|---|
| **1** | 11 (calendario) + 5 (plazas) + puente SimpliRoute + conciliar cobros | `servicios` deja de estar vacía; la facturación mensual puede disparar |
| **2** | 1 (clientes) + 2 (sitios) + 4 (ciclo de vida) + 3 (entidades) | Cartera, concentración, renovaciones, CFDI correcto, ingresos de GP separados |
| **3** | 6, 7, 8, 9, 10 | Evidencia, historial de activo, integridad de flota |
| **4** | 12, 13 | Automatización por eventos y seguridad por rol |
