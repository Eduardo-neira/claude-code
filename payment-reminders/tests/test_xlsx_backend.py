from datetime import date

import pytest

openpyxl = pytest.importorskip("openpyxl")

from payment_reminders.spreadsheet.xlsx_backend import XlsxSpreadsheet


def _make_xlsx(path):
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.append(
        ["factura", "cliente", "correo", "monto", "moneda",
         "fecha_vencimiento", "estatus", "ultimo_recordatorio", "fecha_ultimo_recordatorio"]
    )
    ws.append(["A-1", "Cliente Uno", "uno@x.mx", 1000, "MXN", "2026-07-10", "pendiente", "", ""])
    ws.append(["A-2", "Cliente Dos", "dos@x.mx", 2000, "MXN", "2026-07-28", "pagada", "", ""])
    wb.save(path)


def test_read_and_writeback(tmp_path):
    path = tmp_path / "cxc.xlsx"
    _make_xlsx(path)

    backend = XlsxSpreadsheet(path)
    invoices = backend.read_invoices()
    assert [i.invoice_id for i in invoices] == ["A-1", "A-2"]
    assert invoices[0].amount == 1000
    assert invoices[0].due_date == date(2026, 7, 10)

    backend.stage_update(
        invoices[0],
        status="vencida",
        last_reminder_stage="vencido",
        last_reminder_date=date(2026, 7, 31),
    )
    backend.commit()

    reread = XlsxSpreadsheet(path).read_invoices()
    assert reread[0].status == "vencida"
    assert reread[0].last_reminder_stage == "vencido"
    assert reread[0].last_reminder_date == date(2026, 7, 31)
    assert reread[1].status == "pagada"  # intacta


def test_creates_missing_columns(tmp_path):
    path = tmp_path / "cxc2.xlsx"
    wb = openpyxl.Workbook()
    ws = wb.active
    # Sin columnas de recordatorio: el backend debe crearlas al escribir.
    ws.append(["factura", "cliente", "correo", "monto", "fecha_vencimiento", "estatus"])
    ws.append(["B-1", "Cliente", "b@x.mx", 500, "2026-07-10", "pendiente"])
    wb.save(path)

    backend = XlsxSpreadsheet(path)
    inv = backend.read_invoices()[0]
    backend.stage_update(inv, last_reminder_stage="vencido", last_reminder_date=date(2026, 7, 31))
    backend.commit()

    reread = XlsxSpreadsheet(path).read_invoices()
    assert reread[0].last_reminder_stage == "vencido"
