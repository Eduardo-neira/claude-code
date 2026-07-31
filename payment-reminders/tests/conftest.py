import sys
from pathlib import Path

# Permite importar el paquete sin instalarlo (src layout).
SRC = Path(__file__).resolve().parents[1] / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

TEMPLATES_DIR = Path(__file__).resolve().parents[1] / "templates"
