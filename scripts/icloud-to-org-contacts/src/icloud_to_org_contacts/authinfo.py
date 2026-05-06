"""Read CardDAV credentials from authinfo files."""

from dataclasses import dataclass
from pathlib import Path
import shlex
import subprocess


class CredentialError(RuntimeError):
    """Raised when CardDAV credentials cannot be found."""


@dataclass(frozen=True)
class Credential:
    """Username/password pair from authinfo."""

    login: str
    password: str


def _default_authinfo_paths():
    home = Path.home()
    return [home / ".authinfo.gpg", home / ".authinfo"]


def _read_authinfo_text(paths):
    for path in paths:
        if not path.exists():
            continue
        if path.suffix == ".gpg":
            result = subprocess.run(
                ["gpg", "--quiet", "--batch", "--decrypt", str(path)],
                check=True,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            return result.stdout
        return path.read_text(encoding="utf-8")
    raise CredentialError("No authinfo file found")


def _fields_from_line(line):
    fields = {}
    tokens = shlex.split(line, comments=True)
    i = 0
    while i + 1 < len(tokens):
        key = tokens[i]
        value = tokens[i + 1]
        fields[key] = value
        i += 2
    return fields


def load_authinfo_credential(machine, login=None, *, paths=None):
    """Return a credential matching MACHINE and optional LOGIN."""
    text = _read_authinfo_text(paths or _default_authinfo_paths())
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        fields = _fields_from_line(line)
        if fields.get("machine") != machine:
            continue
        if login and fields.get("login") != login:
            continue
        if fields.get("login") and fields.get("password"):
            return Credential(fields["login"], fields["password"])
    if login:
        raise CredentialError(f"No authinfo credential for {machine} / {login}")
    raise CredentialError(f"No authinfo credential for {machine}")
