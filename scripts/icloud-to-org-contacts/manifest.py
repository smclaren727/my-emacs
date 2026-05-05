"""Persistent state for icloud-to-org-contacts.

A small JSON file in the contacts output directory records what we
emitted on the last run: per-contact content hash, file path, the
keys we wrote into the property drawer, and a global hash of the
output settings.

Lets us:
  - skip contacts whose substance hasn't changed (cheap dirty check)
  - detect deletions (uids in manifest not present in this import)
  - force a full rewrite when output settings change
  - reserve etag/url slots for the future CardDAV cutover
"""

import hashlib
import json
import os
from datetime import datetime, timezone

MANIFEST_FILENAME = ".import-state.json"
MANIFEST_VERSION = 1

# Schema version of the on-disk Org note shape produced by orgnote.py.
# Bump when build_org_note's output format changes (new keys, renamed
# keys, different drawer layout) so existing contacts get rewritten.
OUTPUT_SCHEMA_VERSION = "tier-3.4"

# vCard fields whose values change on every Apple Contacts re-export
# even when nothing of substance changed. Excluded from content hash.
_VOLATILE_FIELDS = {"REV", "PRODID", "PHOTO", "VERSION"}


def manifest_path(output_dir):
    return output_dir / MANIFEST_FILENAME


def load_manifest(output_dir):
    path = manifest_path(output_dir)
    if not path.exists():
        return _empty()
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return _empty()
    if data.get("version") != MANIFEST_VERSION:
        return _empty()
    # Defensive: ensure required keys exist even if the file was hand-edited.
    data.setdefault("contacts", {})
    data.setdefault("output_settings_hash", None)
    data.setdefault("last_run", None)
    return data


def save_manifest(output_dir, manifest):
    """Atomic write: temp file + rename."""
    manifest = dict(manifest)
    manifest["version"] = MANIFEST_VERSION
    manifest["last_run"] = datetime.now(timezone.utc).isoformat()
    path = manifest_path(output_dir)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
    os.replace(tmp, path)


def _empty():
    return {
        "version": MANIFEST_VERSION,
        "last_run": None,
        "output_settings_hash": None,
        "contacts": {},
    }


def content_hash(contact):
    """sha256 over a parsed contact dict, ignoring volatile fields."""
    stable = {k: v for k, v in contact.items() if k not in _VOLATILE_FIELDS}
    canonical = json.dumps(stable, sort_keys=True, default=str)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def output_settings_hash(extra=None):
    """sha256 over the script's behavior settings.

    `extra` is reserved for future user-tunable settings (excluded keys,
    label format toggles, etc.). Today the hash is driven solely by
    OUTPUT_SCHEMA_VERSION — bumping it forces every contact through a
    rewrite on the next run.
    """
    payload = dict(extra or {})
    payload["schema_version"] = OUTPUT_SCHEMA_VERSION
    canonical = json.dumps(payload, sort_keys=True, default=str)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def make_entry(path_relative, chash, *, etag=None, url=None,
               emitted_keys=None, archived=False):
    """Build a manifest entry in the canonical shape."""
    return {
        "path": path_relative,
        "content_hash": chash,
        "etag": etag,
        "url": url,
        "emitted_keys": list(emitted_keys or []),
        "archived": archived,
    }
