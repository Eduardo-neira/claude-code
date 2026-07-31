# Contenido inicial del chatbot — Grupo Portátil

Insumos listos para cargar en Supabase (`tarifas` y `base_conocimiento`). Este documento resuelve el paso 2 del roadmap: **tabla de tarifas** + **FAQ iniciales**.

> **Qué tienes que hacer tú (Eduardo):**
> 1. Llenar los precios reales en la **tabla de tarifas** (los campos marcados `$____`).
> 2. Revisar las 18 FAQ y corregir cualquier respuesta que no sea exacta (marcadas con ⚠️ las que dependen de precio o política interna).
>
> Con eso el bot queda listo para la prueba piloto en el WhatsApp actual.

---

## 1 · Tabla de tarifas (plantilla para llenar)

Esta es la información que el bot usa para cotizar. **No inventa precios**: si un renglón está vacío, para ese caso el bot escala al equipo en lugar de dar un número.

| Tipo de unidad | Precio mensual (contrato periódico) | Precio por día (evento) | Servicio de limpieza | ¿Incluye insumos? (papel/gel) |
|---|---|---|---|---|
| Estándar | $____ MXN | $____ MXN/día | Incluido (semanal/quincenal) | ⚠️ Sí / No |
| Ejecutivo | $____ MXN | $____ MXN/día | Incluido | ⚠️ Sí / No |
| Discapacitados | $____ MXN | $____ MXN/día | Incluido | ⚠️ Sí / No |
| Lavamanos / accesorio | $____ MXN | $____ MXN/día | n/a | — |

**Descuentos vigentes** (confirmar):
- Volumen ≥ 5 unidades: hasta ____% (referencia previa: 10%)
- Contrato ≥ 6 meses: hasta ____% (referencia previa: 8%)
- Cliente clasificación A: condiciones especiales → **siempre escala a Eduardo**

**Notas de cobertura por plaza** (para que el bot conteste "¿dan servicio en…?"):
- **MTY:** Santa Catarina, García, Apodaca, Escobedo, Monterrey y zona metropolitana. ¿Alguna zona que **no** cubran? → ____
- **QRO:** El Marqués, Corregidora, Parque Industrial Benito Juárez, Querétaro capital. ¿Alguna zona que **no** cubran? → ____

### Seed SQL (cargar cuando estén los precios)

```sql
INSERT INTO tarifas (tipo_unidad, precio_mensual, precio_dia_evento, incluye_insumos) VALUES
  ('estandar',        0.00, 0.00, false),   -- ⚠️ llenar
  ('ejecutivo',       0.00, 0.00, false),   -- ⚠️ llenar
  ('discapacitados',  0.00, 0.00, false),   -- ⚠️ llenar
  ('lavamanos',       0.00, 0.00, false);   -- ⚠️ llenar
```

---

## 2 · Preguntas frecuentes (18 FAQ — borrador para revisar)

Respuestas redactadas en el tono de GP (cálido, directo, español MX). Las marcadas con ⚠️ **dependen de un dato que solo tú confirmas** (precio, política, cobertura); revísalas primero. El `{precio_x}` lo llena el bot desde la tabla de tarifas.

### Cobertura y zonas

**1. ¿Dan servicio en mi zona?**
> ¡Hola! 🟢 Con gusto. Damos servicio en toda la zona metropolitana de **Monterrey** y en **Querétaro** (El Marqués, Corregidora, Benito Juárez y capital). ¿En qué dirección o zona sería? Así te confirmo.

**2. ¿Tienen servicio en Querétaro?** / **¿Solo Monterrey?**
> Sí, operamos en **Monterrey y en Santiago de Querétaro**. ¿Para cuál plaza necesitas el servicio?

### Precios y cotización

**3. ⚠️ ¿Cuánto cuesta rentar un sanitario portátil?**
> Depende del tipo de unidad y del tiempo de renta. El **estándar** sale en **{precio_estandar}** al mes con limpieza incluida. ¿Me dices cuántas unidades y por cuánto tiempo? Así te doy el precio exacto (con posible descuento por volumen o contrato largo).

**4. ⚠️ ¿Cuánto por un evento de un día?**
> Para eventos manejamos tarifa por día. El estándar sale en **{precio_estandar_dia}**/día. ¿Qué fecha, cuántas unidades y en qué dirección? Con eso te confirmo disponibilidad y precio.

**5. ⚠️ ¿Hacen descuento por varias unidades?**
> Sí 🙌 A partir de cierto volumen y en contratos de varios meses aplicamos descuento. Dime cuántas unidades y por cuánto tiempo y te armo la mejor propuesta.

**6. ¿El precio incluye la limpieza?**
> Sí, en los contratos periódicos el **servicio de limpieza y vaciado va incluido** (semanal o quincenal, según lo que necesites). Solo se cobra aparte algún servicio extra fuera de la frecuencia acordada.

