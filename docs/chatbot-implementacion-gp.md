# Chatbot de Atención al Cliente — Implementación (Grupo Portátil)

Registro de lo montado en el entorno real de GP. Complementa el diseño (`chatbot-atencion-cliente-gp.md`) y el contenido inicial (`chatbot-contenido-inicial-gp.md`).

## Supabase (proyecto `gp-inventario`)

El esquema se alineó a la estructura real: los clientes viven como texto en `contratos`, las plazas son `sucursales` (hoy solo MTY, id 1) y los precios son por-contrato. Tablas nuevas (prefijo `chatbot_`, RLS activo, sin políticas públicas → solo accesibles con service role):

| Tabla | Uso | Estado inicial |
|---|---|---|
| `chatbot_faq` | Base de conocimiento para FAQ | 18 FAQ cargadas |
| `chatbot_tarifas` | Tarifas de referencia para cotizar | 5 filas (MTY) con **precio en null** |
| `chatbot_solicitudes` | Solicitudes capturadas por el bot | vacía · `folio` autogenerado `SOL-YYYY-####` |
| `chatbot_conversaciones` | Estado/log por teléfono | vacía |

FKs reales: `sucursal_id → sucursales(id)`, `contrato_id → contratos(id)`.

## n8n (workflow `GP · Chatbot Atención al Cliente`)

- **ID:** `dnD13Xduno1cVg2j` · **Estado:** publicado (activo)
- **Endpoint (producción):** `POST https://grupoportatil.app.n8n.cloud/webhook/gp-chatbot-wa`
- **Flujo:** `Webhook (WhatsApp) → Normalizar Mensaje → Agente Atención GP → Responder al Gateway`
- **Agente (AI Agent + Claude/Anthropic)** con memoria por teléfono y 4 herramientas:
  - `Consultar_FAQ` (Supabase · lee `chatbot_faq`)
  - `Consultar_Tarifas` (Supabase · lee `chatbot_tarifas`)
  - `Registrar_Solicitud` (Supabase · inserta en `chatbot_solicitudes`)
  - `Escalar_A_Humano` (Gmail · correo a eduardo.neira@gportatil.com)
- **Credenciales:** reutiliza las existentes (Anthropic, Supabase, Gmail).

### Reglas clave codificadas en el agente
- Precios **solo** desde `Consultar_Tarifas`; si el precio está en null, **no inventa** y escala.
- Modelo **prepago**: la solicitud queda `pendiente_pago`; la entrega se programa al confirmar pago.
- Escala a humano ante queja, incidencia, negociación, cobranza/factura compleja o petición explícita.
- Distingue plaza (MTY `sucursal_id=1` / QRO).

## Pendientes para producción real

1. **Cargar precios reales** en `chatbot_tarifas` (mientras estén en null, el bot escala en vez de cotizar).
2. **Conectar el canal WhatsApp:** apuntar Troncalnet/Twilio al endpoint del webhook. Cuando exista credencial de Twilio/WhatsApp en n8n, agregar el nodo de **envío saliente** (hoy la respuesta del bot se devuelve en el JSON `reply`).
3. **Alta de QRO** en `sucursales` cuando aplique.
4. **Prueba piloto** con un grupo chico para validar FAQ faltantes y el enrutamiento de escalamiento.

## Nota de seguridad (Supabase)

El advisor de Supabase reporta que `public.spatial_ref_sys` (tabla del sistema PostGIS, preexistente, no creada por el chatbot) tiene RLS desactivado. No se modificó. Si se quiere restringir, evaluar habilitar RLS con políticas adecuadas — fuera del alcance de este chatbot.
