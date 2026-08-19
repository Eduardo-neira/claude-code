# Recordatorios automatizados de cuentas por cobrar

Sistema para el **seguimiento de pagos pendientes**: envía correos con
**plantillas personalizadas** según la antigüedad de la deuda (escalamiento) y
**actualiza el estatus de cada factura en una hoja de cálculo** (CSV o Google
Sheets) para una gestión eficiente de las cuentas por cobrar.

Diseñado para ser **seguro por defecto**: la simulación (*dry-run*) está activa
a menos que pidas el envío explícito con `--send`.

## ¿Qué hace?

1. Lee las facturas desde una hoja de cálculo (Google Sheets o un CSV local).
2. Para cada factura **abierta**, calcula los días respecto al vencimiento y
   determina la **etapa de cobranza** correspondiente.
3. Renderiza un correo personalizado (texto + HTML) con los datos del cliente,
   la factura, el monto, la fecha de vencimiento y el enlace de pago.
4. Envía el recordatorio (SMTP/Gmail) y **marca la factura en la hoja**
   (estatus + etapa del último recordatorio + fecha), evitando duplicados.

### Etapas de escalamiento por defecto

| Etapa                 | Días respecto al vencimiento | Tono                     |
|-----------------------|------------------------------|--------------------------|
| `proximo_vencimiento` | −3 a −1 (antes de vencer)    | Recordatorio amable      |
| `vence_hoy`           | 0                            | Aviso del día            |
| `vencido_reciente`    | 1 a 7                        | Primer aviso de mora     |
| `vencido`             | 8 a 30                       | Segundo aviso            |
| `aviso_final`         | 31 o más                     | Aviso final de cobranza  |

Cada factura recibe **un** recordatorio por etapa: al avanzar a la siguiente
etapa se envía uno nuevo; dentro de la misma etapa no se reenvía.

## Instalación

```bash
cd payment-reminders
pip install -r requirements.txt          # Jinja2 + PyYAML (mínimo)
# Opcionales:
pip install gspread google-auth          # backend de Google Sheets
pip install python-dotenv                # carga automática de .env
```

## Configuración

```bash
cp config.example.yaml config.yaml
cp .env.example .env
# Edita config.yaml (empresa, remitente, hoja, etapas) y .env (secretos).
```

Los secretos **no** se escriben en el YAML: se referencian con `${VARIABLE}` y
se leen del entorno o del archivo `.env`. `config.yaml`, `.env` y los CSV con
datos reales están en `.gitignore`.

### Hoja de cálculo

Columnas esperadas (los nombres se pueden ajustar en `columns:` del config):

| Columna                     | Descripción                                  |
|-----------------------------|----------------------------------------------|
| `factura`                   | Folio/ID de la factura                       |
| `cliente`                   | Nombre del cliente                           |
| `correo`                    | Correo de contacto                           |
| `monto`                     | Importe (acepta `$`, comas)                  |
| `moneda`                    | MXN, USD, …                                  |
| `fecha_emision`             | Fecha de emisión (opcional)                  |
| `fecha_vencimiento`         | Fecha de vencimiento                         |
| `estatus`                   | `pendiente`, `vencida`, `pagada`, …          |
| `ultimo_recordatorio`       | Etapa del último recordatorio (lo escribe el sistema) |
| `fecha_ultimo_recordatorio` | Fecha del último recordatorio (lo escribe el sistema) |
| `enlace_pago`               | Liga de pago (opcional)                       |
| `notas`                     | Notas (opcional)                             |

En `data/cuentas_por_cobrar.example.csv` hay un ejemplo listo para probar.

### Google Sheets

Usa una **cuenta de servicio** de Google Cloud con la API de Google Sheets
habilitada, comparte la hoja con el correo de la cuenta de servicio (rol
Editor) y en `config.yaml`:

```yaml
spreadsheet:
  kind: google_sheets
  options:
    spreadsheet_id: "${SHEETS_SPREADSHEET_ID}"
    worksheet: "Cuentas por cobrar"
    credentials_file: "service_account.json"
```

### Correo (Gmail / SMTP)

Para Gmail, activa la verificación en dos pasos y genera una **contraseña de
aplicación**; ponla en `SMTP_PASSWORD` del `.env`:

```yaml
mailer:
  kind: smtp
  options:
    host: "smtp.gmail.com"
    port: 587
    use_tls: true
    username: "${SMTP_USERNAME}"
    password: "${SMTP_PASSWORD}"
```

## Uso

```bash
# Simulación (no envía nada, no toca la hoja) — comportamiento por defecto
python -m payment_reminders --config config.yaml

# Envío real
python -m payment_reminders --config config.yaml --send

# Simular con una fecha específica (pruebas) y sólo ciertas facturas
python -m payment_reminders --config config.yaml --today 2026-07-31 --invoice A-101
```

Ejecuta primero **sin `--send`** para revisar el resumen y los correos que se
enviarían; cuando estés conforme, agrega `--send`.

### Salida de ejemplo (dry-run con los datos de ejemplo)

```
======================================================================
Resumen de la corrida — SIMULACIÓN (dry-run)
======================================================================
  Omitidos        3
  Se enviarían    6
  → [proximo_vencimiento] A-101 · pagos@constructoranorte.mx (-2 días de mora)
  → [vence_hoy] A-102 · cuentas@eventosmty.com (0 días de mora)
  → [vencido_reciente] A-103 · tesoreria@grupovallarta.mx (3 días de mora)
  → [vencido] A-104 · pagos@obrasqro.mx (21 días de mora)
  → [aviso_final] A-105 · admin@rentasbajio.com (60 días de mora)
  → [vencido] A-109 · compras@comercialvalle.mx (21 días de mora)
======================================================================
```

## Automatización diaria

Programa una corrida diaria con `cron` (o el Programador de tareas de Windows):

```cron
# Todos los días a las 9:00 — recordatorios de cuentas por cobrar
0 9 * * *  cd /ruta/payment-reminders && /usr/bin/python -m payment_reminders --config config.yaml --send >> reminders.log 2>&1
```

En `.github/workflows/` hay un ejemplo de flujo de GitHub Actions programado.

## Arquitectura

```
src/payment_reminders/
├── models.py            # Invoice, ReminderResult, RenderedEmail
├── stages.py            # etapas de escalamiento + selección
├── templating.py        # render de correos (Jinja2)
├── service.py           # orquestación y reglas de negocio
├── config.py            # carga de YAML + variables de entorno
├── cli.py               # interfaz de línea de comandos
├── spreadsheet/         # backends CSV y Google Sheets (intercambiables)
└── mailer/              # backends consola y SMTP (intercambiables)
templates/               # plantillas de correo (texto + HTML) por etapa
tests/                   # pruebas con pytest
```

Los backends de hoja de cálculo y de correo son **intercambiables** vía
configuración, lo que permite probar todo en local (CSV + consola) sin
credenciales antes de conectar Google Sheets y Gmail.

## Pruebas

```bash
pip install pytest
python -m pytest
```

## Notas de seguridad

- Nunca subas `config.yaml`, `.env`, `service_account.json` ni CSV con datos
  reales de clientes: ya están en `.gitignore`.
- Empieza siempre en *dry-run* y usa `--invoice` para pruebas acotadas.
- Considera configurar un `bcc` de cobranza para conservar copia de cada aviso.
