# Emacs Configuration — Decision Log

This document records key decisions made during the build of this Emacs
configuration. Each entry captures what was chosen, why, and what the
alternatives were. This serves as a reference for future changes and
as onboarding documentation.

## Current State Overrides (2026-04-17)

These entries supersede older sections below where they conflict.

- Leader trigger is `key-chord` double-space (`"  "`), with `C-c u` as fallback.
- `key-chord` is treated as optional at startup; failure falls back to `C-c u`.
- Theme stack uses `color-theme-sanityinc-tomorrow`
  (`sanityinc-tomorrow-night` / `sanityinc-tomorrow-day`).
- Modeline stack uses `mood-line` with Fira Code-compatible glyphs enabled.
- OS modules now exist for macOS, Linux, and Windows and are loaded by `system-type`.
- File-manager reveal is cross-platform via `my-reveal-in-file-manager`.
- Standard Dired remains the default; Dirvish is explicit via `dirvish`,
  `dirvish-dwim`, and leader `d D`.
- Elfeed search layout uses fixed `Date`, `Tags`, and `Feed Source`
  columns with `Subject` as the flexible final column.
- Mail uses mu4e from Homebrew/site-lisp, org-msg for compose, and
  mu4e-dashboard as the main dashboard/sidebar surface.

---

## Architecture

### Modular, flag-driven structure

**Chosen:** Modules in `core/` and `modules/`, loaded conditionally via
feature flags in `core/my-flags.el`.

**Why:** Each capability layer can be toggled independently. Swapping
one flags file creates a different profile (dev-only, travel, headless).
A broken optional module cannot take down the config.

**Alternatives considered:**
- Single monolithic `init.el` — doesn't scale, hard to debug.
- Doom/Spacemacs framework — violates the "build understanding first" principle.
- Literate config (org-babel) — adds complexity without clear payoff at this stage.

---

### File naming convention

**Chosen:** Filenames use the `my-` prefix (`my-core.el`, `my-ui.el`).
Each file's `provide` symbol matches its filename exactly.

**Why:** Emacs `require` resolves by symbol name, searching `load-path`
for a matching filename. Without the prefix, `(require 'core)` could
collide with third-party packages. Matching filename to symbol avoids
confusion and makes the relationship greppable.

**Alternatives considered:**
- Clean filenames without prefix (`core.el`), using `load` by path
  instead of `require` — loses duplicate-load protection.

---

### Core fails hard, modules fail gracefully

**Chosen:** `my-flags`, `my-loader`, and `my-core` are loaded via bare
`require` in `init.el`. Optional modules are wrapped in `my-load-module`
(a `condition-case` macro) that catches errors and logs them to
`*startup-errors*`.

**Why:** If core infrastructure fails, Emacs should not silently continue
in a partially initialized state — that creates debugging nightmares.
Optional modules should degrade gracefully so you always have a working
editor.

---

### Package bootstrap lives in `init.el`

**Chosen:** `package-initialize`, archive setup, and `use-package` require
are in `init.el`, not in `my-core.el`.

**Why:** These are orchestration concerns — they enable everything else
but aren't "defaults." Keeping them in `init.el` makes the boot
sequence explicit: paths → flags → packages → loader → core → modules.

---

### OS detection via `system-type`, not a feature flag

**Chosen:** `(when (eq system-type 'darwin) ...)` in `init.el` instead
of a `my-flag-os` toggle.

**Why:** Platform is a fact, not a preference. Flags should be reserved
for things you'd actually want to toggle on the same machine.

---

## `early-init.el`

### GC threshold set to `most-positive-fixnum` during startup

**Chosen:** Disable GC during init, restore to 16 MB after startup via
`emacs-startup-hook`.

**Why:** Prevents GC pauses during the heavy loading phase. 16 MB is
the runtime threshold — well above the 800 KB default, but not so high
that GC pauses become noticeable during editing.

**Alternatives considered:**
- 64 MB runtime threshold — aggressive, only justified by profiling.

---

### `file-name-handler-alist` cleared during startup

**Chosen:** Save and nil out the handler list in `early-init.el`, restore
in `my-core.el` via `emacs-startup-hook`.

