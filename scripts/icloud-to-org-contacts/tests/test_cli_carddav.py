from uuid import UUID

from icloud_to_org_contacts import cli
from icloud_to_org_contacts.carddav import DAVCard
from icloud_to_org_contacts.manifest import load_manifest


def assert_org_id_property(note):
    for line in note.splitlines():
        if line.startswith(":ID: "):
            UUID(line.removeprefix(":ID: ").strip())
            return
    raise AssertionError("Org ID property missing")


class FakeCardDAVClient:
    cards = []
    calls = []

    def __init__(self, server_url, username, password):
        self.server_url = server_url
        self.username = username
        self.password = password

    def fetch_vcards(self, addressbook_url=None):
        self.calls.append(
            {
                "server_url": self.server_url,
                "username": self.username,
                "password": self.password,
                "addressbook_url": addressbook_url,
            }
        )
        return list(self.cards)


def test_sync_carddav_writes_vcard_url_etag_and_properties(monkeypatch, tmp_path):
    FakeCardDAVClient.cards = [
        DAVCard(
            url="https://contacts.example/card/alice.vcf",
            etag='"etag-1"',
            data="\n".join([
                "BEGIN:VCARD",
                "VERSION:3.0",
                "UID:alice",
                "FN:Alice Carddav",
                "EMAIL;TYPE=WORK:alice@example.com",
                "END:VCARD",
            ]),
        ),
        DAVCard(
            url="https://contacts.example/card/group.vcf",
            etag='"etag-g"',
            data="\n".join([
                "BEGIN:VCARD",
                "VERSION:3.0",
                "UID:group-1",
                "FN:Team",
                "X-ADDRESSBOOKSERVER-KIND:group",
                "X-ADDRESSBOOKSERVER-MEMBER:urn:uuid:alice",
                "END:VCARD",
            ]),
        ),
    ]
    FakeCardDAVClient.calls = []
    monkeypatch.setattr(cli, "CardDAVClient", FakeCardDAVClient)

    cli.main([
        "sync-carddav",
        "-o",
        str(tmp_path),
        "--server-url",
        "https://contacts.example",
        "--username",
        "alice@example.com",
        "--password",
        "app-pass",
    ])

    note = (tmp_path / "alice-carddav.org").read_text(encoding="utf-8")
    assert_org_id_property(note)
    assert ":VCARD_UID: alice\n" in note
    assert ":VCARD_URL: https://contacts.example/card/alice.vcf\n" in note
    assert ":EMAIL_WORK: alice@example.com\n" in note
    assert "#+filetags: :contact:team:\n" in note
    manifest = load_manifest(tmp_path)
    entry = manifest["contacts"]["alice"]
    assert entry["etag"] == '"etag-1"'
    assert entry["url"] == "https://contacts.example/card/alice.vcf"
    assert entry["emitted_keys"][0] == "ID"
    assert entry["emitted_tags"] == ["team"]
    assert FakeCardDAVClient.calls[0]["username"] == "alice@example.com"
    assert FakeCardDAVClient.calls[0]["password"] == "app-pass"


def test_sync_carddav_can_filter_to_selected_group(monkeypatch, tmp_path):
    FakeCardDAVClient.cards = [
        DAVCard(
            url="https://contacts.example/card/a.vcf",
            etag='"a"',
            data="BEGIN:VCARD\nVERSION:3.0\nUID:a\nFN:A Person\nEND:VCARD",
        ),
        DAVCard(
            url="https://contacts.example/card/b.vcf",
            etag='"b"',
            data="BEGIN:VCARD\nVERSION:3.0\nUID:b\nFN:B Person\nEND:VCARD",
        ),
        DAVCard(
            url="https://contacts.example/card/group.vcf",
            etag='"g"',
            data="\n".join([
                "BEGIN:VCARD",
                "VERSION:3.0",
                "UID:group-1",
                "FN:Selected",
                "X-ADDRESSBOOKSERVER-KIND:group",
                "X-ADDRESSBOOKSERVER-MEMBER:urn:uuid:b",
                "END:VCARD",
            ]),
        ),
    ]
    monkeypatch.setattr(cli, "CardDAVClient", FakeCardDAVClient)

    cli.main([
        "sync-carddav",
        "-o",
        str(tmp_path),
        "--username",
        "u",
        "--password",
        "p",
        "--group",
        "Selected",
    ])

    assert not (tmp_path / "a-person.org").exists()
    assert (tmp_path / "b-person.org").exists()


def test_sync_carddav_skips_when_etag_and_url_match(monkeypatch, tmp_path, capsys):
    FakeCardDAVClient.cards = [
        DAVCard(
            url="https://contacts.example/card/alice.vcf",
            etag='"etag-1"',
            data="BEGIN:VCARD\nVERSION:3.0\nUID:alice\nFN:Alice\nEND:VCARD",
        )
    ]
    monkeypatch.setattr(cli, "CardDAVClient", FakeCardDAVClient)
    args = [
        "sync-carddav",
        "-o",
        str(tmp_path),
        "--username",
        "u",
        "--password",
        "p",
    ]

    cli.main(args)
    cli.main(args)

    assert "0 created, 0 updated, 1 unchanged" in capsys.readouterr().out


def test_list_groups_prints_uid_name_and_member_count(monkeypatch, capsys):
    FakeCardDAVClient.cards = [
        DAVCard(
            url="https://contacts.example/card/group.vcf",
            etag='"g"',
            data="\n".join([
                "BEGIN:VCARD",
                "VERSION:3.0",
                "UID:group-1",
                "FN:Friends",
                "X-ADDRESSBOOKSERVER-KIND:group",
                "X-ADDRESSBOOKSERVER-MEMBER:urn:uuid:a",
                "X-ADDRESSBOOKSERVER-MEMBER:urn:uuid:b",
                "END:VCARD",
            ]),
        )
    ]
    monkeypatch.setattr(cli, "CardDAVClient", FakeCardDAVClient)

    cli.main([
        "list-groups",
        "--username",
        "u",
        "--password",
        "p",
    ])

    assert capsys.readouterr().out == "group-1\tFriends\t2\n"
