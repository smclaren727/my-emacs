# AGENTS.md — Emacs Configuration Context

Maintenance note: update this `AGENTS.md` file only. `CLAUDE.md` is
intentionally a one-line `@AGENTS.md` pointer and should stay that way.

This file provides context for coding agents when working on this Emacs
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
  Makefile               — `make test` runs the ERT suite in batch mode
  emacs-decisions-log.md — log of architectural and package decisions
  AGENTS.md              — canonical agent instructions for this repo
  CLAUDE.md              — one-line @AGENTS.md pointer
  etc/
    authinfo.example       — tracked mail auth example copied into ~/.authinfo.gpg or ~/.authinfo
    com.seanmclaren.mail-sync.plist — launchd template for out-of-Emacs mail sync
    custom.el              — package-generated custom variables (gitignored/runtime)
    mail-accounts.example.el — example override for mu4e/mail account data
    mbsyncrc.example       — tracked local mbsync template with Gmail-safe IMAP defaults
    msmtprc.example        — tracked local msmtp template
    mu4e-dashboard.org     — org source for the mu4e dashboard/sidebar
    ssh-config.example     — TRAMP/Nix host alias examples
  core/
    my-flags.el          — feature flags that toggle modules (provides 'my-flags)
    my-loader.el         — error-resilient module loading macro (provides 'my-loader)
    my-core.el           — production-safe defaults, no-littering, backup/autosave (provides 'my-core)
    my-leader.el         — leader keymap with key-chord double-space and C-c u fallback (provides 'my-leader)
  modules/
    my-os-macos.el       — macOS: modifier keys, exec-path-from-shell, clipboard (provides 'my-os-macos)
    my-os-linux.el       — Linux: clipboard + trash integration (provides 'my-os-linux)
    my-os-windows.el     — Windows: Super modifiers, clipboard, trash (provides 'my-os-windows)
    my-ui.el             — sanityinc-tomorrow themes, spacious-padding, mood-line, fonts (provides 'my-ui)
    my-files.el          — Dired defaults, explicit Dirvish workflow, PDF viewing via pdf-tools (provides 'my-files)
    my-editing.el        — vertico, orderless, marginalia, consult, embark, corfu, cape, devil, vundo, markdown (provides 'my-editing)
    my-dev.el            — magit, eglot, tree-sitter, flymake, diff-hl, compile (provides 'my-dev)
    my-org-mode.el       — org capture, agenda, refile, org-id, export, custom headline bullets, org-bars (provides 'my-org-mode)
    my-tramp.el          — TRAMP helpers and Nix host shortcuts (provides 'my-tramp)
    my-shells.el         — project-aware shell management (provides 'my-shells)
    my-feeds.el          — Elfeed, elfeed-goodies, elfeed-tube, feed browsing (provides 'my-feeds)
    my-reading.el        — local-first read-later captures, snapshots, Reader migration (provides 'my-reading)
    my-nodes.el          — org-node networked notes, backlinks, node search (provides 'my-nodes)
    my-bookmarks.el      — org-backed bookmark manager (provides 'my-bookmarks)
    my-ai.el             — gptel + agent-shell: LLM chat, Claude Code, Codex (provides 'my-ai)
    my-mail.el           — mu4e, Org contact completion, mbsync, msmtp, org-msg, dashboard, org mail capture (provides 'my-mail)
    my-contacts.el       — Emacs wrapper for standalone icloud-to-org-contacts CLI (provides 'my-contacts)
    my-node.el           — shared node-only hooks selected by host profile (provides 'my-node)
    my-ops.el            — placeholder, flag disabled (provides 'my-ops)
  elisp/
    my-elfeed.el                 — shared Elfeed helpers (entry-at-point)
    my-feeds-search-header.el    — Powerline header rendering for Elfeed search/show
    my-node-contact-email.el     — org-node contact email completion helper
    my-org-headline-bullets.el   — display-only Org headline bullet glyphs
    my-org-property-drawers.el   — keep Org property drawers folded
    my-org-tag-transitions.el    — automatic Org tag transition rules
  scripts/
    bookmark-open        — helper for opening bookmark URLs
    bootstrap-mail-config.sh — idempotent local mail bootstrap helper
    mail-auth-value      — authinfo reader for mbsync/msmtp password helpers
    mail-sync            — launchd-friendly mail sync/index helper
    read-later-capture   — canonical CLI capture entrypoint for URLs and metadata
    read-later-delete    — deletes items plus generated queue/snapshot/feed state
    read-later-feed      — generates the local RSS feed consumed by elfeed-org
    read-later-readability — Playwright/Mozilla Readability article extractor
    read-later-snapshot  — fetch readable/full snapshots for queued captures
    readwise-export-import — one-time Readwise/Reader export importer
  test/
    my-feeds-search-header-tests.el — ERT tests for Elfeed search-header layout helpers
    my-org-headline-bullets-tests.el — ERT tests for headline bullet glyph + matcher
    my-org-tag-transitions-tests.el — ERT tests for tag transition rules and buffer transforms
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
- **Keep source and state separate.** Tracked repo files use `my-emacs-source-root` via `my-emacs-source-file`; writable local state uses `user-emacs-directory` via `my-emacs-state-file`.
- **`provide` must match filename.** `my-core.el` provides `'my-core`.  Always.
- **`use-package-always-ensure` is host-aware.** It stays enabled on normal editable hosts and is disabled for `my-host-type = node`; don't add redundant `:ensure t` on external packages.  Use `:ensure nil` for built-in packages.

## Host Profiles

- `MY_EMACS_SOURCE_ROOT` may point at a read-only source checkout that differs from `user-emacs-directory`.
- `MY_EMACS_HOST_CONTEXT` is loaded near the top of `init.el`, before `my-flags`, so host shims can pre-bind flags and host-only variables.
- `my-host-type = node` means a headless harness host: `use-package-always-ensure` and package-vc installs are disabled, and `my-node.el` is loaded when `my-flag-node` is non-nil.
- Keep non-portable paths and secrets outside the repo in the host-context shim; keep shared node behavior in `modules/my-node.el`.

## Coding Conventions

**Canonical style guide: [`docs/emacs-lisp-style-guide.md`](docs/emacs-lisp-style-guide.md).**
All new code and changes to existing code must conform to it.  This is a
local pandoc-converted copy of bbatsov/emacs-lisp-style-guide checked in
so it's greppable without network access.  The bullets below are
project-specific additions and reminders; for everything else (lambdas in
hooks, sharp-quoting function references, `when`/`unless`/`cond` shape,
`(declare (debug …))` on macros, parameter count, predicate naming,
docstring imperative voice, etc.) defer to the style guide.

`.dir-locals.el` enforces `indent-tabs-mode nil` and `fill-column 80` for
`emacs-lisp-mode` in this repo.

Project-specific additions on top of the style guide:

- Lexical binding on every file: `;;; filename.el --- Description -*- lexical-binding: t; -*-`
- `my-` prefix on all symbols (functions, variables, keymaps) to avoid collisions
- `use-package` for all package config with declarative keywords (`:hook`, `:bind`, `:custom`)
- `:custom` for user options, `:config` for post-load logic, `:init` for pre-load setup
- `cl-lib` not deprecated `cl`
- Comments explain *why*, not *what*
- Section headers use `;;; Section name ---` with dashes to column 70

## Keybinding Architecture

- All personal bindings live in `my-leader-map`, accessible via double-space chord or `C-c u`
- Leader sub-prefixes: `b` buffer, `c` compile, `d` Dired/Dirvish, `e` emacs/eval, `f` files/search, `g` git, `m` mail/bookmarks, `n` news/feeds, `o` org, `p` project, `r` remote/TRAMP, `s` shell, `w` window
- Use `my-leader-define` to add leader bindings
- Mode-local bindings (`:map some-mode-map`) stay in their respective module files
- Don't shadow core Emacs bindings without strong justification
- `which-key-add-keymap-based-replacements` provides descriptions for sub-prefixes

## Package Management

- `package.el` with MELPA and GNU ELPA
- `use-package` (built-in Emacs 29+) for configuration
- No `straight.el`, no `elpaca` (future migration path)
- GitHub-only packages may use `use-package :vc` / package-vc; prefer ELPA/MELPA when available
- One package at a time.  Each must solve a concrete problem.

## Emacs As An Inspection Tool

- Prefer asking the running Emacs daemon before guessing about Emacs Lisp APIs,
  package behavior, keybindings, variables, or loaded features.  Use
  `emacsclient --eval` first because it sees the same runtime state the user is
  actually using.
- Keep inspection forms read-only unless the task explicitly requires mutation.
  Use Emacs as a source of truth, not as a place to make hidden state changes.
- Use `emacs --batch -l ~/.emacs.d/init.el --eval ...` only when the daemon is
  unavailable or startup itself is under investigation.  Use `emacs -Q --batch`
  when comparing against vanilla Emacs behavior.
- Prefer Emacs' self-documenting APIs over memory or invented helper code:
  `documentation`, `documentation-property`, `apropos-internal`,
  `where-is-internal`, `key-binding`, `symbol-file`, `find-function-noselect`,
  `find-variable-noselect`, `boundp`, `fboundp`, `featurep`, `locate-library`,
  `symbol-value`, `default-value`, and `macroexpand-1`.
- In an interactive Emacs session, use the normal help system as well:
  `describe-function`, `describe-variable`, `describe-key`,
  `describe-symbol`, `apropos`, and `info`.
- For package questions, check whether the package is loaded with `featurep`,
  whether it can be found with `locate-library`, where a symbol comes from with
  `symbol-file`, and what the local value/customization is with `symbol-value`
  or `default-value`.
- For keybinding questions, inspect both command bindings and keymaps.  Use
  `where-is-internal` to find keys for a command, `key-binding` to resolve a
  key sequence, and then inspect this repo for the durable definition.
- For hooks, modes, and package setup, inspect the live value first, then read
  the defining source.  This helps distinguish configured behavior from package
  defaults.
- Example client inspections:

  ```sh
  emacsclient --eval "(documentation 'consult-ripgrep)"
  emacsclient --eval "(apropos-internal \"ripgrep\" 'fboundp)"
  emacsclient --eval "(where-is-internal 'consult-ripgrep)"
  emacsclient --eval "(symbol-file 'consult-ripgrep 'defun)"
  emacsclient --eval "(boundp 'my-notes-directory)"
  emacsclient --eval "(symbol-value 'my-notes-directory)"
  emacsclient --eval "(locate-library \"org-node\")"
  emacsclient --eval "(macroexpand-1 '(use-package consult :commands consult-ripgrep))"
  ```

Use CLI tools for broad repository search (`rg` first), and use Emacs
inspection for Emacs semantics.  The best workflow is usually: search the repo,
ask Emacs what is live, then edit the smallest source file that owns the
behavior.

## Platform

- Supported platforms: macOS, Linux, and Windows via OS-specific modules
- `my-os-macos.el`, `my-os-linux.el`, or `my-os-windows.el` is loaded by `system-type` (not a flag)
- Primary daily driver: macOS (Apple Silicon, Homebrew emacs-plus with native-comp)
- Shell: zsh
- Python LSP: `pylsp` via pip3 (`~/Library/Python/3.9/bin/`)
- TypeScript LSP: `typescript-language-server` via npm (`~/.npm-global/bin/`)
- Tools: ripgrep, pandoc, multimarkdown, yt-dlp, mpv, mu, mbsync, msmtp
- Remote/TRAMP host aliases are documented in `etc/ssh-config.example` (copy to `~/.ssh/config` per machine)

## Theme System

- `color-theme-sanityinc-tomorrow` (`sanityinc-tomorrow-night` / `sanityinc-tomorrow-day`)
- On macOS, auto-switches via `ns-system-appearance-change-functions`; on other OSes, uses frame background mode at startup
- `mood-line` for the mode line, with Fira Code-compatible glyphs enabled
- Org buffers use fixed-pitch layout inspired by NANO/book-mode, without enabling `book-mode` globally
- `nerd-icons` is available for targeted UI surfaces; Dirvish uses its own `nerd-icons` attribute
- `pdf-tools` is enabled via `pdf-loader-install`, so opening a PDF switches to `pdf-view-mode` on demand instead of front-loading PDF support at startup

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
- Org files open folded to top-level headings (`overview`); property drawers stay hidden but participate in normal cycling
- Exports: built-in Org -> LaTeX -> PDF plus `ox-pandoc` for broader format conversion
  Verified Pandoc targets on this machine: `docx`, `latex-pdf`, `beamer-pdf`, `html5-pdf`
  `ox-pandoc` uses `pdflatex` for `latex-pdf` / `beamer-pdf` and `weasyprint` for `html5-pdf`
  Not installed by default: `context-pdf`, `typst-pdf`, `wkhtmltopdf`/`prince`/`groff`-dependent routes

## Testing Changes

- `M-x eval-buffer` to reload a single file without restarting
- `M-x check-parens` before saving any `.el` file
- `emacs --debug-init` if startup breaks
- `C-x b *startup-errors*` to check for module failures
- `C-x b *Messages*` for startup time and warnings
- Startup target: under 1 second

## Automated Tests (ERT)

Tests live in `test/`, one `*-tests.el` file per source module.  Run the
full suite with `make test` (uses `emacs -Q --batch -L elisp -L test`),
or run interactively in a normal Emacs session with `M-x ert RET t RET`
after evaluating the test file — interactive ERT gives clickable
backtraces and lets you re-run a single failing test with debugging on.

When deciding whether to add tests for a new file, apply this heuristic:

- **Is there a pure function that takes inputs and returns outputs?**
  If yes, test it.  This is where regressions hide and where ERT pays
  back the maintenance cost.
- **If the answer is no**, either refactor to expose one (e.g., split a
  filtering step out of an interactive command so it can be unit-tested
  with a list argument), or skip the file.
- **Skip rendering, hooks, and advice by default.**  They are both the
  hardest to test and the least likely to silently break — visible
  breakage is its own test, and the fixtures required (face attributes,
  buffer-local state, advice ordering, Org version coupling) cost more
  than they save.

Prefer testing buffer transforms with `with-temp-buffer` and
`(let ((MODE-HOOK nil)) (MODE))` to isolate from user config.  Bind
dynamic variables the function under test reads (e.g., rule tables,
column widths) inside the test so each test owns its inputs.

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
- Review the full diff before staging. Use `git add -A` only when the user confirms the whole worktree belongs in scope, then commit and push.

## What NOT to Do

- Don't add packages without a concrete problem to solve
- Don't use deprecated APIs or `(require 'cl)`
- Don't load packages in `early-init.el`
- Don't hardcode absolute paths
- Don't create `defcustom` for settings that won't be changed at runtime
- Don't add `(provide 'early-init)` or `(provide 'init)` — loaded by path, not `require`
- Don't over-engineer — if 5 lines solve it, don't build a minor mode
