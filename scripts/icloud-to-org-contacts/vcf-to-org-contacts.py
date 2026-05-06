#!/usr/bin/env python3
"""Compatibility wrapper for the icloud-to-org-contacts CLI."""

import sys
from pathlib import Path


PROJECT_SRC = Path(__file__).resolve().parent / "src"
if str(PROJECT_SRC) not in sys.path:
    sys.path.insert(0, str(PROJECT_SRC))

try:
    from icloud_to_org_contacts.cli import main
except ModuleNotFoundError as exc:
    print(
        "Missing dependency for icloud-to-org-contacts. "
        "Run `python3 -m pip install -e .` from this directory.",
        file=sys.stderr,
    )
    raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
