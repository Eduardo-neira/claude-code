"""Modelos de dominio: facturas, resultados de recordatorio y correos renderizados."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from decimal import Decimal, InvalidOperation
from typing import Optional

# Estatus que se consideran "abiertos" (la factura sigue por cobrar).
# Se normalizan a minúsculas y sin acentos antes de comparar.
DEFAULT_OPEN_STATUSES = ("pendiente", "vencida", "vencido", "parcial", "por cobrar", "")

# Estatus que cierran la factura (no se envía recordatorio).
DEFAULT_CLOSED_STATUSES = ("pagada", "pagado", "cancelada", "cancelado", "condonada")


def parse_amount(raw: object) -> Decimal:
    """Convierte un valor de la hoja (str/num) a Decimal de forma tolerante.

    Acepta formatos como "$12,500.00", "12500", "1.234,56" no es soportado
    (se asume separador de miles con coma y decimal con punto, estilo MX/US).
    """
    if isinstance(raw, Decimal):
        return raw
    if isinstance(raw, (int, float)):
        return Decimal(str(raw))
    text = str(raw or "").strip()
    if not text:
        return Decimal("0")
    # Quitar símbolos de moneda y separadores de miles.
    cleaned = (
        text.replace("$", "")
        .replace("MXN", "")
        .replace("USD", "")
        .replace(",", "")
        .strip()
    )
    try:
        return Decimal(cleaned)
    except (InvalidOperation, ValueError):
        return Decimal("0")


@dataclass
class Invoice:
    """Una factura por cobrar leída de la hoja de cálculo."""

    invoice_id: str
    client_name: str
    client_email: str
    amount: Decimal
    currency: str = "MXN"
    due_date: Optional[date] = None
    issue_date: Optional[date] = None
    status: str = "pendiente"
    last_reminder_stage: str = ""
    last_reminder_date: Optional[date] = None
    payment_link: str = ""
    notes: str = ""
    # Ubicación en el backend (índice de fila) para poder escribir de vuelta.
    row_ref: Optional[object] = field(default=None, repr=False)

    def days_overdue(self, today: date) -> Optional[int]:
        """Días transcurridos desde el vencimiento (negativo = aún no vence)."""
        if self.due_date is None:
            return None
        return (today - self.due_date).days

    def is_open(self, open_statuses=DEFAULT_OPEN_STATUSES) -> bool:
        return _normalize(self.status) in {_normalize(s) for s in open_statuses}

    def has_valid_email(self) -> bool:
        return bool(self.client_email) and "@" in self.client_email


@dataclass
class RenderedEmail:
    """Correo listo para enviar (asunto + cuerpos texto y HTML)."""

    to: str
    subject: str
    text_body: str
    html_body: str


@dataclass
class ReminderResult:
    """Resultado de procesar una factura en una corrida."""

    invoice: Invoice
    action: str  # sent | would_send | skipped | error
    stage_name: str = ""
    reason: str = ""
    email: Optional[RenderedEmail] = None
    error: str = ""

    @property
    def was_delivered(self) -> bool:
        return self.action == "sent"


def _normalize(text: str) -> str:
    """minúsculas, sin acentos ni espacios extra, para comparar estatus."""
    text = (text or "").strip().lower()
    replacements = {"á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u", "ñ": "n"}
    for accented, plain in replacements.items():
        text = text.replace(accented, plain)
    return text
