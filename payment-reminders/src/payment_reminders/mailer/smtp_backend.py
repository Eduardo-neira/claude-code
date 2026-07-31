"""Backend de correo por SMTP (compatible con Gmail, Outlook, etc.).

Para Gmail usa una **contraseña de aplicación** (App Password), no la
contraseña normal de la cuenta, y mantén activada la verificación en dos pasos.
Host por defecto: ``smtp.gmail.com:587`` con STARTTLS.
"""

from __future__ import annotations

import smtplib
import ssl
from email.message import EmailMessage
from email.utils import formataddr

from ..models import RenderedEmail
from .base import MailBackend, Sender


class SmtpMailBackend(MailBackend):
    def __init__(
        self,
        sender: Sender,
        host: str = "smtp.gmail.com",
        port: int = 587,
        username: str = "",
        password: str = "",
        use_tls: bool = True,
    ):
        super().__init__(sender)
        self.host = host
        self.port = port
        self.username = username or sender.email
        self.password = password
        self.use_tls = use_tls
        self._conn: smtplib.SMTP | None = None

    def _connect(self) -> smtplib.SMTP:
        if self._conn is not None:
            return self._conn
        context = ssl.create_default_context()
        if self.use_tls:
            conn = smtplib.SMTP(self.host, self.port, timeout=30)
            conn.ehlo()
            conn.starttls(context=context)
            conn.ehlo()
        else:
            conn = smtplib.SMTP_SSL(self.host, self.port, context=context, timeout=30)
        if self.password:
            conn.login(self.username, self.password)
        self._conn = conn
        return conn

    def _build_message(self, email: RenderedEmail) -> EmailMessage:
        msg = EmailMessage()
        msg["From"] = formataddr((self.sender.name, self.sender.email))
        msg["To"] = email.to
        msg["Subject"] = email.subject
        if self.sender.reply_to:
            msg["Reply-To"] = self.sender.reply_to
        if self.sender.bcc:
            msg["Bcc"] = ", ".join(self.sender.bcc)
        msg.set_content(email.text_body)
        msg.add_alternative(email.html_body, subtype="html")
        return msg

    def send(self, email: RenderedEmail) -> None:
        conn = self._connect()
        conn.send_message(self._build_message(email))

    def close(self) -> None:
        if self._conn is not None:
            try:
                self._conn.quit()
            finally:
                self._conn = None
