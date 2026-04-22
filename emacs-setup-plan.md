# Emacs Setup Plan

## Design Philosophy

A modular, flag-driven Emacs configuration built for gradual layering.
Each module can be enabled or disabled independently, supporting
profiles like dev-only, writing-only, travel, or headless/server mode.

The config is not an editor. It is a programmable personal computing
environment — editing, knowledge, orchestration, terminal control,
git, agents, and eventually browser embedding and task automation. But
we layer this gradually.

---

## Installation

### macOS (Apple Silicon)

Emacs is installed via `emacs-plus`, a community-maintained Homebrew tap
that provides a native macOS app with extensive build options.

Homebrew must be installed natively at `/opt/homebrew/` (not
`/usr/local/`, which is the Intel/Rosetta path). Verify with
`which brew` — it should return `/opt/homebrew/bin/brew`.

```bash
brew tap d12frosted/emacs-plus
brew install emacs-plus@30 --with-xwidgets --with-imagemagick --with-mailutils --with-ctags --with-compress-install
```

Native compilation, tree-sitter, and other core features are included by
default in `emacs-plus@30`. No `--with-native-comp` flag is needed.

After installation, copy to Applications (the install output will
confirm the exact paths):

```bash
cp -r /opt/homebrew/opt/emacs-plus@30/Emacs.app /Applications/
cp -r "/opt/homebrew/opt/emacs-plus@30/Emacs Client.app" /Applications/
```

Use `cp -r` rather than symlinks for better Spotlight integration. After
a `brew upgrade emacs-plus@30`, re-copy to update the apps in
`/Applications`.

### Linux

To be documented when a Linux environment is set up.

### Windows

To be documented if needed.

---

## Core Structure

The config is logically divided into modules, not tied to a specific
directory layout:

- **init** — bootstrap only, no logic beyond orchestration
- **early-init** — startup performance, UI suppression, GC tuning
- **core** — production-safe defaults and infrastructure
- **ui** — visual decisions (theme, modeline, fonts)
- **files** — Dired defaults, explicit Dirvish workflow, and on-demand PDF viewing
- **editing** — completion, minibuffer, undo, pairs
- **dev** — git, projects, LSP, tree-sitter
- **notes** — org, capture, agenda, IDs
- **mail** — mu4e, mbsync/msmtp integration, org-msg, dashboard, mail capture
- **feeds** — Elfeed, elfeed-org, elfeed-goodies, YouTube enhancements
- **ai** — gptel plus CLI coding-agent shells
- **ops** — async processes, job runners, logging helpers, remote helpers, and orchestration utilities
- **leader** — custom leader key map (double-space chord via `key-chord`, `C-c u` as fallback)
- **os** — platform-specific modules (macOS, Linux, Windows)

Each module is loaded conditionally via feature flags.

---

## Feature Flags

All flags live in a single configuration file loaded before anything
else. This makes it trivial to create alternate profiles by swapping one
file.

Example flags: `dev`, `org`, `ai`, `writing`, `minimal`.

Example profiles:

- **Default** — core + ui + editing + dev + notes
- **Travel** — core + ui + editing + notes (no dev tooling)
- **Headless** — core + dev (no UI modules)
- **Minimal** — core only

---

## Step 1 — Minimal Bootstrap

The main init file does three things:

1. Sets load-path
2. Loads the feature flag configuration
3. Loads modules conditionally based on flags

No logic beyond orchestration. Nothing else belongs here.

---

## Step 2 — Error Resilience

Each optional module load is wrapped so that a broken module does not
take down the entire config. A simple macro catches errors per-module
and logs them to a `*startup-errors*` buffer, including the module name
and error message.

However:

- **The core module must fail hard.** If core infrastructure fails,
  Emacs should not silently continue in a partially initialized state.
- Optional modules fail gracefully. Foundational modules do not.

This prevents debugging partial, inconsistent startup states.

---

## Step 3 — Production-Safe Defaults