**Why:** Every `load` and `require` during init checks file paths against
regex handlers (TRAMP, compression, etc.). None of our config files are
remote or compressed, so this is wasted work — ~10 regex matches per
file load for no benefit.

---

### `inhibit-redisplay` not used

**Chosen:** Removed. Was added initially but not kept.

**Why:** Requires careful restoration — if `my-core.el` fails to load,
Emacs becomes completely unresponsive with no display output. The risk
of a bricked display outweighs the minor flicker reduction. Frame alist
settings already prevent most visual flash.

---

### UI suppressed via `default-frame-alist`, not mode toggles

**Chosen:** `(push '(menu-bar-lines . 0) default-frame-alist)` instead
of `(menu-bar-mode -1)`.

**Why:** `early-init.el` runs before the first frame exists. `menu-bar-mode`
operates on existing frames — calling it here would create the frame
with the menu bar visible, then remove it, causing a flash. Pushing to
`default-frame-alist` creates frames without these elements from the start.

---

### `package-enable-at-startup` set to `nil`

**Chosen:** Prevent `package.el` from auto-initializing.

**Why:** We call `package-initialize` ourselves in `init.el` after
setting up archive sources. Without this, Emacs would initialize
packages twice.

---

## `my-core.el`

### `no-littering` for directory cleanliness

**Chosen:** `no-littering` package, loaded with `:demand t`.

**Why:** Redirects all package-generated files into `~/.emacs.d/etc/`
(configuration) and `~/.emacs.d/var/` (runtime state). Without it,
packages scatter files across `~/.emacs.d/`, making it hard to
distinguish config from clutter.

**Alternatives considered:**
- Manual `setq` for each package's data directory — tedious, incomplete,
  and doesn't cover future packages.

---

### Centralized backups with versioning

**Chosen:** `backup-by-copying t`, `version-control t`, 5 newest / 2
oldest kept.

**Why:** Prevents backup files from scattering across the filesystem.
`backup-by-copying` preserves symlinks and file ownership. Versioned
backups provide multiple recovery points.

---

### Lockfiles disabled

**Chosen:** `create-lockfiles nil`.

**Why:** Lockfiles (`#filename#`) cause issues with file watchers
(webpack, esbuild, etc.). Safe to disable for single-user setups.

---

### `ring-bell-function` set to `ignore`

**Chosen:** Silent bell.

**Why:** The default audible bell (and macOS visual flash) triggers on
`C-g`, failed searches, end of buffer, and many other common situations.
Purely annoying with no informational value.

---

### `use-short-answers` over `fset`

**Chosen:** `(setq use-short-answers t)` instead of
`(fset 'yes-or-no-p 'y-or-n-p)`.

**Why:** `use-short-answers` is the Emacs 28+ idiomatic approach. The
`fset` approach is a legacy hack that directly patches a function definition.

---

## `my-os-macos.el`

### Modifier key mapping

**Chosen:** Command = Meta, Option = Super, Fn = Hyper, Right Option = none.

**Why:** Command → Meta keeps Emacs muscle memory aligned with every
tutorial and manual (`M-x` = Command-x). Option → Super frees it for
special characters (accented input). Right Option = none allows raw
character input on international keyboards.

---

### `exec-path-from-shell`

**Chosen:** Used for GUI and daemon sessions.

**Why:** GUI Emacs and launchd-started daemon Emacs on macOS do not inherit
the terminal's `$PATH`. Without this, tools like `git`, `node`, `rg`, `pylsp`,
`mu`, `mbsync`, and Homebrew GCC support files can be missing. Correct PATH
inheritance is also part of the native-comp stability fix for daemon startup.

**Alternatives considered:**
- Manual `exec-path` setting — faster but brittle, needs updating when
  new tools are installed.

---

### Font fallbacks and larger default size

**Chosen:** Prefer JetBrains Mono, then Fira Code, SF Mono, Menlo, and
DejaVu Sans Mono at height 130. Variable-pitch prose prefers Avenir Next,
SF Pro Text, Helvetica Neue, Cantarell, and DejaVu Sans at height 140.

