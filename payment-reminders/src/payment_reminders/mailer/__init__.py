"""Backends de envío de correo (consola para pruebas y SMTP para producción)."""

from .base import MailBackend, Sender
from .console import ConsoleMailBackend

__all__ = ["MailBackend", "Sender", "ConsoleMailBackend", "build_mailer"]


def build_mailer(kind: str, options: dict, sender: "Sender") -> "MailBackend":
    """Fábrica de backends de correo a partir de la configuración."""
    kind = (kind or "console").lower()
    if kind in ("console", "dry", "dryrun", "dry_run"):
        return ConsoleMailBackend(sender=sender)
    if kind in ("smtp", "gmail"):
        from .smtp_backend import SmtpMailBackend

        return SmtpMailBackend(
            sender=sender,
            host=options.get("host", "smtp.gmail.com"),
            port=int(options.get("port", 587)),
            username=options.get("username", sender.email),
            password=options.get("password", ""),
            use_tls=bool(options.get("use_tls", True)),
        )
    raise ValueError(f"Backend de correo desconocido: {kind!r}")
