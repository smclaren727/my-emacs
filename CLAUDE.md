# CLAUDE.md — Emacs Configuration Context

This file provides context for Claude Code when working on this Emacs
configuration.  Read this before making any changes.

## Project Overview

A modular, flag-driven Emacs configuration built from scratch for
Emacs 29+ with native compilation on macOS.  No frameworks (no Doom,
no Spacemacs).  Every package solves a concrete problem.

## Directory Structure

```
~/.emacs.d/
  early-init.el          — startup perf, UI suppression, GC tuning (runs before init.el)
  init.el                — orchestration only: load-path → flags → packages → loader → core → leader → modules
  emacs-decisions-log.md — log of architectural and package decisions
  CLAUDE.md              — this file
  etc/
    authinfo.example       — tracked mail auth example copied into ~/.authinfo.gpg or ~/.authinfo
    custom.el              — package-generated custom variables (gitignored/runtime)
    mail-accounts.example.el — example override for mu4e/mail account data
    mbsyncrc.example       — tracked local mbsync template with Gmail-safe IMAP defaults
    msmtprc.example        — tracked local msmtp template
  core/
    my-flags.el          — feature flags that toggle modules (provides 'my-flags)
    my-loader.el         — error-resilient module loading macro (provides 'my-loader)
    my-core.el           — production-safe defaults, no-littering, backup/autosave (provides 'my-core)
    my-leader.el         — leader keymap with key-chord double-space and C-c u fallback (provides 'my-leader)
  modules/
    my-os-macos.el       — macOS: modifier keys, exec-path-from-shell, clipboard (provides 'my-os-macos)
    my-os-linux.el       — Linux: clipboard + trash integration (provides 'my-os-linux)
    my-os-windows.el     — Windows: Super modifiers, clipboard, trash (provides 'my-os-windows)
    my-ui.el             — sanityinc tomorrow themes, modeline, fonts (provides 'my-ui)
    my-editing.el        — vertico, orderless, marginalia, consult, embark, corfu, cape, vundo, markdown (provides 'my-editing)
    my-dev.el            — magit, eglot, tree-sitter, flymake, diff-hl, compile (provides 'my-dev)
    my-org-mode.el       — org capture, agenda, refile, org-id, org-modern (provides 'my-org-mode)
    my-shells.el         — project-aware shell management (provides 'my-shells)
    my-feeds.el          — elfeed RSS reader, elfeed-org, article saving (provides 'my-feeds)
    my-nodes.el          — org-node networked notes, backlinks, node search (provides 'my-nodes)
    my-ai.el             — gptel + agent-shell: LLM chat, Claude Code, Codex (provides 'my-ai)
    my-mail.el           — mu4e, mbsync, msmtp, org mail capture (provides 'my-mail)
    my-ops.el            — placeholder, flag disabled (provides 'my-ops)
  scripts/
    bootstrap-mail-config.sh — idempotent local mail bootstrap helper
    mail-auth-value      — authinfo reader for mbsync/msmtp password helpers
```

## Load Order

1. `early-init.el` — GC disabled, file-name-handlers cleared, UI suppressed
2. `init.el` — sets load-path, loads flags, initializes package.el/use-package
3. `my-loader.el` — provides `my-load-module` macro (required, fails hard)
4. `my-core.el` — defaults, no-littering, restores early-init overrides (required, fails hard)
5. `my-leader.el` — leader keymap setup (required, fails hard)
6. Modules — loaded conditionally via flags or platform detection, wrapped in `my-load-module` (fail gracefully)

## Critical Rules

- **Core files fail hard.** `my-flags`, `my-loader`, `my-core`, `my-leader` use bare `require`.  If they break, Emacs should crash loudly.
- **Modules fail gracefully.** Loaded via `my-load-module` which catches errors and logs to `*startup-errors*`.
- **No hardcoded paths.** Notes use `my-notes-directory`.  Everything else derives from `user-emacs-directory`.
- **`provide` must match filename.** `my-core.el` provides `'my-core`.  Always.
- **`use-package-always-ensure` is `t`.**  Don't add redundant `:ensure t` on external packages.  Use `:ensure nil` for built-in packages.

## Coding Conventions

- Lexical binding on every file: `;;; filename.el --- Description -*- lexical-binding: t; -*-`
- `my-` prefix on all symbols (functions, variables, keymaps) to avoid collisions
- `use-package` for all package config with declarative keywords (`:hook`, `:bind`, `:custom`)
- `:custom` for user options, `:config` for post-load logic, `:init` for pre-load setup
- `when` / `unless` over single-branch `if`
- `cl-lib` not deprecated `cl`
- Comments explain *why*, not *what*
- Section headers use `;;; Section name ---` with dashes to column 70