**Why:** The fallback list keeps the config portable while still preferring
high-quality fonts on macOS. Height 130/140 keeps JetBrains Mono readable
without making Org outlines feel oversized. Font detection is frame-aware and
applied to all existing graphical frames as well as future frames, so
daemon/server startup cannot leave the first GUI frame on the platform default
font.

**Previously tried:** Atkinson Hyperlegible Mono — decided against for
personal preference.

---

### `ns-auto-titlebar`

**Chosen:** Used for dark mode titlebar consistency.

**Why:** Makes the macOS titlebar match the Emacs theme background.
Without it, a dark theme has a jarring light titlebar.

---

## `my-ui.el`

### color-theme-sanityinc-tomorrow

**Chosen:** `color-theme-sanityinc-tomorrow`, using
`sanityinc-tomorrow-night` for dark appearance and `sanityinc-tomorrow-day`
for light appearance.

**Why:** The Tomorrow day/night pair gives a familiar, balanced light/dark
palette while preserving the rest of the custom frame, Org, and modeline
layout. Dark/light switching still follows macOS appearance when available.

**Previously used:** ef-themes (`ef-dark` / `ef-light`) and nano-theme
(`nano-dark` / `nano-light`).

---

### Soft macOS frame shell

**Chosen:** Add `alpha-background`, `ns-background-blur`, and
`ns-alpha-elements` to `default-frame-alist` on macOS, start macOS GUI
sessions as a modest floating frame, then reapply supported transparency
parameters to newly created frames from `my-ui.el`. Non-macOS hosts keep the
previous maximized default.

**Why:** This recreates the translucent frame from the reference image while
preserving the native macOS titlebar and traffic-light window controls. The
settings stay harmless on Emacs builds that do not support the Emacs Plus
blur patch.

---

### System appearance switching via built-in hook

**Chosen:** A small custom function on `ns-system-appearance-change-functions`
instead of the `auto-dark` package.

**Why:** `auto-dark` failed to detect the initial system appearance
reliably and didn't respond to OS toggles in testing. The built-in hook
is a direct NS-port callback — instant, no polling, no extra dependency.

**Previously tried:** `auto-dark` package — removed due to detection failures.

---

### Measured responsiveness before visual rollback

**Chosen:** Improve redisplay and long-line behavior first with
`redisplay-skip-fontification-on-input`, `jit-lock-defer-time`, and targeted
`so-long` handling for long Org files.

**Why:** Local testing showed long Org lines and fontification during movement
are plausible lag sources, while the current frame blur, transparency,
`mood-line`, and `ultra-scroll` remain part of the intended daily UI. Heavier
visual cuts should wait for profiling or a specific reproduced bottleneck.

---

### `mood-line`

**Chosen:** `mood-line`, enabled globally with `mood-line-mode`.

**Why:** It is a lightweight, conventional mode line with good defaults and
customizable glyph sets. The config uses `mood-line-glyphs-fira-code` for
prettier buffer, VC, and checker indicators without hand-rolling mode-line
state.

**Previously used:** `nano-modeline`, and before that `moody` with `minions`
and `nerd-icons-mode-line`.

---

### Line numbers in `prog-mode` only

**Chosen:** `display-line-numbers-mode` on `prog-mode-hook`.

**Why:** Line numbers are useful in code, distracting in prose.

---

## `my-editing.el`

### Vertico stack over Helm/Ivy

**Chosen:** Vertico + Orderless + Marginalia + Consult + Embark.

**Why:** Each package enhances one specific part of the built-in
completion system rather than replacing it. Small, independent,
composable. Any package can be removed without breaking the others.
The entire stack is smaller than Ivy alone.

**Alternatives considered:**
- Helm — self-contained ecosystem, locks you in. ~15,000+ lines.
- Ivy/Counsel/Swiper — smaller than Helm but still monolithic. ~10,000+ lines.
- fido-vertical-mode (built-in) — zero dependencies, gets 80% there,
  but has edge cases with Orderless and packages expecting standard
  `completing-read` behavior. Vertico is ~600 lines and purpose-built.

---

### `C-s` bound to `consult-line`

