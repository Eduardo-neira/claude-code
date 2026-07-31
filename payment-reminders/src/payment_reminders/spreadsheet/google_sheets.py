"""Backend de Google Sheets (usa gspread + una cuenta de servicio).

Se importa de forma perezosa: las dependencias ``gspread`` y
``google-auth`` sólo se requieren si realmente se usa este backend.

Autenticación recomendada: una **cuenta de servicio** de Google Cloud con la
API de Google Sheets habilitada. Comparte la hoja de cálculo con el correo de
la cuenta de servicio (rol Editor) y apunta ``credentials_file`` al JSON de la
llave, o define ``GOOGLE_APPLICATION_CREDENTIALS``.
"""

from __future__ import annotations

from datetime import date
from typing import Dict, List, Optional, Tuple

from ..models import Invoice, parse_amount
from .base import ColumnMap, SpreadsheetBackend, parse_date

_SCOPES = ["https://www.googleapis.com/auth/spreadsheets"]


class GoogleSheetsSpreadsheet(SpreadsheetBackend):
    def __init__(
        self,
        spreadsheet_id: str,
        worksheet: str = "Sheet1",
        credentials_file: Optional[str] = None,
        columns: Optional[ColumnMap] = None,
    ):
        self.spreadsheet_id = spreadsheet_id
        self.worksheet_name = worksheet
        self.credentials_file = credentials_file
        self.columns = columns or ColumnMap()

        self._ws = None
        self._header: List[str] = []
        self._col_index: Dict[str, int] = {}
        # Actualizaciones pendientes: (fila_1based, col_1based) -> valor
        self._pending: Dict[Tuple[int, int], str] = {}

    # -- conexión --------------------------------------------------------
    def _worksheet(self):
        if self._ws is not None:
            return self._ws
        try:
            import gspread
            from google.oauth2.service_account import Credentials
        except ImportError as exc:  # pragma: no cover - depende del entorno
            raise ImportError(
                "El backend de Google Sheets requiere 'gspread' y "
                "'google-auth'. Instálalos con: pip install gspread google-auth"
            ) from exc

        if self.credentials_file:
            creds = Credentials.from_service_account_file(
                self.credentials_file, scopes=_SCOPES
            )
            client = gspread.authorize(creds)
        else:
            # Usa GOOGLE_APPLICATION_CREDENTIALS del entorno.
            import google.auth

            creds, _ = google.auth.default(scopes=_SCOPES)
            client = gspread.authorize(creds)

        sheet = client.open_by_key(self.spreadsheet_id)
        self._ws = sheet.worksheet(self.worksheet_name)
        return self._ws

    # -- lectura ---------------------------------------------------------
    def read_invoices(self) -> List[Invoice]:
        ws = self._worksheet()
        rows = ws.get_all_values()
        if not rows:
            return []
        self._header = rows[0]
        self._col_index = {name: i for i, name in enumerate(self._header)}

        c = self.columns
        invoices: List[Invoice] = []
        for offset, raw in enumerate(rows[1:]):
            row = {self._header[i]: (raw[i] if i < len(raw) else "") for i in range(len(self._header))}
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
                    row_ref=offset + 2,  # +1 encabezado, +1 base-1 de Sheets
                )
            )
        return invoices

    # -- escritura -------------------------------------------------------
    def _col_for(self, field_header: str) -> Optional[int]:
        if field_header in self._col_index:
            return self._col_index[field_header] + 1  # base-1
        return None

    def stage_update(
        self,
        invoice: Invoice,
        *,
        status: Optional[str] = None,
        last_reminder_stage: Optional[str] = None,
        last_reminder_date: Optional[date] = None,
    ) -> None:
        if invoice.row_ref is None:
            raise ValueError("La factura no tiene fila asociada (¿se leyó de la hoja?)")
        row = int(invoice.row_ref)
        c = self.columns
        updates = {
            c.status: status,
            c.last_reminder_stage: last_reminder_stage,
            c.last_reminder_date: (
                last_reminder_date.strftime("%Y-%m-%d") if last_reminder_date else None
            ),
        }
        for header, value in updates.items():
            if value is None:
                continue
            col = self._col_for(header)
            if col is None:
                # La columna no existe en la hoja: se omite en silencio para
                # no romper la corrida (el operador puede agregarla después).
                continue
            self._pending[(row, col)] = value

    def commit(self) -> None:
        if not self._pending:
            return
        ws = self._worksheet()
        try:
            from gspread.utils import rowcol_to_a1
        except ImportError:  # pragma: no cover
            rowcol_to_a1 = None

        cells = []
        for (row, col), value in self._pending.items():
            if rowcol_to_a1 is not None:
                cells.append({"range": rowcol_to_a1(row, col), "values": [[value]]})
            else:  # pragma: no cover - fallback improbable
                ws.update_cell(row, col, value)

        if cells:
            ws.batch_update(cells)
        self._pending.clear()
