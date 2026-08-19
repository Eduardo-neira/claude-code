from datetime import date

from payment_reminders.spreadsheet.csv_backend import CsvSpreadsheet

CSV = """factura,cliente,correo,monto,moneda,fecha_vencimiento,estatus,ultimo_recordatorio,fecha_ultimo_recordatorio
A-1,Cliente Uno,uno@x.mx,1000,MXN,2026-07-10,pendiente,,
A-2,Cliente Dos,dos@x.mx,2000,MXN,2026-07-28,pagada,,
"""


def test_read_and_writeback(tmp_path):
    path = tmp_path / "cxc.csv"
    path.write_text(CSV, encoding="utf-8")

    backend = CsvSpreadsheet(path)
    invoices = backend.read_invoices()
    assert len(invoices) == 2
    assert invoices[0].invoice_id == "A-1"
    assert invoices[0].amount == 1000
    assert invoices[0].due_date == date(2026, 7, 10)
    assert invoices[1].status == "pagada"

    backend.stage_update(
        invoices[0],
        status="vencida",
        last_reminder_stage="vencido",
        last_reminder_date=date(2026, 7, 31),
    )
    backend.commit()

    # Releer y verificar persistencia.
    reread = CsvSpreadsheet(path).read_invoices()
    assert reread[0].status == "vencida"
    assert reread[0].last_reminder_stage == "vencido"
    assert reread[0].last_reminder_date == date(2026, 7, 31)
    # La segunda fila no cambió.
    assert reread[1].status == "pagada"


def test_commit_noop_when_clean(tmp_path):
    path = tmp_path / "cxc.csv"
    path.write_text(CSV, encoding="utf-8")
    backend = CsvSpreadsheet(path)
    backend.read_invoices()
    before = path.read_text(encoding="utf-8")
    backend.commit()  # sin cambios
    assert path.read_text(encoding="utf-8") == before
