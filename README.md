# GitHub Inbox

A native macOS port of the Herdr **GitHub Inbox** panel. It is designed to look and behave like the Herdr mod while running as an independent window that AeroSpace can tile beside an editor or terminal.

The app uses SwiftUI and AppKit directly: no Electron, WebView, Node.js, Tauri, or Herdr runtime is required. GitHub access goes through the authenticated [GitHub CLI](https://cli.github.com/), and the app stores no credentials.

## Features

- Herdr palette, JetBrains Mono typography, SVG icons, row selection, tabs, and compact rail.
- Titled header with the current tab's qualified search query and PR count, plus a persistent shortcut/footer bar with the last refresh time.
- Configurable GitHub search tabs with one or more queries per tab.
- Mine, review-requested, and custom list views.
- PR stacks, review groups, repository headers, checks, review status, and unread comments.
- Keyboard navigation, context actions, refresh, folding, and persistent UI state.
- Open, copy, approve with a review message, merge with confirmation, mark ready, and assign.
- Searchable multi-select label and reviewer pickers.
- Automatic 60-second refresh that preserves previous results when a query fails.

## Requirements

- macOS 14 or newer.
- Swift 5.9 or newer; full Xcode is not required.
- GitHub CLI (`gh`) with an authenticated account.

Verify the prerequisites:

```sh
swift --version
gh auth status
```

## Install with Homebrew

```sh
brew tap abelfubu/tap
brew trust abelfubu/tap
brew install --cask gh-inbox
```

Homebrew installs the `gh` dependency automatically. The release apps are universal (Apple Silicon and Intel), ad-hoc signed, and not notarized; macOS may require **right-click → Open** on first launch.

## Build and run

```sh
cd ~/dev/gh-inbox
swift run
```

Build an ad-hoc-signed app bundle:

```sh
./scripts/build-app.sh --open
```

The bundle is written to `dist/GitHub Inbox.app`.

For a distributable universal release, run `./scripts/package-release.sh 0.1.0` (universal packaging requires full Xcode; normal app builds only need Command Line Tools). This verifies the app signature and architectures, then writes `dist/GitHub-Inbox-0.1.0.zip` and its SHA-256 checksum. Pushing a matching `v0.1.0` tag runs the release workflow and uploads both assets to GitHub.

Install it for Finder and Spotlight:

```sh
pkill -x GitHubInbox || true
ditto "dist/GitHub Inbox.app" "/Applications/GitHub Inbox.app"
codesign --verify --deep --strict "/Applications/GitHub Inbox.app"
open "/Applications/GitHub Inbox.app"
```

`GH_PATH` overrides the `gh` executable. Otherwise the app searches `PATH`, Homebrew, `~/.local/bin/gh`, and `/usr/bin/gh`.

## App icon

The app icon uses the Herdr palette with a PR glyph, inbox tray, and unread indicator. Its editable source is `Assets/AppIcon.svg`; generated outputs are `Assets/AppIcon.icns` and `Assets/AppIcon.png`. The app build copies the icon into `Contents/Resources` and declares it in `Info.plist`.

After editing the SVG, regenerate all macOS icon sizes:

```sh
./scripts/build-icon.sh
./scripts/build-app.sh
```

Regeneration requires `rsvg-convert` from `librsvg` and macOS's built-in `iconutil`. The generated `.icns` is kept with the source so normal app builds do not need `librsvg`.

## Configuration

The app reads `~/.config/gh-inbox/config.json`, creates defaults if the file is missing, and reloads it on every refresh. See [`config.example.json`](config.example.json) for a complete example.

```json
{
  "sections": [
    {
      "id": "mine",
      "label": "Mine",
      "icon": "pr",
      "view": "mine",
      "queries": ["author:@me"],
      "labels": { "3": "label:mine" }
    },
    {
      "id": "review",
      "label": "Review",
      "icon": "eye",
      "view": "review",
      "queries": ["review-requested:@me -author:@me"]
    },
    {
      "id": "team",
      "label": "Team",
      "icon": "pr",
      "view": "list",
      "queries": ["author:teammate", "author:another-teammate"]
    }
  ],
  "labels": {
    "4": "label:urgent"
  }
}
```

Section fields:

- `id`: unique lowercase identifier using `a-z`, digits, and `-`.
- `label`: visible tab label.
- `queries`: one or more GitHub search queries; results are deduplicated.
- `query`: single-query alternative to `queries`.
- `view`: `mine`, `review`, or `list`.
- `icon`: bundled Herdr icon name, such as `pr` or `eye`.
- `icons`: ordered compact-rail icon fallbacks using `pr`, `eye`, `custom`, or `stack`; the first valid icon is used.
- `labels`: digit-to-`label:` mappings for direct `1`–`9` tab selection.

Top-level `labels` supplies defaults; section mappings override matching digits. Digits above the visible tab count are ignored.

The app appends `is:pr is:open archived:false` to every query. Legacy `customTabs` arrays are accepted and appended to `sections`. The selected tab and folded groups persist between launches. Below 160 px wide, the header, shortcut footer, and tab strip are replaced by Herdr's compact icon rail.

### Colors

The optional `colors` object accepts `#RRGGBB` or `#RRGGBBAA` values. Omitted colors keep their defaults; unknown names and invalid values are ignored. The default app and icon background is `#0D1117`.

```json
{
  "colors": {
    "background": "#0D1117",
    "surface": "#161B22",
    "accent": "#2F81F7"
  }
}
```

Supported names: `background`, `chrome`, `surface`, `raised`, `hover`, `selected`, `border`, `foreground`, `muted`, `dim`, `accent`, `green`, `red`, `yellow`, `orange`, and `purple`. Changes apply on refresh. `background` also updates the native window behind the SwiftUI content.

### Font

The optional `font` key accepts an installed font family name. It applies to both interface and monospace text on refresh; omitted or blank values restore **JetBrains Mono**. Use `"System"` for San Francisco.

```json
{
  "font": "Geist Mono"
}
```

### Shortcuts

The optional `shortcuts` object maps action IDs to arrays of bindings. Omitted actions retain their defaults, multiple bindings are allowed, and an empty array disables an action.

```json
{
  "shortcuts": {
    "nextPR": ["j", "down"],
    "previousPR": ["k", "up"],
    "nextTab": ["l", "]", "cmd-g"],
    "refresh": ["cmd-r", "r"]
  }
}
```

Use `cmd`, `shift`, `alt`/`option`, and `ctrl`/`control` prefixes, such as `cmd-shift-o`. Special keys are `enter`, `escape`, `space`, `up`, `down`, `left`, `right`, and `tab`. Uppercase single letters such as `K` are shorthand for `shift-k`. Bindings apply on refresh and update native menu commands and visible shortcut hints.

Numbered tabs use `1`–`9` by default. Override them with `tab1` through `tab9`, for example `"tab3": ["cmd-3"]` or `"tab4": []` to disable one. `labels` validates the corresponding `label:N` action aliases.

Action IDs: `nextPR`, `previousPR`, `previousTab`, `nextTab`, `openSelected`, `actions`, `cancel`, `fold`, `refresh`, `copy`, `diff`, `merge`, `approve`, `ready`, `assign`, `labels`, `openConfig`, `closeWindow`, `nextOption`, `previousOption`, `toggleOption`, `submitForm`, and `submitApproval`.

## Keyboard and mouse

The table below lists the **default** bindings.

These shortcuts apply while GitHub Inbox is the active app; they are not global hotkeys.

Drag across displayed PR text to select it, then press **Cmd+C** to copy. Single-clicking elsewhere on a PR row still selects that PR; form fields keep their native text editing and copy/paste behavior.

| Key | Action |
|---|---|
| `j` / `k` | Next / previous PR, or next / previous action |
| `h` / `l`, `[` / `]` | Previous / next tab |
| `⌘G` | Next tab |
| `⌘[` / `⌘]` | Previous / next tab |
| `1`–`9` | Select the corresponding visible tab |
| `Enter` | Open the selected PR, run an action, or submit a picker |
| `o` / `Shift-K` | Open PR actions |
| `Escape` | Close actions/forms or clear selection |
| `f` | Fold the selected review group or PR stack |
| `r` / `⌘R` | Refresh and reload config |
| `y` | Copy PR URL |
| `d` | Open the PR diff in Herdr + Neovim Diffview |
| `m` | Merge with confirmation |
| `a` | Open the approval form |
| `Shift-R` | Mark a draft PR as ready for review |
| `i` | Assign the PR to yourself |
| `Shift-L` | Open the multi-select label picker |
| `⌘⇧O` | Open JSON config |
| `⌘W` | Close the window |

Single-click selects a PR, double-click opens it, and right-click shows its actions.

### Herdr and Rex Diffview

`d` and **Open diff in Neovim** create a tab named `PR #N · diff`. When Herdr is running, it uses the **active Herdr space** and inherits the last-focused Herdr terminal's folder. When Herdr is unavailable, it opens a new window (tab) in your **Rex session** instead. Both targets fetch the base and PR head refs, then run `nvim -c "DiffviewOpen origin/BASE...origin/pr/N/head"`. After creating the tab, its exact terminal/block is focused and the target Herdr or Rex app is brought to the foreground. Rex also sends `session.select` to the connected app client with the new `window_id`, because changing only the server’s focused block does not update the Rex UI.

For Rex, the app resolves the session from its environment or `rex whoami`; if exactly one session exists, it selects that session automatically. Set `"rexSession": "session-id-or-label"` when multiple sessions are active. Rex uses a local checkout from the optional `repositories` mapping, then checks `~/dev/<repo>`, `~/code/<repo>`, `~/Projects/<repo>`, `~/work/<repo>`, and `~/src/<repo>`:

```json
{
  "rexSession": "Dashboard",
  "repositories": {
    "owner/repository": "~/dev/repository"
  }
}
```

The target verifies that `origin` matches the PR repository before fetching. A mismatch or missing checkout reports an error instead of opening the wrong diff. Fetching tries the existing `origin` first, then retries through GitHub HTTPS with `gh auth token` if SSH authentication fails; the token is not printed or stored. Neovim must have Diffview installed.

### Approval and multi-select forms

Actions, approval, labels, and reviewer selection open in centered popups over the PR list. Approval uses a multiline editor. Enter inserts a new line; `⌘Enter` or **Approve** submits an optional review message. Escape, the close button, or the backdrop cancels without submitting.

Labels and reviewers use searchable multi-select pickers:

- Type to filter; matching ignores case, diacritics, and repeated whitespace.
- `↑` / `↓` moves the highlighted row.
- **Space** toggles an item; clicking a row also toggles it. When the current text is the start of a matching multi-word option, **Space** continues the search instead.
- Select any number of items, then press **Enter** or the action button to submit.
- **Escape** cancels the form.

After Enter or Escape, focus returns to the PR list and normal shortcuts resume. Reviewer candidates come from `gh api repos/<owner>/<repo>/collaborators`; labels come from `gh label list`.

## Architecture

| File | Responsibility |
|---|---|
| `Sources/GitHubInbox/GitHubInboxApp.swift` | App scene, window sizing, native menu commands, debug test entry points |
| `Sources/GitHubInbox/ContentView.swift` | Herdr-style UI, keyboard handling, focus lifecycle, native UI smoke tests |
| `Sources/GitHubInbox/InboxStore.swift` | Observable application state, refresh coordination, selection, forms, PR actions |
| `Sources/GitHubInbox/GitHubClient.swift` | Authenticated `gh` process execution, GraphQL queries, JSON decoding |
| `Sources/GitHubInbox/Models.swift` | PR/config models and derived review/check status |
| `Sources/GitHubInbox/Config.swift` | Config loading, sections, optional color and shortcut overrides |
| `Sources/GitHubInbox/Labels.swift` | Label/action parsing and `1`–`9` shortcut defaults |
| `Sources/GitHubInbox/Shortcuts.swift` | Action bindings, key parsing, native menu equivalents, shortcut hints |
| `Sources/GitHubInbox/PRGrouper.swift` | Pure stack construction and ordering |
| `Sources/GitHubInbox/InboxAction.swift` | Context action definitions |
| `Sources/GitHubInbox/Theme.swift` | Configurable Herdr colors, hex parsing, font family and typography |
| `Sources/GitHubInbox/InboxIcon.swift` | Bundled SVG rendering with system-symbol fallbacks |
| `Sources/GitHubInbox/WindowConfigurator.swift` | Borderless window and hidden traffic-light chrome |
| `Sources/GitHubInbox/SelfTests.swift` | Deterministic model/config tests |
| `scripts/build-app.sh` | Release build, icon installation, app bundle creation, ad-hoc signing |
| `scripts/build-icon.sh` | Regenerates the complete macOS icon set from `Assets/AppIcon.svg` |

Important implementation invariants:

- Route every GitHub mutation through `InboxStore.perform` so debug dry runs remain safe.
- Use `pr.repository` for repository-specific commands and `pr.id` for stable selection.
- Keep stack and repository-header calculations pure; do not mutate captured state inside SwiftUI `ViewBuilder` loops.
- Preserve `@FocusState` transitions between `.panel` and `.formInput`; form dismissal restores list shortcuts after the old input resigns.
- Preserve existing PR results when a background refresh fails.
- Use bundled Herdr SVG resources and `Theme` colors for visual parity. Route configurable shortcuts through `ShortcutMap` rather than hard-coded key handlers.

## Verification

Build and run the deterministic self-tests:

```sh
swift build
GH_INBOX_SELF_TEST=1 .build/debug/GitHubInbox
# Equivalent: swift run GitHubInbox --self-test
```

Run the native keyboard test:

```sh
GH_INBOX_KEY_SMOKE=1 .build/debug/GitHubInbox
```

Run the multi-select, approval, and focus-lifecycle test without changing any PR:

```sh
GH_INBOX_FORM_SMOKE=1 GH_INBOX_DRY_RUN=1 .build/debug/GitHubInbox
```

The self-tests avoid networking. The native smoke tests launch the real app and use live GitHub reads plus the user's config. Key smoke needs a configured tab with at least two PRs. Form smoke additionally needs at least two available collaborators. `GH_INBOX_DRY_RUN=1` intercepts mutations only in debug builds; it does not disable GitHub reads.

### Visual verification

Capture the app's own rendered content without screen-recording permission:

```sh
GH_INBOX_SCREENSHOT=/tmp/gh-inbox.png \
GH_INBOX_WIDTH=380 GH_INBOX_HEIGHT=800 \
.build/debug/GitHubInbox
```

Capture a form:

```sh
GH_INBOX_SCREENSHOT=/tmp/gh-inbox-approve.png \
GH_INBOX_FORM=approve GH_INBOX_WIDTH=420 GH_INBOX_HEIGHT=430 \
.build/debug/GitHubInbox
```

`GH_INBOX_FORM` also accepts `actions`, `labels`, and `reviewers`. Use `actions` to capture the centered PR action popup. Form screenshots perform GitHub reads but do not submit.

For UI changes, inspect the screenshot and verify keyboard/focus behavior in the running app in addition to compilation.

## Troubleshooting

- **`gh` is unavailable or authentication fails:** run `gh auth status` in a shell, then restart the app. Set `GH_PATH` when the executable is elsewhere.
- **A custom tab is empty:** test its query with `gh search prs`; the app automatically adds open, non-archived PR filters.
- **Changes do not appear in Finder:** rebuild with `./scripts/build-app.sh`, replace `/Applications/GitHub Inbox.app`, and reopen it.
- **Font or icons differ from Herdr:** confirm JetBrains Mono is installed and the app bundle contains `Contents/Resources/GitHubInbox_GitHubInbox.bundle`.

## Acknowledgments

The interface and SVG assets are based on Herdr's `gh-inbox` mod. Review asset licensing before publishing a public redistribution.
