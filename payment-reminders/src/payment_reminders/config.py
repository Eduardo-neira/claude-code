"""Carga de configuración desde YAML con interpolación de variables de entorno.

Los secretos (contraseñas, IDs) no se escriben en el YAML: se referencian con
``${NOMBRE_VARIABLE}`` y se resuelven desde el entorno (o un archivo .env si
está disponible ``python-dotenv``).
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

from .mailer.base import Sender
from .spreadsheet.base import ColumnMap
from .stages import DEFAULT_STAGES, Stage

_ENV_PATTERN = re.compile(r"\$\{([A-Z0-9_]+)\}")


def _interpolate(value: Any) -> Any:
    """Reemplaza ``${VAR}`` por el valor de entorno en strings (recursivo)."""
    if isinstance(value, str):
        def repl(match: re.Match) -> str:
            return os.environ.get(match.group(1), "")

        return _ENV_PATTERN.sub(repl, value)
    if isinstance(value, dict):
        return {k: _interpolate(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_interpolate(v) for v in value]
    return value


@dataclass
class AppConfig:
    templates_dir: Path
    company: Dict[str, Any]
    sender: Sender
    spreadsheet_kind: str
    spreadsheet_options: Dict[str, Any]
    mailer_kind: str
    mailer_options: Dict[str, Any]
    columns: ColumnMap
    stages: List[Stage]
    open_statuses: List[str]
    overdue_status: str = "vencida"


def _load_dotenv(config_dir: Path) -> None:
    env_path = config_dir / ".env"
    if not env_path.exists():
        return
    try:
        from dotenv import load_dotenv

        load_dotenv(env_path)
    except ImportError:
        # Parser mínimo si python-dotenv no está instalado.
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            os.environ.setdefault(key.strip(), val.strip().strip('"').strip("'"))


def load_config(path: str | Path) -> AppConfig:
    path = Path(path)
    _load_dotenv(path.parent)

    raw = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    raw = _interpolate(raw)

    company = raw.get("company", {})

    sender_cfg = raw.get("sender", {})
    sender = Sender(
        name=sender_cfg.get("name", company.get("name", "")),
        email=sender_cfg.get("email", ""),
        reply_to=sender_cfg.get("reply_to") or None,
        bcc=sender_cfg.get("bcc") or None,
    )

    sheet_cfg = raw.get("spreadsheet", {})
    mailer_cfg = raw.get("mailer", {})

    columns = ColumnMap(**(raw.get("columns") or {}))

    stages_cfg = raw.get("stages")
    if stages_cfg:
        stages = [
            Stage(
                name=s["name"],
                days_from=int(s["days_from"]),
                days_to=None if s.get("days_to") in (None, "", "inf") else int(s["days_to"]),
                subject=s["subject"],
                template=s["template"],
            )
            for s in stages_cfg
        ]
    else:
        stages = list(DEFAULT_STAGES)

    templates_dir = Path(raw.get("templates_dir") or (path.parent / "templates"))
    if not templates_dir.is_absolute():
        templates_dir = (path.parent / templates_dir).resolve()

    open_statuses = raw.get("open_statuses") or list(_default_open())

    return AppConfig(
        templates_dir=templates_dir,
        company=company,
        sender=sender,
        spreadsheet_kind=sheet_cfg.get("kind", "csv"),
        spreadsheet_options=sheet_cfg.get("options", {}),
        mailer_kind=mailer_cfg.get("kind", "console"),
        mailer_options=mailer_cfg.get("options", {}),
        columns=columns,
        stages=stages,
        open_statuses=open_statuses,
        overdue_status=raw.get("overdue_status", "vencida"),
    )


def _default_open():
    from .models import DEFAULT_OPEN_STATUSES

    return DEFAULT_OPEN_STATUSES
