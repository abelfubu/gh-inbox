# Publishing GitHub Inbox with Homebrew

GitHub Inbox is distributed as a **Homebrew Cask**, because it installs `GitHub Inbox.app` rather than a source-built command-line formula.

## Published distribution

- Source: `https://github.com/abelfubu/gh-inbox`
- Tap: `https://github.com/abelfubu/homebrew-tap`
- Cask: `Casks/gh-inbox.rb`
- Release tag: `v0.1.0`
- Archive: `GitHub-Inbox-0.1.0.zip`

Install with:

```sh
brew tap abelfubu/tap
brew install --cask gh-inbox
gh auth login
open -a "GitHub Inbox"
```

The cask depends on macOS 14 or newer and the `gh` formula. The archive contains a universal arm64/x86_64 app. Builds are currently ad-hoc signed, not Developer ID signed or notarized, so macOS may require **right-click → Open** on first launch.

No `LICENSE` is declared until redistribution terms for Herdr-derived assets are confirmed. This does not block the personal tap, but it must be resolved before an official Homebrew Cask submission.

## Release automation

Pushing a semantic-version tag runs `.github/workflows/release.yml` on a macOS runner. The workflow:

1. Builds and runs deterministic self-tests.
2. Builds universal arm64/x86_64 binaries.
3. Verifies the app signature, `Info.plist`, and executable architectures.
4. Creates a ZIP containing `GitHub Inbox.app` at its root and a SHA-256 file.
5. Publishes both assets to the matching GitHub release.

To release locally with full Xcode installed:

```sh
./scripts/package-release.sh 0.1.0
```

Normal development builds only need Command Line Tools; universal packaging uses `xcbuild` from full Xcode. GitHub-hosted macOS runners provide it.

For a later version, set `APP_VERSION`/`BUILD_NUMBER` as appropriate, tag the release, and update the cask:

```sh
cd ~/dev/homebrew-tap
./scripts/update-cask.sh gh-inbox 0.1.1
```

The update script downloads the exact public archive, updates its version/checksum, and checks Ruby syntax. Review, commit, and push the cask change.

## Cask verification

```sh
brew audit --cask --online --strict Casks/gh-inbox.rb
brew install --cask Casks/gh-inbox.rb
open -a "GitHub Inbox"
brew uninstall --cask gh-inbox
```

The cask's optional `zap` stanza removes `~/.config/gh-inbox` only when a user explicitly runs `brew uninstall --zap`.

## Developer ID and notarization

For a smoother public installation experience and possible Homebrew Core acceptance, sign releases with a Developer ID Application certificate, enable the hardened runtime, notarize with Apple, staple the ticket, and verify with `spctl`. Store credentials only in encrypted GitHub Actions secrets or a local notarization Keychain profile; never commit them.

Sign nested helpers/frameworks before the outer app if any are added. Build the final distribution ZIP only after notarization and stapling, then use that final ZIP's SHA-256 in the cask.

## Official Homebrew Cask submission

The personal tap works without Homebrew maintainer approval. Before submitting to `Homebrew/homebrew-cask` later:

- Confirm redistribution licensing and third-party notices.
- Publish stable, signed/notarized releases with permanent URLs.
- Check current notability and acceptance requirements.
- Run `brew audit --new --cask` and `brew style`.
- Test install, launch, upgrade, and uninstall on a clean machine.
- Follow the current upstream contribution guide.

Homebrew policies can change; use the current official documentation at submission time.