These are non-negotiable quality-of-life settings applied in the core
module:

- Centralized backups and autosaves (not scattered across the filesystem)
- `no-littering` package to keep config and data directories clean
- Persistent minibuffer history (`savehist-mode`)
- Recent files tracking (`recentf-mode`)
- Auto-revert external file changes (`global-auto-revert-mode`)
- Sensible GC tuning (high threshold during startup, lowered after init)
- Native compilation enabled in the build (e.g., emacs-plus with native-comp)
- Buffer name uniquification (`uniquify`)
- Electric pair mode for auto-closing brackets and quotes
- Lockfiles disabled (`create-lockfiles nil`) — prevents issues with file watchers

If `no-littering` is enabled early, document clearly where backups,
caches, and auto-saves are redirected to avoid confusion during
debugging.

These prevent the majority of long-term config regret. Get them right
once.

---

## Step 4 — Package Strategy

Start with:

- Built-in `package.el`
- `use-package` for structured, declarative package configuration

The priority right now is iteration speed, not reproducibility.

Future upgrade path: `elpaca` provides async installation, git-based
pinning, and reproducible builds without the weight of `straight.el`.
Switching package managers should be treated as a deliberate migration
step once the system stabilizes, not something done mid-iteration.

---

## Step 5 — Path A: Development Stack

A modern vanilla completion and development stack:

### Minibuffer and Completion:

- Vertico (minibuffer UI)
- Orderless (flexible matching)
- Marginalia (rich annotations)
- nerd-icons-completion (icons in supported completion surfaces)
- Consult (power commands — search, buffer switching, line jumping)
- Embark (context actions on completion candidates)
- Corfu (in-buffer completion popup, auto-complete enabled, 0.2s delay, 2-char prefix)
- Cape (extra completion-at-point backends — file paths, dabbrev, keywords; plugs directly into Corfu)
- Devil (semicolon-triggered modifier-free entry for default Emacs keybindings)
- vundo (visual undo tree on `C-x u` — replaces undo-tree, no persistence corruption risk)

### UI:

- ef-themes (`ef-dark` / `ef-light`) with macOS appearance switching
- spacious-padding for frame/window breathing room
- moody + minions (ribbon-style modeline + minor-mode collapse)
- nerd-icons-mode-line, installed beside Moody's buffer identification

### Development:

- Magit (git)
- Eglot (LSP, built-in from Emacs 29+)
- Native tree-sitter integration
- `treesit-auto` (major mode remapping only for grammars already installed)
- diff-hl (fringe git change indicators, kept in sync via Magit post-refresh hook)

### Files:

- Dired remains the plain default for `M-x dired` and leader `d d`
- Dirvish is available explicitly via `M-x dirvish`, `M-x dirvish-dwim`, and leader `d D`
- Dirvish uses its own Nerd Icons attribute; `nerd-icons-dired` is installed but not auto-enabled so plain Dired stays plain during evaluation
- PDFs open through `pdf-tools`; `pdf-loader-install` keeps startup light and activates `pdf-view-mode` only when a PDF is visited

### Language Servers:

Language servers are system tools, not Emacs packages — install manually:

- Python: `pip3 install python-lsp-server`
- TypeScript: `npm install -g typescript-language-server typescript`
  (npm global prefix: `~/.npm-global` to avoid permission issues)

Eglot hooks must target `-ts-mode` variants (`python-ts-mode`, `js-ts-mode`, etc.)
since `treesit-auto` remaps traditional major modes.

Tree-sitter grammar installation follows a clear policy:

- Grammars are installed intentionally, outside of incidental file previews.
- `treesit-auto` only registers `-ts-mode` remaps for grammars already present.
- Missing grammars fall back to regular major modes instead of prompting during Dirvish previews or other transient buffer visits.

Keep it minimal. Avoid stacking redundant packages. Every addition
should solve a concrete problem.

---

## Step 6 — Path B: Knowledge / Org

