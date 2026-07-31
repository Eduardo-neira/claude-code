"""Backends de hoja de cálculo (CSV local y Google Sheets)."""

from .base import ColumnMap, SpreadsheetBackend
from .csv_backend import CsvSpreadsheet

__all__ = ["ColumnMap", "SpreadsheetBackend", "CsvSpreadsheet", "build_backend"]


def build_backend(kind: str, options: dict, columns: "ColumnMap") -> "SpreadsheetBackend":
    """Fábrica de backends a partir de la configuración.

    ``kind`` puede ser ``csv`` o ``google_sheets``. El backend de Google se
    importa de forma perezosa para no exigir sus dependencias en pruebas.
    """
    kind = (kind or "csv").lower()
    if kind == "csv":
        return CsvSpreadsheet(path=options["path"], columns=columns)
    if kind in ("xlsx", "excel"):
        from .xlsx_backend import XlsxSpreadsheet

        return XlsxSpreadsheet(
            path=options["path"],
            columns=columns,
            worksheet=options.get("worksheet"),
            header_row=int(options.get("header_row", 1)),
        )
    if kind in ("google_sheets", "google", "sheets"):
        from .google_sheets import GoogleSheetsSpreadsheet

        return GoogleSheetsSpreadsheet(
            spreadsheet_id=options["spreadsheet_id"],
            worksheet=options.get("worksheet", options.get("sheet_name", "Sheet1")),
            credentials_file=options.get("credentials_file"),
            columns=columns,
        )
    raise ValueError(f"Backend de hoja de cálculo desconocido: {kind!r}")