**7. ⚠️ ¿Incluye papel higiénico y gel?**
> *(Confirmar política real)* — Podemos incluir papel y gel antibacterial según el tipo de contrato. ¿Lo quieres con insumos incluidos? Te lo coticé de las dos formas.

### Tipos de unidad

**8. ¿Qué tipos de baño tienen?**
> Manejamos varios: **estándar**, **ejecutivo** (más equipado), y **para personas con discapacidad** (accesible). También lavamanos portátiles. ¿Para qué tipo de evento u obra lo necesitas? Te recomiendo el ideal.

**9. ¿Tienen baños para personas con discapacidad?**
> Sí, contamos con unidades **accesibles para personas con discapacidad**, más amplias y con soportes. ¿Cuántas necesitas y para qué fecha?

### Pago y facturación

**10. ¿Cómo se paga? / ¿Cómo es el proceso?**
> Trabajamos con **pago anticipado**: confirmas tu renta, realizas el pago y con eso programamos la entrega y te asignamos operador. ¿Quieres que te registre la solicitud para enviarte los datos de pago?

**11. ¿Puedo pagar después del servicio?**
> Nuestro modelo es **prepago** (pago antes del servicio), así aseguramos tu unidad y la fecha. En cuanto se confirma el pago, queda agendada tu entrega. 🟢

**12. ⚠️ ¿Dan factura?**
> Sí, facturamos con **CFDI 4.0**. Solo necesito tu **RFC, razón social, régimen fiscal y uso de CFDI**. ¿Los tienes a la mano?

**13. ⚠️ ¿Qué formas de pago aceptan?**
> *(Confirmar: transferencia, depósito, tarjeta…)* — Aceptamos **transferencia y depósito**. Te comparto los datos en cuanto registremos tu solicitud.

### Servicio y logística

**14. ⚠️ ¿En cuánto tiempo entregan?**
> *(Confirmar tiempo real por plaza)* — Una vez confirmado el pago, coordinamos la entrega en la fecha que necesites según disponibilidad y ruta. ¿Para qué día la necesitarías?

**15. ¿Cada cuánto limpian el baño?**
> Según tu contrato: puede ser **semanal o quincenal**. En eventos hacemos el servicio según la duración. ¿Qué frecuencia te acomoda?

**16. Necesito un servicio de limpieza extra / fuera de lo agendado**
> Claro, podemos programar un **servicio extra**. Si ya eres cliente, dime tu contrato o la dirección y lo agendo. *(Si aplica costo adicional, el bot escala para confirmarlo.)*

**17. Ya soy cliente y quiero agregar / quitar unidades o cambiar algo**
> Con gusto 🙌 Como es un ajuste a tu contrato, te paso con el equipo para hacerlo bien. Dime tu nombre o número de contrato y en breve te contactan.

### Incidencias (estas SIEMPRE escalan a una persona)

**18. La unidad está sucia / dañada / no la han recogido / hay una fuga**
> Lamento el inconveniente 🙏 Ya le avisé de inmediato a nuestro equipo de la plaza para atenderlo. Te contactan en breve por este mismo WhatsApp. ¿Me confirmas la dirección donde está la unidad?

---

## 3 · Cómo se cargan estas FAQ (seed de `base_conocimiento`)

Una vez revisadas, cada FAQ es un renglón. Ejemplo:

```sql
INSERT INTO base_conocimiento (categoria, pregunta_ejemplo, respuesta, plaza, activo) VALUES
  ('cobertura', '¿Dan servicio en mi zona?',
   'Damos servicio en la zona metropolitana de Monterrey y en Querétaro. ¿En qué dirección o zona sería?',
   NULL, true),
  ('pago', '¿Cómo se paga?',
   'Trabajamos con pago anticipado: confirmas tu renta, realizas el pago y con eso programamos la entrega.',
   NULL, true);
  -- ... resto de las FAQ revisadas
```

El bot no responde con el texto tal cual robotizado: usa estas respuestas como **fuente de verdad** y las adapta al mensaje del cliente. Lo que **no** improvisa nunca es precio, cobertura ni política de pago — eso sale solo de aquí.

---

## Siguiente acción

1. **Eduardo:** llena los precios en la tabla de tarifas y revisa las 18 FAQ (sobre todo las ⚠️). 20–30 min.
2. Con eso confirmado, se cargan `tarifas` y `base_conocimiento` en Supabase y se levanta el workflow `chatbot-router` en n8n conectado al **WhatsApp actual**.
3. **Prueba piloto:** activar el bot para un grupo chico de clientes/prospectos. La prueba dirá qué FAQ faltan y si el enrutamiento de escalamiento por plaza es el correcto (validación del punto 3).
