# Portable Emacs Notes

Notes for a future build session around running the same Emacs setup from an
external drive across macOS, Linux, and Windows.

## Goal

Keep the shared Emacs configuration portable while avoiding cross-machine and
cross-OS corruption from runtime state, caches, and compiled artifacts.

## Recommended Model

Treat the Emacs setup as three layers:

1. Shared source
   `init.el`, `core/`, `modules/`, scripts, notes, templates, and other
   plain-text config/data that should travel with the external drive.
2. Local mutable state
   Per-machine caches, databases, history files, server/auth files, autosaves,
   backups, package build output, and native compilation artifacts.
3. Local platform glue
   OS-specific launchers, helper scripts, binaries, and machine-local overrides.

## What Can Be Shared

- Shared Emacs config source
- Plain-text notes and org files
- Feed definitions and other declarative data
- OS-specific launchers stored in the repo

## What Should Usually Stay Local

Examples from this config:

- `var/eln-cache/`
- `var/server/`
- `recentf`
- `savehist`
- `var/org-id-locations`
- `var/elfeed/db/`
- Possibly `etc/custom.el` if it picks up machine-specific values

These files are not the "real" config. They are machine-shaped state.

## Why Shared State Causes Trouble

- Absolute paths differ across macOS, Linux, and Windows
- Native-compiled files are OS/build specific
- Server/client files depend on local runtime behavior
- Databases and caches can accumulate stale entries from another machine
- FAT-family filesystems are a poor fit for secure/authenticated server state

## exFAT Takeaway

Running the shared config from an exFAT external drive can be fine.

The risky part is storing runtime/server/auth/cache state on that same exFAT
volume. In particular:

- Unix-socket based runtime files are a poor fit for exFAT
- TCP auth/server files should not be trusted on FAT-family filesystems

If portable use becomes a real goal later, keep source on the drive and move
runtime state onto each machine's local native filesystem.

## Future Design Direction

Use the external drive for shared source, but compute a local state directory
per machine at startup.

A good selector is based on:

- `system-type`
- `system-name`

That allows:

- macOS laptop state on the MacBook
- separate Windows state for each Windows machine
- optional Linux-specific state when needed

## Bootstrap Behavior

Emacs can bootstrap local state automatically:

- detect host/OS
- compute a local state root
- create it with `make-directory` if missing
- point caches/server/auth/db files there

This means a newly encountered machine does not have to be pre-registered.

## Cleanup Behavior

Do not auto-delete local state on startup.

Safer approach:

- auto-create missing local state
- never auto-remove it implicitly
- provide an explicit cleanup/reset command later if desired

## Possible Future Layout

Examples only, not implemented:

- macOS: `~/Library/Application Support/Emacs/<host>/`
- Linux: `~/.local/state/emacs/<host>/`
- Windows: `%LOCALAPPDATA%\\Emacs\\<host>\\`

The shared repo could still live on the external drive.

## Windows Notes

- Separate Windows Emacs binaries are fine
- Shared config on the external drive should mostly work
- Runtime/server/auth/caches should still be local on Windows
- NTFS is the preferred filesystem for Windows server/auth runtime files

## Practical Rule Of Thumb

Share source, not state.

If a future cross-machine setup behaves strangely, first suspects are:

- native compilation cache
- server/auth files
- history files
- package-specific note graph caches or databases
- org-id locations
- elfeed database

## Not Planned Yet

This note is for reference only. No automatic per-machine local state split has
been implemented yet.