**Chosen:** Replaces default `isearch-forward`.

**Why:** `consult-line` shows all matching lines with live preview via
Vertico. More powerful for navigation. Most people prefer it once adjusted.

**Tradeoff:** Changes a fundamental keybinding. If it feels wrong,
move to `M-s l` and restore `C-s` as `isearch-forward`.

---

### `C-c u g` for `consult-ripgrep`

**Chosen:** Personal prefix binding instead of `M-s r`.

**Why:** Consistency — custom bindings live under `C-c u` per the system
convention.

---

### Corfu with auto-completion enabled

**Chosen:** `corfu-auto t`, 0.2s delay, 2 character prefix.

**Why:** More discoverable while learning. Closer to modern editor
behavior. Can be flipped to `nil` for manual triggering if it becomes
noisy.

**Alternative:** `corfu-auto nil` (manual via `M-TAB`) — less noise,
more control. Valid preference.

---

### `vundo` for visual undo

**Chosen:** `vundo` package on `C-x u`.

**Why:** Emacs undo is non-linear — it preserves all history but
navigating it linearly loses branches. vundo renders the full undo tree
and lets you jump to any state. Lightweight, no configuration beyond
the binding.

**Alternatives considered:**
- undo-tree — older, has known data corruption issues with its
  persistence feature.

---

### `devil` for modifier-light default bindings

**Chosen:** Devil mode with semicolon (`;`) as the activation key.

**Why:** Learning default Emacs bindings is valuable, but repeatedly holding
Control is physically costly. Devil mode provides a modifier-light path toward
default keybinding literacy without requiring OS-level Caps Lock remapping.

---

### `nerd-icons-completion`

**Chosen:** Enabled after init and integrated with Marginalia via
`marginalia-mode-hook`.

**Why:** Icons add lightweight recognition in completion surfaces without
changing completion behavior. Hooking the Marginalia setup avoids the package
turning itself back off when Marginalia is not active yet.

---

## `my-files.el`

### Dired stays plain by default

**Chosen:** Standard Dired remains the default for `M-x dired` and leader
`d d`. Dirvish is invoked explicitly via `M-x dirvish`, `M-x dirvish-dwim`,
and leader `d D`.

**Why:** Dirvish is promising, but keeping plain Dired available makes the
transition safer while the workflow is still being learned. It also keeps a
stable baseline for troubleshooting file-management behavior.

---

### Dirvish as enhanced file manager

**Chosen:** Dirvish is installed with `nerd-icons`, collapse, VC state,
file-time, and file-size attributes.

**Why:** Dirvish provides a more familiar file-manager surface while staying
based on Dired. Its own `nerd-icons` attribute handles icons in Dirvish
buffers; `nerd-icons-dired` is installed but not automatically enabled so
plain Dired remains visually plain for now.

---

### PDF viewing via `pdf-tools`

**Chosen:** `pdf-tools` is installed and activated with
`pdf-loader-install`, keeping PDF support on-demand.

**Why:** This replaces DocView with the better `pdf-view-mode` experience
without adding unnecessary startup work. The loader approach follows the
package's own recommendation when startup time matters.

---

## `my-dev.el`

### Eglot over lsp-mode

**Chosen:** Eglot (built-in from Emacs 29+).

**Why:** Built-in, minimal, integrates cleanly with the Vertico/Corfu
completion stack. Follows the principle of preferring built-in features.
Less configuration surface than lsp-mode.

**Alternatives considered:**
- lsp-mode — more features (breadcrumbs, lens, etc.) but heavier,
  more configuration, more dependencies. Can be revisited if Eglot
  proves insufficient.

---

### Tree-sitter via `treesit-auto`

**Chosen:** `treesit-auto` with implicit installation disabled. Only modes
whose grammars are already installed are registered in `auto-mode-alist`.

**Why:** Dirvish and other preview workflows can visit many files briefly.
Prompting for missing grammars or remapping to unavailable `-ts-mode`s creates
noisy warnings and interrupts browsing. Missing grammars now fall back to the
regular major modes until they are installed intentionally.

---

### Eglot hooks target `-ts-mode` variants

