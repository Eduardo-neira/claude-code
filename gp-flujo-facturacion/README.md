# GP · Flujo de facturación automática post-servicio

Automatización que **emite una factura CFDI personalizada después de cada
servicio**, calculando la tarifa según **geocerca (ubicación)** y **tipo de
servicio**, integrando contratos, coordenadas de Google Maps y Facturama.

Stack: **Supabase (PostGIS)** + **n8n** + **Facturama (CFDI 4.0)** + **AppSheet**
+ **Troncalnet/WhatsApp**.

> Diseño operativo completo (objetivo, riesgos, métricas): [`docs/diseno-flujo.md`](docs/diseno-flujo.md).

---

## Cómo funciona (resumen)

```
AppSheet (operador cierra servicio + GPS)
        │
        ▼
Supabase  servicios.estado = 'completado'
        │   (solo si contrato con pago_confirmado = true)
        ▼
n8n  cada 10 min → vista servicios_por_facturar
        │
        ▼
Supabase  calcular_tarifa_servicio()   ← PostGIS resuelve la geocerca
        │   base × modificador + recargo_zona − descuento + IVA
        ▼
Facturama  timbra CFDI 4.0
        │
        ├─► Supabase  registra factura + marca servicio 'facturado'
        │        └─► WhatsApp al cliente con su factura
        └─► (error) registra estado 'error' + alerta a Eduardo
```

---

## Estructura del paquete

```
gp-flujo-facturacion/
├── README.md                      ← este archivo
├── docs/
│   └── diseno-flujo.md            ← SOP: proceso, riesgos, métricas, siguiente acción
├── supabase/
│   ├── migrations/
│   │   └── 0001_facturacion_geocercas.sql   ← schema + funciones (aplicar en Supabase)
│   └── seed_ejemplo.sql           ← geocercas y tarifas de EJEMPLO (ajustar a valores reales)
├── logic/
│   ├── geocerca.js                ← point-in-polygon (referencia de PostGIS)
│   ├── calcular-tarifa.js         ← fórmula de tarifa (espejo de la función SQL)
│   └── calcular-tarifa.test.js    ← 13 pruebas de la lógica de tarifa/geocerca
├── n8n/
│   └── workflow-facturacion-post-servicio.json  ← workflow importable
└── package.json                   ← `npm test` corre las pruebas de la lógica
```

---

## Componentes clave

### Supabase (`0001_facturacion_geocercas.sql`)
- **`geocercas`** — zonas por polígono (PostGIS, SRID 4326) con recargo `fijo`,
  `porcentaje` o `ninguno` y `prioridad` para traslapes.
- **`tarifas`** — precio base por `plaza × tipo_unidad × tipo_servicio`, con vigencia.
- **`tipos_servicio`** — catálogo con `modificador` y claves SAT (prod/serv, unidad).
- **`servicios`** — servicios ejecutados (fuente del disparo); `ubicacion` PostGIS
  generada desde `lat/lng`.
- **`facturas`** — registro de cada CFDI con desglose y tracking de Facturama.
- **`resolver_geocerca(lat, lng, plaza)`** — geocerca que contiene el punto.
- **`calcular_tarifa_servicio(servicio_id)`** — **fuente única de verdad del precio**;
  devuelve el desglose completo en JSONB.
- **`servicios_por_facturar`** — vista que aplica la regla de cobro anticipado.
- Campos fiscales CFDI agregados a `clientes` y `contratos`.

### Lógica JS (`logic/`)
Implementación de referencia de la misma fórmula, en JS puro y **sin
dependencias**. Sirve como Code node alterno en n8n y como red de seguridad:
las pruebas fijan los números esperados para que la fórmula no derive.

### Workflow n8n (`n8n/…json`)
13 nodos: schedule → consulta → cálculo SQL → CFDI → Facturama → registro →
WhatsApp, con rama de error → alerta a Eduardo. Importable; requiere conectar
credenciales (marcadas como `REEMPLAZAR`).

---

## Despliegue

1. **Aplicar el schema** en Supabase (staging primero):
   ```bash
   psql "$SUPABASE_DB_URL" -f supabase/migrations/0001_facturacion_geocercas.sql
   ```
   O vía el MCP de Supabase (`apply_migration`).

2. **Cargar tarifas y geocercas reales.** El seed es solo ejemplo:
   ```bash
   psql "$SUPABASE_DB_URL" -f supabase/seed_ejemplo.sql   # ← reemplazar antes con valores reales
   ```
   Ajustar precios y trazar los polígonos con coordenadas reales de cada zona.

3. **Completar datos fiscales** de clientes (`regimen_fiscal`, `uso_cfdi`,
   `codigo_postal_fiscal`) — necesarios para el CFDI 4.0.

4. **Importar el workflow** en n8n y conectar credenciales:
   - Postgres → Supabase de GP
   - HTTP Basic Auth → Facturama
   - HTTP → Troncalnet/WhatsApp
   - Variable `EDUARDO_WHATSAPP` para alertas.

5. **Probar con 1 servicio real** antes de activar el schedule de 10 min.

---

## Pruebas

```bash
npm test          # node --test sobre logic/
```

Cubren: point-in-polygon, prioridad en traslape, respeto de plaza, tarifa base,
recargo fijo, recargo porcentaje, modificador de servicio, descuento de contrato,
servicio no facturable, servicio sin coordenada y ausencia de tarifa.

---

## Notas de ajuste

- **Recargo por distancia (alternativa).** Este diseño usa polígonos. Si en el
  futuro se prefiere cobrar por km desde el patio, se sustituye el bloque de
  geocerca por una llamada a Google Distance Matrix; el resto del flujo no cambia.
- **`ExpeditionPlace` / SAT.** El workflow usa valores de ejemplo (CP 64000,
  claves SAT genéricas de servicios de limpieza). Validar con el contador de GP.
- **IVA 16%** está fijo en la función y la lógica; parametrizar si hay servicios
  a tasa distinta.
