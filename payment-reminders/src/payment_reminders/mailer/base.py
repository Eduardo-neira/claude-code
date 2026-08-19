"""Interfaz común de los backends de correo."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import List, Optional

from ..models import RenderedEmail


@dataclass
class Sender:
    """Identidad del remitente usada en los correos."""

    name: str
    email: str
    reply_to: Optional[str] = None
    bcc: Optional[List[str]] = None  # copia oculta (p.ej. cobranza@empresa.com)

    @property
    def from_header(self) -> str:
        return f"{self.name} <{self.email}>" if self.name else self.email


class MailBackend(ABC):
    """Contrato de envío de un correo ya renderizado."""

    def __init__(self, sender: Sender):
        self.sender = sender

    @abstractmethod
    def send(self, email: RenderedEmail) -> None:
        """Envía (o simula) un correo. Debe lanzar excepción si falla."""

    def close(self) -> None:
        """Libera recursos (conexiones). Por defecto no hace nada."""