**Chosen:** `python-ts-mode`, `js-ts-mode`, `typescript-ts-mode`,
`tsx-ts-mode` in Eglot hooks.

**Why:** `treesit-auto` remaps traditional major modes to tree-sitter
variants. Hooks must target the actual mode that runs, which is the
`-ts-mode` version after remapping.

---

### Flymake over Flycheck

**Chosen:** Flymake (built-in).

**Why:** Integrates with Eglot automatically — Eglot registers its own
Flymake backend. No extra package needed.

**Alternatives considered:**
- Flycheck — more mature checker ecosystem, but redundant when Eglot
  already provides diagnostics via Flymake.

---

### `diff-hl` for fringe git indicators

**Chosen:** `diff-hl` with Magit post-refresh hook.

**Why:** Shows added/modified/deleted lines in the fringe. The Magit
hook keeps indicators in sync after git operations.

---

### Language servers installed manually

**Chosen:** External installation via `pip3` and `npm`.

**Why:** Language servers are system tools, not Emacs packages. Manual
installation keeps the config reproducible — the Elisp config doesn't
depend on system package managers.

- Python: `pip3 install python-lsp-server`
- TypeScript: `npm install -g typescript-language-server typescript`
  (npm global prefix set to `~/.npm-global` to avoid permission issues)

---

## `my-org-mode.el`

### Single notes root variable

**Chosen:** `my-notes-directory` set to `~/All-The-Things/`.

**Why:** All paths derive from this one variable. No absolute paths
baked into capture templates, agenda config, or org settings. Easy to
relocate or sync.

---

### Org capture templates: todo, note, journal

**Chosen:** Three templates — quick todo, contextual note, daily journal.

**Why:** Covers the most common capture workflows without overloading
with options. Todo and note go to `inbox.org`; journal goes to
`journal.org`.

---

### Journal uses `file+olp+datetree` with day tree type

**Chosen:** Year → Month → Day hierarchy (`tree-type day`).

**Why:** Personal preference for YYYY-MM-DD date organization.
Considered `:tree-type week` but changed to `:tree-type day`.

---

### `org-id` enabled from day one

**Chosen:** IDs generated automatically on every capture via
`org-capture-prepare-finalize-hook`.

**Why:** Retrofitting IDs across hundreds of files later is painful.
IDs make linking reliable — headings can move or rename without breaking
links.

---

### `org-id-link-to-org-use-id` set to `create-if-interactive-and-no-custom-id`

**Chosen:** IDs created on demand when manually storing links.

**Why:** Builds ID coverage gradually as you link between notes, without
bulk-generating IDs for every heading.

---

### Minimal custom Org headline bullets

**Chosen:** A small local `my-org-headline-bullets-mode`, hooked into
`org-mode`.

**Why:** Plain Org is calmer than the broader `org-modern` styling for TODO
keywords, tags, tables, checkboxes, lists, and metadata. The config only
replaces the final visible headline star with level-specific glyphs:
`●`, `○`, `◉`, `⌾`, and `⚬`. File contents stay as normal Org stars.
Continuous outline guide lines stay in a separate display layer.

**Previously used:** `org-modern`, with `org-modern-star` set to `replace`.
It was removed because its general Org polish made buffers feel busier than
plain Org.

---

### Org outline guide bars

**Chosen:** `org-bars`, installed via `:vc` from GitHub and layered on top of
`org-indent-mode`.

**Why:** Org indentation is already display-only and uses virtual line
prefixes. `org-bars` is purpose-built for those prefixes, keeps file contents
unchanged, preserves Org's normal visibility cycling, and allows the custom
headline bullet mode to remain responsible only for bullet glyphs.
`org-bars-with-dynamic-stars-p` is disabled so it does not replace headline
bullets, and Org buffers keep `line-spacing` nil because non-nil line spacing
creates visible gaps between the per-line bar images. `org-bars` gets one
extra pixel of image height to cover tiny gaps from heading font metric
rounding.

---

### Org visual indentation

**Chosen:** Keep `org-startup-indented` enabled.

