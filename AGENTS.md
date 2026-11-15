# AGENTS.md

## Mission

Maintain a native macOS port of Herdr's `gh-inbox` panel. The target is **Herdr visual and keyboard parity in a standalone window**, not a generic GitHub client. Herdr is not a runtime dependency.

Read `README.md` for setup, configuration, shortcuts, architecture, and verification commands. Keep it current whenever behavior, configuration, shortcuts, or test entry points change.

## Working sequence

1. Reproduce the issue or identify the exact Herdr behavior being ported. Read the relevant Swift source and, when available, the reference mod at `~/.config/herdr-app/mods/gh-inbox/`.
2. Make the smallest coherent change. Preserve the public config shape and existing shortcuts unless the user requests a change.
3. Add deterministic model coverage for parsing, grouping, or state logic. Extend native smoke coverage for keyboard, focus, or form behavior.
4. Run the required verification below. For visual changes, capture and inspect the app's own rendered view.
5. When the task includes updating the installed app, build the release bundle, replace `/Applications/GitHub Inbox.app`, verify its signature, reopen it, and confirm the installed process is running.

Completion requires both a successful build and the relevant behavioral checks; compilation alone is insufficient.

## Safety

- Route every GitHub mutation through `InboxStore.perform`; this is the single debug dry-run boundary.
- Use `GH_INBOX_FORM_SMOKE=1 GH_INBOX_DRY_RUN=1 .build/debug/GitHubInbox` for mutation-flow verification. Never approve, merge, edit, assign, label, or request reviewers on a real PR merely to test the app.
- Treat `~/.config/gh-inbox/config.json` as user-owned runtime data. Tests may read it; use fixtures for config changes instead of rewriting the user's file.
- Keep GitHub reads scoped with `pr.repository` and stable PR identity based on `pr.id`.
- The dry-run guard exists only in debug builds. Release verification must not use live mutation as a test strategy.

## Herdr parity invariants

- Use `Theme` colors, JetBrains Mono typography, and bundled Herdr SVG icons. Match spacing, selection, stacking, folding, and compact-rail behavior to the reference mod.
- Preserve default shortcut behavior: `j/k` navigate, `h/l` and brackets switch tabs, `1`–`9` select configured tabs, `o` opens actions, `f` folds, `r` refreshes, and Escape closes the current transient UI before clearing selection. Route every binding through `ShortcutMap`; optional config overrides must not fork the native menu and view handlers.
- Preserve one keyboard focus owner. Forms own `.formInput`; the PR list owns `.panel`. PR/action shortcuts stay inactive while a form is active; only shared window, tab, refresh, and cancellation bindings remain available.
- Keep displayed PR text selectable and copyable. Do not wrap selectable text in a row-wide `Button`; use a row tap gesture and `.textSelection(.enabled)` so drag selection wins without breaking single-click PR selection.
- Every Enter/Escape/button dismissal path must restore `.panel` after SwiftUI removes the input. Test both submission and cancellation.
- Multi-select forms use Space/click to toggle and Enter to submit all selected items. Approval uses Enter for a newline and Command-Enter to submit.
- Keep stack construction and repository-header decisions pure. Never mutate captured local state from a SwiftUI `ViewBuilder`/`ForEach` to derive layout.
- Preserve previous results across refresh failures and avoid duplicate results across multiple queries.

## Code map

Use the architecture table in `README.md` to locate components. The most common edit points are:

- UI, keyboard, focus, and native smoke tests: `Sources/GitHubInbox/ContentView.swift`.
- State, forms, actions, and refresh: `Sources/GitHubInbox/InboxStore.swift`.
- GitHub transport and decoding: `Sources/GitHubInbox/GitHubClient.swift` and `Models.swift`.
- Stack behavior: `Sources/GitHubInbox/PRGrouper.swift`.
- Config compatibility: `Sources/GitHubInbox/Config.swift`.
- Color overrides and parsing: `Sources/GitHubInbox/Theme.swift`.
- Numbered labels/icons and `tab1`–`tab9` bindings: `Sources/GitHubInbox/Labels.swift` plus `ShortcutMap`.
- Shortcut actions, parsing, menus, and hints: `Sources/GitHubInbox/Shortcuts.swift`.
- App icon source and generation: `Assets/AppIcon.svg` and `scripts/build-icon.sh`; `scripts/build-app.sh` installs the generated `.icns`.
- Deterministic tests: `Sources/GitHubInbox/SelfTests.swift`.

Prefer pure helpers for parsing, grouping, and derived state so they remain testable without AppKit or network access.

## Required verification

From the repository root:

```sh
swift build
GH_INBOX_SELF_TEST=1 .build/debug/GitHubInbox
GH_INBOX_KEY_SMOKE=1 .build/debug/GitHubInbox
GH_INBOX_FORM_SMOKE=1 GH_INBOX_DRY_RUN=1 .build/debug/GitHubInbox
```

Form smoke is DEBUG-only and now sets `GH_INBOX_DRY_RUN=1` internally as defense in depth. Never remove that guard or run mutating form tests without dry-run.

For a release/install task:

```sh
./scripts/build-app.sh
pkill -x GitHubInbox || true
ditto "dist/GitHub Inbox.app" "/Applications/GitHub Inbox.app"
codesign --verify --deep --strict "/Applications/GitHub Inbox.app"
open "/Applications/GitHub Inbox.app"
pgrep -fl '/Applications/GitHub Inbox.app/Contents/MacOS/GitHubInbox'
```

For version publishing, follow [Create a release](README.md#create-a-release) and [Homebrew publishing](docs/homebrew-publishing.md). Only new `v<major>.<minor>.<patch>` tags trigger the GitHub release and automatic Homebrew cask update.

The native smoke tests require real GitHub reads and suitable configured data. If their fixtures are unavailable, report that limitation precisely rather than claiming they passed. UI work also needs a screenshot using `GH_INBOX_SCREENSHOT`; see `README.md` for form captures and sizing variables.

## Change discipline

- Keep the app dependency-free beyond Swift/AppKit and the user's authenticated `gh` executable.
- Keep debug/test hooks out of release behavior.
- Update `config.example.json` and `README.md` with config changes, and `README.md` with shortcut changes.
- After icon edits, run `./scripts/build-icon.sh`, inspect `Assets/AppIcon.png`, and verify the bundled `Contents/Resources/AppIcon.icns` plus `CFBundleIconFile` in `Info.plist`.
- Do not declare a redistribution license for Herdr-derived assets without confirming their upstream terms.
