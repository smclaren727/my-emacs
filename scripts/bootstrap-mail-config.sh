#!/usr/bin/env bash

set -euo pipefail

emacs_dir="${EMACS_DIR:-$HOME/.emacs.d}"
etc_dir="$emacs_dir/etc"
scripts_dir="$emacs_dir/scripts"
mail_root="${MAIL_ROOT:-$HOME/Mail}"
bin_dir="${BIN_DIR:-$HOME/bin}"

install_copy_if_missing() {
  local src="$1"
  local dest="$2"
  local mode="$3"

  if [[ -e "$dest" ]]; then
    printf 'Keeping existing %s\n' "$dest"
    return
  fi

  cp "$src" "$dest"
  chmod "$mode" "$dest"
  printf 'Created %s from %s\n' "$dest" "$src"
}

ensure_symlink() {
  local src="$1"
  local dest="$2"

  if [[ -L "$dest" ]]; then
    local target
    target="$(readlink "$dest")"
    if [[ "$target" == "$src" ]]; then
      printf 'Keeping existing symlink %s -> %s\n' "$dest" "$src"
      return
    fi
  fi

  if [[ -e "$dest" ]]; then
    printf 'Skipping %s because it already exists and is not the managed symlink\n' "$dest"
    return
  fi

  ln -s "$src" "$dest"
  printf 'Created symlink %s -> %s\n' "$dest" "$src"
}

if [[ ! -d "$etc_dir" ]]; then
  printf 'Expected template directory %s was not found.\n' "$etc_dir" >&2
  exit 1
fi

mkdir -p "$mail_root/gmail" "$mail_root/icloud" "$bin_dir"

install_copy_if_missing "$etc_dir/mbsyncrc.example" "$HOME/.mbsyncrc" 600
install_copy_if_missing "$etc_dir/msmtprc.example" "$HOME/.msmtprc" 600
install_copy_if_missing "$etc_dir/authinfo.example" "$HOME/.authinfo.example" 600
ensure_symlink "$scripts_dir/mail-auth-value" "$bin_dir/mail-auth-value"
ensure_symlink "$scripts_dir/mail-sync" "$bin_dir/mail-sync"

if command -v mu >/dev/null 2>&1; then
  if ! mu info >/dev/null 2>&1; then
    mu init \
      --maildir="$mail_root" \
      --my-address=smclaren727@gmail.com \
      --my-address=smclaren727@icloud.com
    printf 'Initialized mu database for %s\n' "$mail_root"
  else
    printf 'Keeping existing mu database\n'
  fi
else
  printf 'mu not found on PATH; skipping mu init\n'
fi

cat <<'EOF'

Next steps:
1. Use app passwords for Gmail and iCloud, with no spaces in the saved value.
2. For launchd background syncs on macOS, prefer Keychain:
   security add-generic-password -U -s mail-auth:imap.gmail.com -a smclaren727@gmail.com -w APP_PASSWORD
   security add-generic-password -U -s mail-auth:smtp.gmail.com -a smclaren727@gmail.com -w APP_PASSWORD
3. ~/.authinfo.gpg and ~/.authinfo from ~/.authinfo.example remain supported fallbacks.
4. The managed mail-sync script syncs the gmail channel by default.
5. Run `mbsync gmail && mu index` to finish the first Gmail sync.
6. Once Gmail is healthy, come back for iCloud if you still want it.
EOF
