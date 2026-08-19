"""Renderizado de correos con plantillas Jinja2 (asunto + texto + HTML)."""

from __future__ import annotations

from datetime import date
from decimal import Decimal
from pathlib import Path
from typing import Any, Dict, Optional

from jinja2 import Environment, FileSystemLoader, StrictUndefined, select_autoescape

from .models import Invoice, RenderedEmail
from .stages import Stage


def format_money(amount: Decimal, currency: str = "MXN") -> str:
    """Formatea un monto con separador de miles y 2 decimales: ``$12,500.00 MXN``."""
    try:
        value = Decimal(amount)
    except Exception:  # noqa: BLE001 - entrada externa poco confiable
        value = Decimal("0")
    return f"${value:,.2f} {currency}".strip()


def format_date_es(value: Optional[date]) -> str:
    """Fecha en formato ``dd/mm/aaaa`` (vacío si es None)."""
    if value is None:
        return ""
    return value.strftime("%d/%m/%Y")


class TemplateRenderer:
    """Envuelve un entorno Jinja2 apuntando a la carpeta de plantillas.

    Para cada etapa se esperan dos archivos::

        <template>.txt.j2    (versión de texto plano — obligatoria)
        <template>.html.j2   (versión HTML — opcional, se genera desde texto)
    """

    # Claves opcionales de ``company`` que las plantillas pueden referenciar.
    # Se rellenan con "" para poder usar StrictUndefined sin romper el render
    # cuando la empresa no configura alguna de ellas.
    _OPTIONAL_COMPANY_KEYS = (
        "name",
        "signature",
        "phone",
        "collections_email",
        "payment_instructions",
    )

    def __init__(self, templates_dir: Path, company: Optional[Dict[str, Any]] = None):
        self.templates_dir = Path(templates_dir)
        self.company = dict(company or {})
        for key in self._OPTIONAL_COMPANY_KEYS:
            self.company.setdefault(key, "")
        self.env = Environment(
            loader=FileSystemLoader(str(self.templates_dir)),
            autoescape=select_autoescape(["html", "xml", "html.j2"]),
            undefined=StrictUndefined,
            trim_blocks=True,
            lstrip_blocks=True,
        )
        self.env.filters["money"] = format_money
        self.env.filters["fecha"] = format_date_es

    def _context(
        self, invoice: Invoice, stage: Stage, today: date, days_overdue: int
    ) -> Dict[str, Any]:
        return {
            "invoice": invoice,
            "stage": stage,
            "today": today,
            "days_overdue": days_overdue,
            "days_until_due": -days_overdue,
            "amount_display": format_money(invoice.amount, invoice.currency),
            "due_date_display": format_date_es(invoice.due_date),
            "company": self.company,
        }

    def render(
        self, invoice: Invoice, stage: Stage, today: date, days_overdue: int
    ) -> RenderedEmail:
        ctx = self._context(invoice, stage, today, days_overdue)

        subject = self.env.from_string(stage.subject).render(**ctx).strip()

        text_body = self.env.get_template(f"{stage.template}.txt.j2").render(**ctx).strip()

        html_name = f"{stage.template}.html.j2"
        if (self.templates_dir / html_name).exists():
            html_body = self.env.get_template(html_name).render(**ctx).strip()
        else:
            html_body = _text_to_html(text_body)

        return RenderedEmail(
            to=invoice.client_email,
            subject=subject,
            text_body=text_body,
            html_body=html_body,
        )


def _text_to_html(text: str) -> str:
    """Fallback simple: convierte texto plano en HTML con saltos de línea."""
    from html import escape

    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    body = "\n".join(
        "<p>" + escape(p).replace("\n", "<br>\n") + "</p>" for p in paragraphs
    )
    return f'<div style="font-family: Arial, sans-serif; font-size: 14px; color: #222;">\n{body}\n</div>'
