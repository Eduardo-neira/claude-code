"""Orquestación: decide qué facturas recordar, envía y actualiza la hoja."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from typing import List, Optional, Sequence

from .mailer.base import MailBackend
from .models import DEFAULT_OPEN_STATUSES, Invoice, ReminderResult
from .spreadsheet.base import SpreadsheetBackend
from .stages import Stage, select_stage
from .templating import TemplateRenderer


@dataclass
class RunSummary:
    """Resumen agregado de una corrida."""

    results: List[ReminderResult] = field(default_factory=list)
    dry_run: bool = True

    @property
    def sent(self) -> List[ReminderResult]:
        return [r for r in self.results if r.action in ("sent", "would_send")]

    @property
    def errors(self) -> List[ReminderResult]:
        return [r for r in self.results if r.action == "error"]

    @property
    def skipped(self) -> List[ReminderResult]:
        return [r for r in self.results if r.action == "skipped"]

    def counts(self) -> dict:
        by_action: dict = {}
        for r in self.results:
            by_action[r.action] = by_action.get(r.action, 0) + 1
        return by_action


class ReminderService:
    """Coordina hoja de cálculo, plantillas y correo.

    Reglas de negocio:
      * Sólo se consideran facturas con estatus "abierto".
      * Se calcula la etapa de escalamiento según los días de mora.
      * Se envía **un** recordatorio por factura por corrida, y sólo si la
        etapa actual es distinta a la del último recordatorio registrado
        (evita duplicados y respeta el escalamiento).
      * En ``dry_run`` no se envía correo ni se escribe la hoja.
    """

    def __init__(
        self,
        spreadsheet: SpreadsheetBackend,
        mailer: MailBackend,
        renderer: TemplateRenderer,
        stages: Sequence[Stage],
        open_statuses: Sequence[str] = DEFAULT_OPEN_STATUSES,
        overdue_status: str = "vencida",
    ):
        self.spreadsheet = spreadsheet
        self.mailer = mailer
        self.renderer = renderer
        self.stages = list(stages)
        self.open_statuses = list(open_statuses)
        # Estatus con el que se marca la factura cuando ya venció.
        self.overdue_status = overdue_status

    def run(
        self,
        today: Optional[date] = None,
        dry_run: bool = True,
        only_invoice_ids: Optional[Sequence[str]] = None,
    ) -> RunSummary:
        today = today or date.today()
        summary = RunSummary(dry_run=dry_run)

        invoices = self.spreadsheet.read_invoices()
        wanted = set(only_invoice_ids) if only_invoice_ids else None

        for invoice in invoices:
            if wanted is not None and invoice.invoice_id not in wanted:
                continue
            result = self._process(invoice, today, dry_run)
            summary.results.append(result)

        # Persistir cambios sólo si de verdad enviamos algo.
        if not dry_run and any(r.action == "sent" for r in summary.results):
            self.spreadsheet.commit()

        self.mailer.close()
        return summary

    # -- por factura -----------------------------------------------------
    def _process(self, invoice: Invoice, today: date, dry_run: bool) -> ReminderResult:
        if not invoice.is_open(self.open_statuses):
            return ReminderResult(invoice, "skipped", reason="factura cerrada/pagada")

        days = invoice.days_overdue(today)
        if days is None:
            return ReminderResult(invoice, "skipped", reason="sin fecha de vencimiento")

        stage = select_stage(self.stages, days)
        if stage is None:
            return ReminderResult(
                invoice, "skipped", reason=f"ninguna etapa aplica ({days} días)"
            )

        if invoice.last_reminder_stage == stage.name:
            return ReminderResult(
                invoice,
                "skipped",
                stage_name=stage.name,
                reason="recordatorio de esta etapa ya enviado",
            )

        if not invoice.has_valid_email():
            return ReminderResult(
                invoice, "skipped", stage_name=stage.name, reason="correo inválido o vacío"
            )

        try:
            email = self.renderer.render(invoice, stage, today, days)
        except Exception as exc:  # noqa: BLE001 - plantilla/entrada externa
            return ReminderResult(
                invoice, "error", stage_name=stage.name, error=f"render: {exc}"
            )

        if dry_run:
            return ReminderResult(
                invoice, "would_send", stage_name=stage.name, email=email,
                reason=f"{days} días de mora",
            )

        try:
            self.mailer.send(email)
        except Exception as exc:  # noqa: BLE001 - errores de red/SMTP
            return ReminderResult(
                invoice, "error", stage_name=stage.name, email=email, error=f"envio: {exc}"
            )

        # Marcar la factura como vencida si aplica y registrar el recordatorio.
        new_status = self.overdue_status if days > 0 else invoice.status
        self.spreadsheet.stage_update(
            invoice,
            status=new_status,
            last_reminder_stage=stage.name,
            last_reminder_date=today,
        )
        return ReminderResult(
            invoice, "sent", stage_name=stage.name, email=email,
            reason=f"{days} días de mora",
        )
