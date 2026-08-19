from datetime import date
from decimal import Decimal

import pytest

pytest.importorskip("jinja2")  # el servicio renderiza plantillas con Jinja2

from conftest import TEMPLATES_DIR

from payment_reminders.mailer.console import ConsoleMailBackend
from payment_reminders.mailer.base import Sender
from payment_reminders.models import Invoice
from payment_reminders.service import ReminderService
from payment_reminders.spreadsheet.csv_backend import CsvSpreadsheet
from payment_reminders.stages import DEFAULT_STAGES
from payment_reminders.templating import TemplateRenderer

CSV = """factura,cliente,correo,monto,moneda,fecha_vencimiento,estatus,ultimo_recordatorio,fecha_ultimo_recordatorio,enlace_pago
A-1,Vence Pronto,pronto@x.mx,1000,MXN,2026-08-02,pendiente,,,http://pago/A-1
A-2,Vence Hoy,hoy@x.mx,2000,MXN,2026-07-31,pendiente,,,http://pago/A-2
A-3,Mora Reciente,mora@x.mx,3000,MXN,2026-07-28,pendiente,,,http://pago/A-3
A-4,Ya Recordado,rec@x.mx,4000,MXN,2026-07-10,vencida,vencido,2026-07-15,http://pago/A-4
A-5,Sin Correo,,5000,MXN,2026-07-10,pendiente,,,http://pago/A-5
A-6,Pagada,pagada@x.mx,6000,MXN,2026-07-10,pagada,,,http://pago/A-6
A-7,Sin Vencimiento,sv@x.mx,7000,MXN,,pendiente,,,http://pago/A-7
"""

TODAY = date(2026, 7, 31)


def _service(path, mailer=None):
    backend = CsvSpreadsheet(path)
    mailer = mailer or ConsoleMailBackend(
        Sender(name="Cobranza", email="cobranza@x.mx"), verbose=False
    )
    renderer = TemplateRenderer(TEMPLATES_DIR, company={"name": "Demo"})
    service = ReminderService(backend, mailer, renderer, DEFAULT_STAGES)
    return service, backend, mailer


def _write(tmp_path):
    path = tmp_path / "cxc.csv"
    path.write_text(CSV, encoding="utf-8")
    return path


def test_dry_run_sends_nothing_and_computes_stages(tmp_path):
    path = _write(tmp_path)
    service, backend, mailer = _service(path)

    summary = service.run(today=TODAY, dry_run=True)

    would = {r.invoice.invoice_id: r.stage_name for r in summary.results if r.action == "would_send"}
    assert would == {
        "A-1": "proximo_vencimiento",
        "A-2": "vence_hoy",
        "A-3": "vencido_reciente",
    }
    # A-4 ya recordado en esa etapa, A-5 sin correo, A-6 pagada, A-7 sin fecha
    skipped = {r.invoice.invoice_id for r in summary.results if r.action == "skipped"}
    assert skipped == {"A-4", "A-5", "A-6", "A-7"}

    # Dry-run no envía correos ni toca el archivo.
    assert mailer.outbox == []
    assert path.read_text(encoding="utf-8") == CSV


def test_send_delivers_and_updates_sheet(tmp_path):
    path = _write(tmp_path)
    service, backend, mailer = _service(path)

    summary = service.run(today=TODAY, dry_run=False)

    sent_ids = {r.invoice.invoice_id for r in summary.results if r.action == "sent"}
    assert sent_ids == {"A-1", "A-2", "A-3"}
    assert len(mailer.outbox) == 3

    # La hoja se actualizó: etapa registrada y factura marcada vencida si aplica.
    reread = {i.invoice_id: i for i in CsvSpreadsheet(path).read_invoices()}
    assert reread["A-3"].last_reminder_stage == "vencido_reciente"
    assert reread["A-3"].last_reminder_date == TODAY
    assert reread["A-3"].status == "vencida"  # 3 días de mora
    # A-1 aún no vence: conserva estatus pendiente pero registra el recordatorio.
    assert reread["A-1"].status == "pendiente"
    assert reread["A-1"].last_reminder_stage == "proximo_vencimiento"


def test_idempotent_second_run_sends_nothing_new(tmp_path):
    path = _write(tmp_path)
    service, _, _ = _service(path)
    service.run(today=TODAY, dry_run=False)

    # Segunda corrida el mismo día: ya no debe reenviar las mismas etapas.
    service2, _, mailer2 = _service(path)
    summary2 = service2.run(today=TODAY, dry_run=False)
    assert all(r.action != "sent" for r in summary2.results)
    assert mailer2.outbox == []


def test_escalation_advances_next_stage(tmp_path):
    path = _write(tmp_path)
    # Enviar hoy (A-3 -> vencido_reciente)
    service, _, _ = _service(path)
    service.run(today=TODAY, dry_run=False)

    # 10 días después A-3 pasa a etapa "vencido" y debe reenviarse.
    later = date(2026, 8, 10)
    service2, _, mailer2 = _service(path)
    summary2 = service2.run(today=later, dry_run=False)
    a3 = next(r for r in summary2.results if r.invoice.invoice_id == "A-3")
    assert a3.action == "sent"
    assert a3.stage_name == "vencido"


def test_filter_only_invoice_ids(tmp_path):
    path = _write(tmp_path)
    service, _, mailer = _service(path)
    summary = service.run(today=TODAY, dry_run=True, only_invoice_ids=["A-2"])
    processed = {r.invoice.invoice_id for r in summary.results}
    assert processed == {"A-2"}
