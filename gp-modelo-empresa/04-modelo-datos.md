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
  sucursal_id       integer references sucursales(id),
  activo            boolean not null default true,
  created_at        timestamptz not null default now()
);

alter table contratos add column if not exists sitio_id integer references sitios(id);
```

**Nota:** 60 contratos activos no tienen coordenadas. Esos sitios nacen sin
geolocalizar y **no podrán resolver recargo por geocerca**. Completarlos es
prerrequisito de la facturación por zona.

---

## Cambio 3 · Desarmar `datos_fiscales` — Prioridad 1

Un campo de texto carga tres conceptos. Se separan:

```sql
create table emisores (
  id             integer generated always as identity primary key,
  clave          text unique not null,      -- 'GP', 'TORREON', 'SALTILLO'
  razon_social   text not null,
  rfc            text not null,
  regimen_fiscal text,
  activo         boolean not null default true
);

alter table contratos
  add column if not exists es_fiscal  boolean,
  add column if not exists emisor_id  integer references emisores(id);

-- Poblado desde el texto existente:
update contratos set es_fiscal = (upper(coalesce(datos_fiscales,'')) like '%FACTURA%');
-- 'FACTURA TORREON'  -> emisor TORREON   (8 contratos)
-- 'FACTURA SALTILLO' -> emisor SALTILLO  (2 contratos)
-- 'FACTURA'          -> emisor GP        (158 contratos)
-- 'REMISION'         -> es_fiscal = false (25 contratos)
-- 'nan'              -> fila a eliminar   (1: cliente vacío, sin dirección)
```

⚠️ **Bloqueado por decisión de Eduardo:** confirmar si Torreón y Saltillo son
razones sociales con RFC propio. Si no lo son, el modelo cambia.

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

Hoy: `sucursales` = 1 fila (MTY). **194 de 194 contratos con `sucursal_id` NULL.**
Los 5 operadores también. Las 437 unidades tienen prefijo `MTY`.

```sql
insert into sucursales (nombre, clave, ciudad, estado)
values ('Grupo Portátil Querétaro','QRO','Santiago de Querétaro','Querétaro');

-- Todo lo existente es Monterrey (verificado: coordenadas 25.43-25.93 N,
-- -100.53 a -100.34 W, y los 437 códigos de unidad con prefijo MTY):
update contratos  set sucursal_id = 1 where sucursal_id is null;
update operadores set sucursal_id = 1 where sucursal_id is null and alias <> 'Juan Pablo';
update operadores set sucursal_id = 2 where alias = 'Juan Pablo';  -- base QRO
```

⚠️ **Verificar antes de correr:** ¿la operación de QRO debe vivir en esta base?
Si sí, falta cargar sus unidades y contratos, que hoy no existen aquí.

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
firma y a veces incidencia.

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

Es lo que llena `servicios`. Hoy la programación vive en `frecuencia` (`LMV`/`MJS`)
como texto.

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

---

## Cambio 12 · Eventos de dominio — Prioridad 3

`event_log` existe pero es un log de idempotencia de webhooks (PK = `event_id`
de texto, con `origen` y `payload`). No es un bus de eventos de dominio.
Conviene dejarlo como está y crear el bus aparte:

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

Y políticas RLS por rol. Crítico antes de que operadores (AppSheet) y clientes
(chatbot) escriban directamente en Supabase.

---

## Relaciones objetivo

```text
clientes
   ├── cliente_contactos
   ├── sitios
   └── contratos
          ├── contrato_unidades ──► unidades
          │                            ├── unidad_movimientos
          │                            └── mantenimientos
          ├── servicios
          │      ├── servicio_unidades ──► unidades
          │      ├── servicio_evidencias
          │      └── ruta_servicios ──► rutas ──► operadores
          ├── cobros
          │      └── facturas ──► emisores
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

---

## Orden de ejecución

| Fase | Cambios | Desbloquea |
|---|---|---|
| **1** | 11 (calendario) + 5 (plazas) + conciliar cobros | `servicios` deja de estar vacía; facturación automática puede disparar |
| **2** | 1 (clientes) + 2 (sitios) + 4 (ciclo de vida) + 3 (fiscal) | Cartera, concentración, renovaciones, CFDI correcto |
| **3** | 6, 7, 8, 9, 10 | Evidencia, historial de activo, integridad de flota |
| **4** | 12, 13 | Automatización por eventos y seguridad por rol |