## Keybinding Architecture

- All personal bindings live in `my-leader-map`, accessible via double-space chord or `C-c u`
- Leader sub-prefixes: `b` buffer, `c` compile, `e` emacs/eval, `f` files, `g` git, `n` news/feeds, `o` org, `p` project, `s` shell
- Use `my-leader-define` to add leader bindings
- Mode-local bindings (`:map some-mode-map`) stay in their respective module files
- Don't shadow core Emacs bindings without strong justification
- `which-key-add-keymap-based-replacements` provides descriptions for sub-prefixes

## Package Management

- `package.el` with MELPA and GNU ELPA
- `use-package` (built-in Emacs 29+) for configuration
- No `straight.el`, no `elpaca` (future migration path)
- One package at a time.  Each must solve a concrete problem.

## Platform

- Supported platforms: macOS, Linux, and Windows via OS-specific modules
- `my-os-macos.el`, `my-os-linux.el`, or `my-os-windows.el` is loaded by `system-type` (not a flag)
- Primary daily driver: macOS (Apple Silicon, Homebrew emacs-plus with native-comp)
- Shell: zsh
- Python LSP: `pylsp` via pip3 (`~/Library/Python/3.9/bin/`)
- TypeScript LSP: `typescript-language-server` via npm (`~/.npm-global/bin/`)
- Tools: ripgrep, pandoc, multimarkdown
- Remote/TRAMP host aliases are documented in `etc/ssh-config.example` (copy to `~/.ssh/config` per machine)

## Theme System

- `color-theme-sanityinc-tomorrow` (`sanityinc-tomorrow-night` / `sanityinc-tomorrow-day`)
- On macOS, auto-switches via `ns-system-appearance-change-functions`; on other OSes, uses frame background mode at startup
- `minions` + `moody` for modeline behavior and cleanup

## Notes / Org System (PARA)

- Root: `~/All-The-Things/` (controlled by `my-notes-directory`)
- Structure follows PARA methodology:
  - `00-Capture/` — inbox.org, journal.org, newly captured items awaiting refile
  - `10-Projects/` — one .org file per project (e.g. `refinance-home-mortgage.org`)
  - `20-Areas/` — one .org file per area (e.g. `household.org`, `pc-sarasota.org`)
  - `30-Interests/` — currently `interests.org`
  - `40-Knowledge/` — currently `knowledge.org`
  - `50-Resources/` — bookmarks.org, feeds.org, Saved-Articles/, Contacts/
  - `60-Archive/` — archive.org
- Capture templates: todo (`t`), note (`n`), journal (`j`), project (`p`)
- Project capture creates a new file in `10-Projects/` via `my-org-capture-project-file`
- Journal uses `file+olp+datetree` with `:tree-type day` (Year → Month → Day)
- `org-id` enabled from day one — IDs generated on every capture
- Refile targets: all project files, inbox, areas, interests
- Auto-save after refile via advice on `org-refile`

## Testing Changes

- `M-x eval-buffer` to reload a single file without restarting
- `M-x check-parens` before saving any `.el` file
- `emacs --debug-init` if startup breaks
- `C-x b *startup-errors*` to check for module failures
- `C-x b *Messages*` for startup time and warnings
- Startup target: under 1 second

## Files That Should Not Exist in ~/.emacs.d/

- `~/.emacs` or `~/.emacs.el` — will override `init.el`
- `*~` backup files — should go to `var/backup/`
- `#*#` auto-save files — should go to `var/auto-save/`
- `auto-save-list/` directory — redirected to `var/auto-save/sessions/`
- `eln-cache/` — redirected to `var/eln-cache/`
- `custom-set-variables` in `init.el` — redirected to `etc/custom.el`

## Git Workflow

- Commit after each logical change
- Commit messages: `"module: brief description"` (e.g., `"core: add leader key"`)
- Always `git add -A && git commit -m "..."` then `git push`

## What NOT to Do

- Don't add packages without a concrete problem to solve
- Don't use deprecated APIs or `(require 'cl)`
- Don't load packages in `early-init.el`
- Don't hardcode absolute paths
- Don't create `defcustom` for settings that won't be changed at runtime
- Don't add `(provide 'early-init)` or `(provide 'init)` — loaded by path, not `require`
- Don't over-engineer — if 5 lines solve it, don't build a minor mode
