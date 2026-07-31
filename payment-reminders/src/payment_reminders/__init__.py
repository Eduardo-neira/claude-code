"""Sistema de recordatorios automatizados de cuentas por cobrar.

Envía correos con plantillas personalizadas según la antigüedad de la deuda
(escalamiento) y actualiza el estatus de cada factura en una hoja de cálculo.

El paquete está diseñado para ser seguro por defecto: la simulación (dry-run)
está activa a menos que se solicite el envío explícito, y los backends de hoja
de cálculo y correo son intercambiables (Google Sheets/SMTP en producción,
CSV/consola para pruebas locales sin credenciales).
"""

from .models import Invoice, ReminderResult
from .stages import Stage
from .service import ReminderService

__all__ = ["Invoice", "ReminderResult", "Stage", "ReminderService"]

__version__ = "1.0.0"
