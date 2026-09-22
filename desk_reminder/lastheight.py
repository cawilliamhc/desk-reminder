"""The last height the desk reported, kept across restarts for display only.

The box is silent unless the desk moves, so after a restart the live height is
unknown. The remembered one is shown with a "~" until the desk confirms it;
the coach never acts on it, because someone may have moved the desk since.
"""

import json

from .schedule import DATA_DIR

LAST_HEIGHT_FILE = DATA_DIR / "last_height.json"


def load(path=LAST_HEIGHT_FILE):
    try:
        return float(json.loads(path.read_text())["height"])
    except (FileNotFoundError, ValueError, KeyError, TypeError):
        return None


def save(height, path=LAST_HEIGHT_FILE):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"height": height}))


def title(live, remembered, standing):
    """Menu-bar text: live height, else remembered height marked "~", else a dash."""
    if live is not None:
        return f"{'🧍' if live >= standing else '↕'} {live:.1f}″"
    if remembered is not None:
        return f"↕ ~{remembered:.1f}″"
    return "↕ —"
