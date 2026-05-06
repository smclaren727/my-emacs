"""Archive and resurrection transitions for contact notes.

When a contact disappears from the upstream source, its file is moved
to <output_dir>/Archive/ and gets :STATUS: archived + :ARCHIVED_AT:
properties plus an :archived: filetag. If it reappears later, the
move is reversed and the markers are stripped.

The on-disk filename is preserved across the move so external links
(org-id or path-based) survive when the contact returns.
"""

import re

from .orgnote import unique_filepath

ARCHIVE_DIR_NAME = "Archive"


def archive_dir(output_dir):
    return output_dir / ARCHIVE_DIR_NAME


def _add_archive_properties(content, today):
    if re.search(r"^:STATUS:\s+archived", content, re.MULTILINE):
        return content
    block = f":STATUS:   archived\n:ARCHIVED_AT: {today}\n"
    return content.replace(":END:", block + ":END:", 1)


def _add_archived_filetag(content):
    def repl(match):
        line = match.group(0)
        if ":archived:" in line:
            return line
        return re.sub(r":\s*$", ":archived:", line)
    return re.sub(r"^#\+filetags:.*$", repl, content,
                  count=1, flags=re.MULTILINE)


def _remove_archive_properties(content):
    content = re.sub(r"^:STATUS:\s+archived\s*\n", "", content,
                     flags=re.MULTILINE)
    content = re.sub(r"^:ARCHIVED_AT:\s+\S+.*\n", "", content,
                     flags=re.MULTILINE)
    return content


def _remove_archived_filetag(content):
    def repl(match):
        return match.group(0).replace(":archived:", ":")
    return re.sub(r"^#\+filetags:.*$", repl, content,
                  count=1, flags=re.MULTILINE)


def archive_contact(current_path, output_dir, today):
    """Mark the contact archived and move its file into Archive/.

    Returns the new path inside Archive/.
    """
    archive_root = archive_dir(output_dir)
    archive_root.mkdir(exist_ok=True)

    with open(current_path, "r", encoding="utf-8") as f:
        content = f.read()
    content = _add_archive_properties(content, today)
    content = _add_archived_filetag(content)
    with open(current_path, "w", encoding="utf-8") as f:
        f.write(content)

    new_path = unique_filepath(archive_root, current_path.stem)
    current_path.rename(new_path)
    return new_path


def resurrect_contact(current_path, output_dir):
    """Strip archive markers and move the file back to output_dir root.

    Returns the new path at the root. Caller is responsible for any
    subsequent rename-to-match-FN if the contact's name changed while
    it was archived.
    """
    with open(current_path, "r", encoding="utf-8") as f:
        content = f.read()
    content = _remove_archive_properties(content)
    content = _remove_archived_filetag(content)
    with open(current_path, "w", encoding="utf-8") as f:
        f.write(content)

    new_path = unique_filepath(output_dir, current_path.stem)
    current_path.rename(new_path)
    return new_path
