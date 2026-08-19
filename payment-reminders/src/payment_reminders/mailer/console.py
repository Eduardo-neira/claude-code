"""Backend de correo que imprime en consola (para dry-run y pruebas).

Guarda además cada correo "enviado" en ``self.outbox`` para poder verificarlo
en pruebas automatizadas.
"""

from __future__ import annotations

from typing import List

from ..models import RenderedEmail
from .base import MailBackend, Sender


class ConsoleMailBackend(MailBackend):
    def __init__(self, sender: Sender, verbose: bool = True):
        super().__init__(sender)
        self.verbose = verbose
        self.outbox: List[RenderedEmail] = []

    def send(self, email: RenderedEmail) -> None:
        self.outbox.append(email)
        if not self.verbose:
            return
        print("-" * 70)
        print(f"De:      {self.sender.from_header}")
        print(f"Para:    {email.to}")
        if self.sender.reply_to:
            print(f"Responder a: {self.sender.reply_to}")
        print(f"Asunto:  {email.subject}")
        print("-" * 70)
        print(email.text_body)
        print("-" * 70)
