"""Interfaz común de los backends de hoja de cálculo."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import date, datetime
from typing import List, Optional

from ..models import Invoice


@dataclass
class ColumnMap:
    """Mapeo entre los campos del modelo y los encabezados de la hoja.

    Los valores por defecto están en español, acorde a una hoja de "Cuentas
    por cobrar" típica. Se pueden sobreescribir desde la configuración.
    """

    invoice_id: str = "factura"
    client_name: str = "cliente"
    client_email: str = "correo"
    amount: str = "monto"
    currency: str = "moneda"
    issue_date: str = "fecha_emision"
    due_date: str = "fecha_vencimiento"
    status: str = "estatus"
    last_reminder_stage: str = "ultimo_recordatorio"
    last_reminder_date: str = "fecha_ultimo_recordatorio"
    payment_link: str = "enlace_pago"
    notes: str = "notas"


# Formatos de fecha aceptados al leer la hoja.
_DATE_FORMATS = ("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y", "%m/%d/%Y", "%Y/%m/%d")


def parse_date(raw: object) -> Optional[date]:
    """Convierte un valor de la hoja a ``date`` probando varios formatos."""
    if raw is None or raw == "":
        return None
    if isinstance(raw, datetime):
        return raw.date()
    if isinstance(raw, date):
        return raw
    text = str(raw).strip()
    if not text:
        return None
    for fmt in _DATE_FORMATS:
        try:
            return datetime.strptime(text, fmt).date()
        except ValueError:
            continue
    return None


class SpreadsheetBackend(ABC):
    """Contrato de lectura/escritura sobre la fuente de datos de facturas."""

    @abstractmethod
    def read_invoices(self) -> List[Invoice]:
        """Devuelve todas las facturas de la hoja."""

    @abstractmethod
    def stage_update(
        self,
        invoice: Invoice,
        *,
        status: Optional[str] = None,
        last_reminder_stage: Optional[str] = None,
        last_reminder_date: Optional[date] = None,
    ) -> None:
        """Registra (en memoria) cambios a escribir para una factura."""

    @abstractmethod
    def commit(self) -> None:
        """Persiste todos los cambios pendientes en la fuente de datos."""