Design principles:

- A single root variable for all notes (no absolute paths baked in)
- No external sync assumptions
- Org is a subsystem, not the entire environment

Core setup:

- Capture templates (todo, contextual note, daily journal)
- Agenda configuration
- `org-id` enabled from day one, generating IDs on capture
- `org-modern` for visual polish (styled bullets, TODO keywords, table rendering)
- Open org files folded to top-level headings
- Hide property drawers by default while keeping them available through normal cycling
- Keep Org's built-in LaTeX -> PDF export path, and add `ox-pandoc` for broader export targets
- Pandoc PDF targets are split intentionally: `latex-pdf` and `beamer-pdf` use `pdflatex`, while `html5-pdf` uses `weasyprint`
- Verified Pandoc targets on this machine: `docx`, `latex-pdf`, `beamer-pdf`, `html5-pdf`
- Unprovisioned Pandoc engines are intentionally left out for now: `context`, `typst`, `wkhtmltopdf`, `prince`, `groff`

Define an ID policy early (e.g., IDs added on capture rather than
retroactively). Retrofitting IDs across hundreds of files is painful.

Choose a **canonical notes format** for capture and linking (likely
Org). Avoid parallel capture systems across multiple formats.

Journaling strategy can be decided later, but the capture and ID
scaffolding should not wait.

---

## Step 7 — Path C: AI / Control Layer (complete)

### Implementation

`my-ai.el` provides two packages:

**gptel** (LLM conversations):
- Installed via `:vc` from `karthink/gptel`
- Backends auto-registered: OpenAI, Anthropic Claude, OpenRouter, Ollama
- Auth: env var with auth-source fallback (`my-ai--env-or-auth-source-secret`)
- Streaming enabled, curl transport
- Interactive entry: `my-ai-chat`

**agent-shell** (CLI coding agents):
- Claude Code via `my-ai-claude` (spawns `claude-agent-acp`)
- Codex via `my-ai-codex` (spawns `codex-acp`)
- Auth delegated to each CLI tool's native login

### Architectural Principles (preserved)

The AI layer:
- Is swappable across backends
- Supports multiple providers simultaneously
- Does not pollute editing modules
- Does not require UI dependencies
- Works over SSH (gptel uses curl, agent-shell uses CLI tools)
- Is treated as a service adapter, not a feature

---

## Step 8 — OS Specific Layer

Where possible identify settings, packages and key-binding changes
needed per operating system:

- macOS
- Linux
- Windows

Only platform-specific concerns belong here:

- Modifier key behavior: Command = Meta, Option = Super, Fn = Hyper, Right Option = none
- Clipboard integration
- Font: first available mono from JetBrains Mono, Fira Code, SF Mono, Menlo, or DejaVu Sans Mono at height 160; variable-pitch prose uses Avenir Next/SF Pro Text/etc. at height 170
- Smooth scrolling tweaks
- `exec-path-from-shell` for GUI and daemon sessions so launchd-started Emacs inherits Homebrew paths
- `ns-auto-titlebar` for dark mode consistency
- `frame-resize-pixelwise` set to `t` (prevents gaps when tiling windows)

Nothing else should live in this module.

---

## Long-Term Direction

This config is building toward a programmable personal computing
environment:

- Editing
- Knowledge management
- Orchestration and task automation
- Terminal control
- Git
- AI agents
- Browser embedding (xwidgets)
- Remote development (TRAMP)

Each capability is layered in only when the foundation beneath it is
stable.

---

## The Rules

1. Do not install 30 packages at once
2. Do not copy someone else's mega-config
3. Do not use a framework (Doom, Spacemacs) — build understanding first
4. Do not optimize before stable behavior emerges
5. Do not hardcode paths
6. Do not over-automate before you know what you actually need
7. Every optional module must fail gracefully without taking down the config
8. Every new package must solve a concrete, identified problem
9. Track startup time and avoid silent performance regressions