**Why:** Org's own `org-indent-mode` visually nests body text and plain lists
under their parent headings without modifying file contents. Disabling it made
all list items render at the left edge across Org files, which looked like a
file indentation problem but was only a buffer display setting.

---

### Quiet Org layout instead of global `book-mode`

**Chosen:** `mood-line` for the mode line, plus fixed-pitch Org
typography and wider side margins. Org leaves `header-line-format` unset
unless another package sets it.

**Why:** `book-mode` is explicitly experimental and its own README describes
it as WIP. Recreating the visible layout locally gives the screenshot's
document feel without introducing a global, finicky UI mode. A custom
full-width bottom mode line was avoided because it can become taller than
expected and obscure the final buffer line in small frames.

---

### Folded startup and property drawers

**Chosen:** Org files open with `org-startup-folded` set to `overview`, so
only top-level headings are visible. Property drawers are hidden by default
with a custom helper while still participating in normal local cycling.

**Why:** This keeps daily org files scannable and reduces visual noise without
making metadata inaccessible. It preserves standard Org cycling semantics
instead of inventing a separate drawer UI.

---

### Org export: built-in LaTeX PDF plus `ox-pandoc`

**Chosen:** Keep Org's standard LaTeX exporter as the primary PDF path, and
add `ox-pandoc` for broader format conversion through Pandoc.

**Why:** PDF export is already a first-class Org workflow and works well once
the TeX toolchain is complete. `ox-pandoc` expands the available targets
without replacing the built-in Org exporter.

Pandoc's PDF routes now have explicit engines configured so the behavior is
predictable: `latex-pdf` and `beamer-pdf` use `pdflatex`, while `html5-pdf`
uses `weasyprint`.

Verified working on this macOS setup: `docx`, `latex-pdf`, `beamer-pdf`,
`html5-pdf`.

Left intentionally unprovisioned for now: `context-pdf`, `typst-pdf`, and
PDF routes that depend on `wkhtmltopdf`, `prince`, or `groff`.

---

## `my-feeds.el`

### Elfeed search layout

**Chosen:** A custom Elfeed search renderer with a plain `header-line` column
header in `Date`, `Tags`, `Subject`, `Feed Source` order. The metadata columns
use preferred widths, and the window-width `Subject` column sits before the
feed source.

**Why:** Elfeed renders into an Emacs character matrix, not a browser-style
responsive layout engine. Keeping metadata columns stable at normal frame
sizes makes scanning predictable, while letting the title column absorb
remaining width avoids fragile right-edge alignment and display-property hacks.
In narrow split windows, the feed and tag columns shrink only after `Subject`
hits its minimum width.

The search header intentionally avoids `elfeed-goodies` Powerline separators.
Those image/display-property separators looked too heavy and became visually
fragile after the Emacs 31 update. A buffer-local resize hook debounces forced
Elfeed redraws so the listing follows horizontal frame/window changes without
manual `g` refreshes.

**Alternatives considered:**
- Proportional column compression — more "responsive" in theory, but noisy
  in a character-grid UI and likely to make all columns less readable.
- Right-aligning feed sources against the window edge — worked poorly across
  frame sizes and introduced fragile display-property behavior.
- Putting `Feed Source` before `Subject` — kept metadata together, but made the
  subject/title column start too far to the right for quick scanning.
- Keeping the Powerline header — visually distinctive, but too sensitive to
  theme and renderer changes for a utility buffer.

---

## `my-leader.el`

### Problem: `C-c u` is ergonomically costly as a primary entry point

**Context:** All custom bindings were rooted under `C-c u`. Two modifier
chords before every command interrupts typing flow and accumulates
physical cost over a day of editing. The goal was a single, home-row
trigger that works everywhere.

---

### Leader key mechanism: `key-chord` with double-space

**Chosen:** `key-chord` package, chord `"  "` (double-space), bound to `my-leader-map`.
`C-c u` retained as a universal fallback pointing to the same map.

**Why `key-chord` over the alternatives:**

- Fully self-contained in the Emacs config — one package, version-controlled,
  no OS-level steps or external tooling required.
- Works identically on macOS, Linux, and Windows.
- Works over SSH — space is a plain character that transmits reliably through
  any terminal connection, unlike modifier keys.
