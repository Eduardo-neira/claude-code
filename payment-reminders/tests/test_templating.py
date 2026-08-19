from datetime import date
from decimal import Decimal

import pytest

pytest.importorskip("jinja2")  # el motor de plantillas requiere Jinja2

from conftest import TEMPLATES_DIR

from payment_reminders.models import Invoice
from payment_reminders.stages import DEFAULT_STAGES, select_stage
from payment_reminders.templating import TemplateRenderer, format_money


def test_format_money():
    assert format_money(Decimal("12500"), "MXN") == "$12,500.00 MXN"
    assert format_money(Decimal("9200.5"), "USD") == "$9,200.50 USD"


def make_invoice(**kw):
    base = dict(
        invoice_id="A-100",
        client_name="Cliente Demo",
        client_email="demo@cliente.mx",
        amount=Decimal("12500"),
        currency="MXN",
        due_date=date(2026, 7, 28),
        status="pendiente",
        payment_link="https://pago/A-100",
    )
    base.update(kw)
    return Invoice(**base)


def test_render_includes_personalization():
    renderer = TemplateRenderer(TEMPLATES_DIR, company={"name": "Grupo Portátil"})
    inv = make_invoice()
    today = date(2026, 7, 31)
    stage = select_stage(DEFAULT_STAGES, inv.days_overdue(today))
    email = renderer.render(inv, stage, today, inv.days_overdue(today))

    assert "Cliente Demo" in email.text_body
    assert "$12,500.00 MXN" in email.text_body
    assert "A-100" in email.subject
    assert "Grupo Portátil" in email.html_body
    # 3 días de mora
    assert "3" in email.subject


def test_all_default_stages_render():
    renderer = TemplateRenderer(TEMPLATES_DIR, company={"name": "Acme"})
    today = date(2026, 7, 31)
    for days in (-2, 0, 3, 20, 60):
        stage = select_stage(DEFAULT_STAGES, days)
        due = date.fromordinal(today.toordinal() - days)
        inv = make_invoice(due_date=due)
        email = renderer.render(inv, stage, today, days)
        assert email.subject
        assert email.text_body
        assert email.html_body.startswith("<!DOCTYPE html>")
