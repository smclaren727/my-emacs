import pytest

from icloud_to_org_contacts.authinfo import (
    CredentialError,
    load_authinfo_credential,
)


def test_load_authinfo_credential_matches_machine_and_login(tmp_path):
    authinfo = tmp_path / ".authinfo"
    authinfo.write_text(
        "\n".join([
            "machine contacts.example login alice@example.com password app-pass",
            "machine contacts.example login bob@example.com password other",
        ]),
        encoding="utf-8",
    )

    credential = load_authinfo_credential(
        "contacts.example",
        "bob@example.com",
        paths=[authinfo],
    )

    assert credential.login == "bob@example.com"
    assert credential.password == "other"


def test_load_authinfo_credential_accepts_quoted_password(tmp_path):
    authinfo = tmp_path / ".authinfo"
    authinfo.write_text(
        'machine contacts.example login alice@example.com password "app pass"\n',
        encoding="utf-8",
    )

    credential = load_authinfo_credential("contacts.example", paths=[authinfo])

    assert credential.login == "alice@example.com"
    assert credential.password == "app pass"


def test_load_authinfo_credential_raises_for_missing_entry(tmp_path):
    authinfo = tmp_path / ".authinfo"
    authinfo.write_text(
        "machine other.example login alice@example.com password app-pass\n",
        encoding="utf-8",
    )

    with pytest.raises(CredentialError):
        load_authinfo_credential("contacts.example", paths=[authinfo])
