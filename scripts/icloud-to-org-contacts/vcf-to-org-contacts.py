#!/usr/bin/env python3
"""Compatibility wrapper for the icloud-to-org-contacts CLI."""

import sys
from pathlib import Path


PROJECT_SRC = Path(__file__).resolve().parent / "src"
if str(PROJECT_SRC) not in sys.path:
    sys.path.insert(0, str(PROJECT_SRC))

from icloud_to_org_contacts.cli import main


if __name__ == "__main__":
    main()
