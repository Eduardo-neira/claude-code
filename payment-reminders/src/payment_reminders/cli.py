"""Interfaz de línea de comandos del sistema de recordatorios.

Uso típico:

    # Simulación (no envía nada, no toca la hoja) — comportamiento por defecto
    python -m payment_reminders --config config.yaml

    # Envío real
    python -m payment_reminders --config config.yaml --send

    # Simular con una fecha específica y sólo ciertas facturas
    python -m payment_reminders --config config.yaml --today 2026-07-31 --invoice A-101
"""

from __future__ import annotations

import argparse
import sys
from datetime import date, datetime
from pathlib import Path
from typing import List, Optional

from .config import AppConfig, load_config
from .mailer import build_mailer
from .service import ReminderService, RunSummary
from .spreadsheet import build_backend
from .templating import TemplateRenderer


def _parse_date(text: str) -> date:
    return datetime.strptime(text, "%Y-%m-%d").date()


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="payment_reminders",
        description="Recordatorios automatizados de cuentas por cobrar.",
    )
    p.add_argument(
        "--config",
        default=str(Path(__file__).resolve().parents[2] / "config.yaml"),
        help="Ruta al archivo de configuración YAML.",
    )
    p.add_argument(
        "--send",
        action="store_true",
        help="Envía los correos y actualiza la hoja. Sin esta bandera es simulación.",
    )
    p.add_argument(
        "--today",
        type=_parse_date,
        default=None,
        help="Sobrescribe la fecha de hoy (YYYY-MM-DD), útil para pruebas.",
    )
    p.add_argument(
        "--invoice",
        action="append",
        dest="invoices",
        default=None,
        help="Procesa sólo esta factura (se puede repetir).",
    )
    p.add_argument("--quiet", action="store_true", help="Menos salida en consola.")
    return p


def _build_service(config: AppConfig, quiet: bool) -> ReminderService:
    spreadsheet = build_backend(
        config.spreadsheet_kind, config.spreadsheet_options, config.columns
    )
    mailer = build_mailer(config.mailer_kind, config.mailer_options, config.sender)
    # En dry-run con backend de consola queremos ver los correos; si el usuario
    # pide --quiet, silenciamos ese volcado.
    if hasattr(mailer, "verbose"):
        mailer.verbose = not quiet
    renderer = TemplateRenderer(config.templates_dir, company=config.company)
    return ReminderService(
        spreadsheet=spreadsheet,
        mailer=mailer,
        renderer=renderer,
        stages=config.stages,
        open_statuses=config.open_statuses,
        overdue_status=config.overdue_status,
    )


def print_summary(summary: RunSummary, quiet: bool = False) -> None:
    mode = "ENVÍO REAL" if not summary.dry_run else "SIMULACIÓN (dry-run)"
    print()
    print("=" * 70)
    print(f"Resumen de la corrida — {mode}")
    print("=" * 70)
    counts = summary.counts()
    label = {
        "sent": "Enviados",
        "would_send": "Se enviarían",
        "skipped": "Omitidos",
        "error": "Errores",
    }
    for action, n in sorted(counts.items()):
        print(f"  {label.get(action, action):15} {n}")

    if not quiet:
        for r in summary.sent:
            print(f"  → [{r.stage_name}] {r.invoice.invoice_id} · {r.invoice.client_email} ({r.reason})")
        for r in summary.errors:
            print(f"  ✗ {r.invoice.invoice_id}: {r.error}")

    print("=" * 70)
    if summary.dry_run and summary.sent:
        print("Nada fue enviado. Vuelve a ejecutar con --send para enviar de verdad.")


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)

    try:
        config = load_config(args.config)
    except FileNotFoundError:
        print(f"No se encontró el archivo de configuración: {args.config}", file=sys.stderr)
        return 2

    service = _build_service(config, quiet=args.quiet)
    summary = service.run(
        today=args.today,
        dry_run=not args.send,
        only_invoice_ids=args.invoices,
    )
    print_summary(summary, quiet=args.quiet)

    return 1 if summary.errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
