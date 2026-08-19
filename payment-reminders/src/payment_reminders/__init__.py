"""Sistema de recordatorios automatizados de cuentas por cobrar.

Envía correos con plantillas personalizadas según la antigüedad de la deuda
(escalamiento) y actualiza el estatus de cada factura en una hoja de cálculo.

El paquete está diseñado para ser seguro por defecto: la simulación (dry-run)
está activa a menos que se solicite el envío explícito, y los backends de hoja
de cálculo y correo son intercambiables (Google Sheets/SMTP en producción,
CSV/consola para pruebas locales sin credenciales).
"""

__all__ = ["Invoice", "ReminderResult", "Stage", "ReminderService"]

__version__ = "1.0.0"


def __getattr__(name):
    """Importación perezosa de la API pública (PEP 562).

    Evita cargar dependencias pesadas (p. ej. Jinja2, vía ``service`` y
    ``templating``) con sólo importar el paquete. Así, herramientas que sólo
    usan un backend liviano (CSV/Excel) o que importan submódulos sueltos no
    requieren instalar todo el árbol de dependencias.
    """
    if name in ("Invoice", "ReminderResult"):
        from . import models

        return getattr(models, name)
    if name == "Stage":
        from .stages import Stage

        return Stage
    if name == "ReminderService":
        from .service import ReminderService

        return ReminderService
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