- Double-space is easy to hit while keeping hands on the home row.

**Why double-space as the chord:**

It is fast, ergonomic, and does not require a modifier. The tradeoff is that
intentional double-spaces in prose may trigger the leader, but the config is
optimized around editing and command entry rather than preserving literal
double-space typing.

**Why `C-c u` is kept:**

Acts as a universal fallback for machines where `key-chord` isn't
installed yet, minimal configs, and any environment where the package
isn't available. Both entry points share a single `my-leader-map` —
adding a binding once makes it available via either key.

**Alternatives considered:**

- **Custom `key-translation-map` implementation** — intercepted `f` via
  `key-translation-map` and used `read-event` with a timeout to detect
  `fj`. Rejected: blocked on every `f` keypress for 0.3 seconds, making
  the editor unusable. The timeout fallback also emitted `fj` instead of
  just `f` on a lone keypress. Correctly reimplementing this would have
  meant rebuilding `key-chord` from scratch.
- **OS-level remapping (Karabiner / AutoHotkey / keyd)** — remap Caps
  Lock or a combo to `F13` or a Hyper modifier, then bind in Emacs. Best
  ergonomics on machines you control. Rejected as primary solution:
  creates a per-machine dependency outside the config, breaks the
  portability goal across macOS/Linux/Windows, and doesn't work over SSH.
- **Caps Lock as Hyper modifier** — popular community solution, frees an
  entire `H-*` namespace. Same portability problem as OS-level remapping.
  Additionally, Hyper doesn't transmit reliably over SSH through most
  terminal emulators, so remote sessions would silently break.
- **Function keys (`F5`, `F8`, etc.)** — completely free in vanilla
  Emacs, one keypress, works everywhere. Rejected on ergonomic grounds:
  top of keyboard, away from the home row. Also unreliable on modern
  MacBooks where function keys are behind an `Fn` layer or replaced by
  the Touch Bar.
- **`C-;` as single-chord leader** — better than `C-c u`, one chord,
  free by default. Not rejected outright, but still requires a modifier
  held down, so doesn't fully solve the ergonomic goal. Also: `flyspell`
  claims `C-;` if ever enabled.
- **Hydra / Transient** — modal keymap packages. Press a trigger, enter
  a temporary mode, press single keys to execute commands. Deferred, not
  rejected — identified as the right tool when enough bindings accumulate
  that discoverability becomes a problem. Not a replacement for what
  `my-leader.el` provides.

---

### Key mapping architecture

**Chosen:** A single `my-leader-map` keymap. Both double-space (via `key-chord`)
and `C-c u` (via standard `keymap-global-set`) are bound to this same
map object.

**Why a shared map:** Adding a binding once (`(my-leader-define "f g" #'consult-ripgrep)`)
makes it reachable via either entry point automatically. No duplication,
no synchronization required.

**`key-chord` guarded at startup:** Loading is wrapped in `condition-case`, so
`my-leader.el` still provides `C-c u` even if `key-chord` fails to load. This
is consistent with the error resilience principle — the leader fallback remains
usable rather than blocking startup.

---

## `my-ai.el` (implemented)

### gptel + agent-shell

**Status:** Implemented. gptel chosen as the primary LLM package. agent-shell
added for interactive Claude Code and Codex sessions.

**gptel** — installed via `:vc` from GitHub. Four backends auto-registered
when API keys are available: OpenAI, Anthropic Claude, OpenRouter
(openai-compatible), and Ollama (local). Auth uses env vars with
auth-source fallback. Streaming enabled on all backends.

**agent-shell** — installed for interactive coding-agent sessions. Provides
`my-ai-claude` (Claude Code via ACP) and `my-ai-codex` (Codex via ACP).
Auth delegates to each CLI tool's native login flow.

**Architectural constraint met:** The AI layer is swappable across backends,
supports multiple providers simultaneously, and does not pollute editing
modules or require UI dependencies. All config lives in `my-ai.el`.

**Emacs-Harness integration:** gptel also serves as a provider type inside
Emacs-Harness via `eh-model-providers-gptel.el`. The harness retains prompt
construction, decision validation, policy, and routing. gptel handles LLM
transport only.

