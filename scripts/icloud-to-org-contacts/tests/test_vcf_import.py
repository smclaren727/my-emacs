from manifest import load_manifest

from conftest import run_cli, write_vcf


def test_vcf_import_emits_org_property_drawer(tmp_path):
    vcf = write_vcf(
        tmp_path / "contacts.vcf",
        "BEGIN:VCARD",
        "VERSION:3.0",
        "UID:person-1",
        "FN:Alice Smith",
        "NICKNAME:Al",
        "EMAIL;TYPE=WORK:alice@example.com",
        "TEL;TYPE=CELL:+15550001",
        "ORG:Acme Corp;Platform",
        "TITLE:Engineer",
        "item1.ADR;TYPE=HOME:;;100 Main St;Springfield;IL;62701;USA",
        "item1.X-ABLABEL:_$!<Home>!$_",
        "URL;TYPE=HOME:https://alice.example.com",
        "BDAY:1985-04-12",
        r"NOTE:Line one\nLine two",
        "END:VCARD",
    )
    output_dir = tmp_path / "out"

    result = run_cli(vcf, "-o", output_dir)

    assert "Done: 1 created" in result.stdout
    note = (output_dir / "alice-smith.org").read_text(encoding="utf-8")
    assert note.startswith(":PROPERTIES:\n")
    assert ":VCARD_UID: person-1\n" in note
    assert ":NICKNAME: Al\n" in note
    assert ":EMAIL_WORK: alice@example.com\n" in note
    assert ":PHONE_CELL: +15550001\n" in note
    assert ":COMPANY: Acme Corp\n" in note
    assert ":ROLE: Engineer\n" in note
    assert ":ADDRESS_HOME: 100 Main St, Springfield, IL, 62701, USA\n" in note
    assert ":URL_HOME: https://alice.example.com\n" in note
    assert ":BIRTHDAY: 1985-04-12\n" in note
    assert ":NOTE: Line one / Line two\n" in note
    assert "#+title: Alice Smith\n" in note
    assert "#+filetags: :contact:\n" in note
    assert "#+begin_src" not in note
    assert "Line one\nLine two" in note


def test_reimport_preserves_user_drawer_keys_and_body(tmp_path):
    vcf = tmp_path / "contacts.vcf"
    output_dir = tmp_path / "out"
    write_vcf(
        vcf,
        "BEGIN:VCARD",
        "VERSION:3.0",
        "UID:person-2",
        "FN:Bob Stone",
        "EMAIL;TYPE=WORK:bob@example.com",
        "END:VCARD",
    )
    run_cli(vcf, "-o", output_dir)

    note_path = output_dir / "bob-stone.org"
    original = note_path.read_text(encoding="utf-8")
    edited = original.replace(":END:\n", ":USER_KEY: keep me\n:END:\n", 1)
    edited = edited.rsplit("\n", 1)[0] + "\nUser-owned body.\n"
    note_path.write_text(edited, encoding="utf-8")

    write_vcf(
        vcf,
        "BEGIN:VCARD",
        "VERSION:3.0",
        "UID:person-2",
        "FN:Bob Stone",
        "EMAIL;TYPE=WORK:robert@example.com",
        "END:VCARD",
    )
    run_cli(vcf, "-o", output_dir)

    note = note_path.read_text(encoding="utf-8")
    assert ":EMAIL_WORK: robert@example.com\n" in note
    assert ":EMAIL_WORK: bob@example.com\n" not in note
    assert ":USER_KEY: keep me\n" in note
    assert note.endswith("User-owned body.\n")


def test_group_cards_emit_filetags_and_manifest(tmp_path):
    vcf = write_vcf(
        tmp_path / "contacts.vcf",
        "BEGIN:VCARD",
        "VERSION:3.0",
        "UID:person-3",
        "FN:Carol Team",
        "EMAIL;TYPE=HOME:carol@example.com",
        "END:VCARD",
        "BEGIN:VCARD",
        "VERSION:3.0",
        "UID:group-1",
        "FN:Friends & Family",
        "X-ADDRESSBOOKSERVER-KIND:group",
        "X-ADDRESSBOOKSERVER-MEMBER:urn:uuid:person-3",
        "END:VCARD",
    )
    output_dir = tmp_path / "out"

    run_cli(vcf, "-o", output_dir)

    note = (output_dir / "carol-team.org").read_text(encoding="utf-8")
    assert "#+filetags: :contact:friends-family:\n" in note
    manifest = load_manifest(output_dir)
    assert manifest["contacts"]["person-3"]["path"] == "carol-team.org"
    assert manifest["contacts"]["person-3"]["emitted_keys"] == [
        "ID",
        "VCARD_UID",
        "EMAIL_HOME",
    ]
