"""Etapas de escalamiento del recordatorio según la antigüedad de la deuda."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, List, Optional


@dataclass(frozen=True)
class Stage:
    """Una etapa del ciclo de cobranza.

    Los rangos se expresan en días relativos al vencimiento:
      - negativo  → aún no vence (recordatorio preventivo)
      - 0         → vence hoy
      - positivo  → días de mora

    ``days_to = None`` significa "sin límite superior" (etapa final).
    """

    name: str
    days_from: int
    days_to: Optional[int]
    subject: str
    template: str

    def matches(self, days_overdue: int) -> bool:
        if days_overdue < self.days_from:
            return False
        if self.days_to is not None and days_overdue > self.days_to:
            return False
        return True

    def describe(self) -> str:
        upper = "∞" if self.days_to is None else str(self.days_to)
        return f"{self.name} [{self.days_from}..{upper} días]"


def select_stage(stages: Iterable[Stage], days_overdue: int) -> Optional[Stage]:
    """Devuelve la etapa aplicable más avanzada (mayor ``days_from``).

    Si varias etapas coinciden (rangos traslapados por configuración), se
    prefiere la más severa para no "regresar" en el escalamiento.
    """
    matching: List[Stage] = [s for s in stages if s.matches(days_overdue)]
    if not matching:
        return None
    return max(matching, key=lambda s: s.days_from)


# Configuración de etapas por defecto (cobranza estándar B2B en México).
DEFAULT_STAGES: List[Stage] = [
    Stage(
        name="proximo_vencimiento",
        days_from=-3,
        days_to=-1,
        subject="Recordatorio: tu factura {{ invoice.invoice_id }} vence pronto",
        template="proximo_vencimiento",
    ),
    Stage(
        name="vence_hoy",
        days_from=0,
        days_to=0,
        subject="Tu factura {{ invoice.invoice_id }} vence hoy",
        template="vence_hoy",
    ),
    Stage(
        name="vencido_reciente",
        days_from=1,
        days_to=7,
        subject="Factura {{ invoice.invoice_id }} vencida — {{ days_overdue }} día(s)",
        template="vencido_reciente",
    ),
    Stage(
        name="vencido",
        days_from=8,
        days_to=30,
        subject="Segundo aviso: factura {{ invoice.invoice_id }} con {{ days_overdue }} días de mora",
        template="vencido",
    ),
    Stage(
        name="aviso_final",
        days_from=31,
        days_to=None,
        subject="AVISO FINAL: factura {{ invoice.invoice_id }} vencida hace {{ days_overdue }} días",
        template="aviso_final",
    ),
]