---

## `my-mail.el`

### mu4e from system package manager

**Chosen:** mu4e is loaded from Homebrew/site-lisp rather than ELPA/MELPA.
`init.el` marks `mu4e` as a built-in package version so package-vc dependencies
can resolve cleanly.

**Why:** mu4e ships with the `mu` system package. Keeping the Elisp side paired
with the installed `mu` binary avoids version skew and mirrors how this should
work on Nix later.

---

### Mail retrieval outside Emacs, manual refresh inside Emacs

**Chosen:** mbsync handles retrieval, `mu index` handles indexing, and msmtp
handles sending. The launchd template and `scripts/mail-sync` support periodic
sync outside Emacs; `my-mail-sync-now` provides an in-Emacs manual refresh.

**Why:** Mail sync should not depend on whether Emacs is open, but Emacs still
needs an easy "refresh now" command during mail triage.

---

### mu4e dashboard plus org-msg

**Chosen:** `mu4e-dashboard` provides the dashboard/sidebar workflow, while
`org-msg` handles composing HTML-capable messages from Org. `mu4e-org` stays
enabled for linking mail into Org tasks and notes.

**Why:** This keeps the reading/navigation surface, compose surface, and
task-linking surface separate. The dashboard is a mail home base; org-msg is
only about authoring; mu4e-org keeps durable links into the Org system.

---

### `consult-mu` deferred

**Decision:** Do not add `consult-mu` yet. Keep it as a future option for fast,
from-anywhere mail lookup.

**Why:** The useful part would be `consult-mu-async` for quickly finding one
message or thread without entering the full mu4e dashboard. However, the
current dashboard/org-msg/mu4e-org workflow is still settling, and consult-mu
is a GitHub-only package whose README describes edge cases around mu4e window
management. If revisited, start with a minimal `:vc` setup, conservative
preview settings, and no attachment/contact extras on day one.

---

## Packages Not Chosen (and why)

| Package | Reason skipped |
|---------|----------------|
| auto-dark | Failed to detect macOS appearance reliably. Replaced by built-in `ns-system-appearance-change-functions`. |
| Custom `key-translation-map` leader | Blocked every `f` keypress for 0.3s; timeout fallback emitted `fj` instead of `f`. Would have meant rebuilding `key-chord` from scratch. |
| Caps Lock → Hyper modifier | Per-machine OS dependency; Hyper doesn't transmit reliably over SSH. |
| consult-mu | Deferred. Potentially useful for async "find one email" lookup, but not needed while the mu4e dashboard workflow is still settling. |
| OS-level remapping (Karabiner / keyd) | Per-machine dependency, breaks portability goal, doesn't work over SSH. |
| Hydra / Transient (as leader replacement) | Deferred, not rejected. Right tool when binding count makes discoverability a problem. |
| Helm | Monolithic, ecosystem lock-in. |
| Ivy / Counsel / Swiper | Monolithic, less composable than Vertico stack. |
| lsp-mode | Heavier than Eglot, not built-in. May revisit if Eglot proves insufficient. |
| Flycheck | Redundant with Eglot's Flymake integration. |
| undo-tree | Known data corruption issues with persistence. vundo is safer. |
| straight.el | Adds complexity. `package.el` + `use-package` is sufficient for now. |
| Doom / Spacemacs | Frameworks — goal is to build understanding first. |

---

## Deferred Decisions

| Topic | Status |
|-------|--------|
| `my-ai.el` | Implemented. gptel + agent-shell. See decision above. |
| `my-ops.el` | No concrete need identified yet. |
| Journaling workflow | Capture and ID scaffolding in place. Specific workflows deferred. |
| consult-mu | Maybe later for fast async mail search from anywhere; start minimal if revisited. |
| elpaca migration | Future upgrade path from `package.el` once config stabilizes. |
| `inhibit-redisplay` | Can be re-added to `early-init.el` once startup restoration is battle-tested. |
| Linux / Windows OS module polish | Basic OS modules exist; deeper per-platform tuning deferred until needed. |
