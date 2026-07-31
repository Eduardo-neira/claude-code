"""Backend de hoja de cálculo respaldado por un archivo CSV local.

Ideal para pruebas y para operaciones sin credenciales de Google. Preserva
todas las columnas originales del archivo y sólo reescribe las celdas que
cambian (estatus y datos del último recordatorio).
"""

from __future__ import annotations

import csv
from datetime import date
from pathlib import Path
from typing import Dict, List, Optional

from ..models import Invoice, parse_amount
from .base import ColumnMap, SpreadsheetBackend, parse_date


class CsvSpreadsheet(SpreadsheetBackend):
    def __init__(self, path: str | Path, columns: Optional[ColumnMap] = None):
        self.path = Path(path)
        self.columns = columns or ColumnMap()
        self._rows: List[Dict[str, str]] = []
        self._fieldnames: List[str] = []
        self._dirty = False

    def read_invoices(self) -> List[Invoice]:
        c = self.columns
        with self.path.open("r", encoding="utf-8-sig", newline="") as fh:
            reader = csv.DictReader(fh)
            self._fieldnames = list(reader.fieldnames or [])
            self._rows = [dict(row) for row in reader]

        invoices: List[Invoice] = []
        for idx, row in enumerate(self._rows):
            invoices.append(
                Invoice(
                    invoice_id=(row.get(c.invoice_id) or "").strip(),
                    client_name=(row.get(c.client_name) or "").strip(),
                    client_email=(row.get(c.client_email) or "").strip(),
                    amount=parse_amount(row.get(c.amount)),
                    currency=(row.get(c.currency) or "MXN").strip() or "MXN",
                    issue_date=parse_date(row.get(c.issue_date)),
                    due_date=parse_date(row.get(c.due_date)),
                    status=(row.get(c.status) or "pendiente").strip(),
                    last_reminder_stage=(row.get(c.last_reminder_stage) or "").strip(),
                    last_reminder_date=parse_date(row.get(c.last_reminder_date)),
                    payment_link=(row.get(c.payment_link) or "").strip(),
                    notes=(row.get(c.notes) or "").strip(),
                    row_ref=idx,
                )
            )
        return invoices

    def stage_update(
        self,
        invoice: Invoice,
        *,
        status: Optional[str] = None,
        last_reminder_stage: Optional[str] = None,
        last_reminder_date: Optional[date] = None,
    ) -> None:
        if invoice.row_ref is None:
            raise ValueError("La factura no tiene fila asociada (¿se leyó del CSV?)")
        row = self._rows[int(invoice.row_ref)]
        c = self.columns
        if status is not None:
            row[c.status] = status
            self._ensure_field(c.status)
        if last_reminder_stage is not None:
            row[c.last_reminder_stage] = last_reminder_stage
            self._ensure_field(c.last_reminder_stage)
        if last_reminder_date is not None:
            row[c.last_reminder_date] = last_reminder_date.strftime("%Y-%m-%d")
            self._ensure_field(c.last_reminder_date)
        self._dirty = True

    def _ensure_field(self, name: str) -> None:
        if name not in self._fieldnames:
            self._fieldnames.append(name)

    def commit(self) -> None:
        if not self._dirty:
            return
        tmp = self.path.with_suffix(self.path.suffix + ".tmp")
        with tmp.open("w", encoding="utf-8", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=self._fieldnames)
            writer.writeheader()
            for row in self._rows:
                writer.writerow({k: row.get(k, "") for k in self._fieldnames})
        tmp.replace(self.path)
        self._dirty = False
