# Publishing GitHub Inbox with Homebrew

This document describes how to distribute GitHub Inbox to other macOS users through Homebrew.

## Distribution choice: Cask, not formula

Use a **Homebrew Cask**. GitHub Inbox is a native macOS application installed as `GitHub Inbox.app`; a formula is more appropriate for software that Homebrew builds from source and exposes primarily as a command-line tool.

The recommended distribution path is:

1. Publish the source and a signed macOS release on GitHub.
2. Create a personal Homebrew tap for immediate distribution.
3. Submit the Cask to `Homebrew/homebrew-cask` once the project and release process are stable.

## Current project status

Before the first public release, the project still needs the following:

- `/Users/abelfubu/dev/gh-inbox` is not yet a Git repository.
- No `LICENSE` file is present.
- The current build is arm64-only.
- The current app is ad-hoc signed, not Developer ID signed or notarized.
- `CFBundleShortVersionString` is `0.1.0`, but there is no corresponding public tag or release archive.

The package currently requires macOS 14 or newer and the authenticated GitHub CLI (`gh`). Herdr, Rex, Neovim, and Diffview are optional integrations and must not be required for basic inbox use.

## 1. Publish the source

Create a public repository such as `abelfubu/gh-inbox` and publish the project source.

Before pushing:

- Choose and add an open-source `LICENSE`.
- Add attribution and third-party notices required for Herdr-derived code, icons, colors, or other assets.
- Keep generated `.build/` and `dist/` output out of Git.
- Add Homebrew installation instructions to `README.md` once the tap works.
- Add a screenshot and a short standalone description of the application.
- Document that GitHub authentication is performed with `gh auth login`; the app invokes `gh` and does not store its credentials.

The public source should include the app sources, resources, package manifest, build scripts, configuration example, tests, and generated app icon needed by normal builds.

## 2. Prepare release builds

The first release should use a tag such as `v0.1.0`, matching `CFBundleShortVersionString` in the app bundle. Increment `CFBundleVersion` for every submitted build.

Provide either:

- **One universal ZIP** containing an arm64 + x86_64 binary; this gives the simplest Cask.
- **Separate arm64 and Intel ZIPs**; the Cask then needs per-architecture URLs and checksums.

A universal build can be produced with SwiftPM's arm64 and x86_64 architecture options. Update `scripts/build-app.sh` to support the chosen release architecture and verify the resulting executable with `lipo -info` or `file`. Do not publish the current arm64-only artifact as though it supported Intel Macs.

The release archive should contain `GitHub Inbox.app` at its root. A suitable universal artifact name is:

```text
GitHub-Inbox-0.1.0-macos.zip
```

Before packaging, run the normal checks:

```sh
swift build
GH_INBOX_SELF_TEST=1 .build/debug/GitHubInbox
./scripts/build-app.sh
codesign --verify --deep --strict "dist/GitHub Inbox.app"
```

## 3. Sign and notarize the app

Ad-hoc signing is sufficient for local development but produces a poor installation experience for other users. Public releases should be signed with a **Developer ID Application** certificate, use the hardened runtime, and be notarized by Apple.

This requires:

- An Apple Developer Program membership.
- A Developer ID Application signing identity installed in the build machine's keychain.
- Notarization credentials stored in a Keychain profile, for example `gh-inbox-notary`.

An example local signing and notarization flow is:

```sh
APP="dist/GitHub Inbox.app"
VERSION="0.1.0"
IDENTITY="Developer ID Application: Your Name (TEAM_ID)"

codesign --force --options runtime --timestamp \
  --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# Submit an archive for notarization.
ditto -c -k --keepParent "$APP" "dist/GitHub-Inbox-$VERSION-notarization.zip"
xcrun notarytool submit "dist/GitHub-Inbox-$VERSION-notarization.zip" \
  --keychain-profile "gh-inbox-notary" --wait

# Staple the ticket, then create the archive users will download.
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
ditto -c -k --keepParent "$APP" "dist/GitHub-Inbox-$VERSION-macos.zip"

spctl --assess --type execute --verbose=2 "$APP"
shasum -a 256 "dist/GitHub-Inbox-$VERSION-macos.zip"
```

If nested helper executables or frameworks are added later, sign them individually before signing the outer app bundle rather than relying on recursive signing.

Keep signing identities, notarization passwords, API keys, and keychain passwords out of Git.

## 4. Publish the GitHub release

Create a tag whose version matches the app, attach the final notarized ZIP, and publish release notes. For example:

```sh
gh release create v0.1.0 \
  "dist/GitHub-Inbox-0.1.0-macos.zip" \
  --title "GitHub Inbox 0.1.0" \
  --generate-notes
```

Record the final ZIP's SHA-256. The Cask must use the checksum of the exact public download artifact, not the temporary notarization archive.

## 5. Create a personal Homebrew tap

Create a public repository named `abelfubu/homebrew-gh-inbox` with this layout:

```text
homebrew-gh-inbox/
├── Casks/
│   └── github-inbox.rb
└── README.md
```

For a universal release archive, `Casks/github-inbox.rb` can start as:

```ruby
cask "github-inbox" do
  version "0.1.0"
  sha256 "RELEASE_ZIP_SHA256"

  url "https://github.com/abelfubu/gh-inbox/releases/download/v#{version}/GitHub-Inbox-#{version}-macos.zip"
  name "GitHub Inbox"
  desc "Native macOS GitHub pull-request inbox"
  homepage "https://github.com/abelfubu/gh-inbox"

  depends_on macos: ">= :sonoma"
  depends_on formula: "gh"

  app "GitHub Inbox.app"

  zap trash: "~/.config/gh-inbox"
end
```

The `zap` stanza is optional and destructive when explicitly requested by the user: it removes the app's configuration directory during `brew uninstall --zap`.

Validate and test the Cask before asking others to install it:

```sh
brew audit --cask --online --strict Casks/github-inbox.rb
brew install --cask Casks/github-inbox.rb
open -a "GitHub Inbox"
brew uninstall --cask github-inbox
```

After pushing the tap, users can install the app with:

```sh
brew tap abelfubu/gh-inbox
brew install --cask github-inbox
gh auth login
open -a "GitHub Inbox"
```

The one-command equivalent is:

```sh
brew install --cask abelfubu/gh-inbox/github-inbox
```

## 6. Automate releases

Add a GitHub Actions release workflow on a macOS runner. It should:

1. Check out the tagged source.
2. Run the build and self-tests.
3. Build the selected universal or per-architecture app bundles.
4. Import the Developer ID certificate into a temporary keychain.
5. Sign, notarize, and staple the app.
6. Recreate and checksum the final distribution ZIP.
7. Upload the ZIP to the matching GitHub release.
8. Update the personal tap, or make the version/checksum update easy to apply.

Use encrypted GitHub Actions secrets for certificate and notarization credentials. Delete temporary keychains and avoid printing secrets in logs.

## 7. Submit to the official Homebrew Cask repository

A personal tap does not require acceptance by the Homebrew maintainers and is the quickest distribution option. Official inclusion comes later.

Before opening a pull request against `Homebrew/homebrew-cask`:

- Confirm that `github-inbox` is an available and appropriate Cask token.
- Publish a stable, versioned GitHub release with a permanent download URL.
- Provide a signed and notarized app for a smooth installation experience.
- Check the current Homebrew acceptance and notability requirements.
- Run the current new-Cask audits and style checks, including `brew audit --new --cask` and `brew style`.
- Test installation, launch, upgrade, and uninstall on a clean machine.
- Follow the repository's current contribution guide when opening the pull request.

Homebrew's policies can change, so use the current official documentation and contribution checks at submission time rather than relying on this document for exact acceptance thresholds.

## Releasing later versions

For every new version:

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion`.
2. Run tests and release checks.
3. Create the matching Git tag.
4. Build, sign, notarize, staple, and archive the app.
5. Publish the release ZIP and notes.
6. Update the Cask's `version` and `sha256`, including separate values for each architecture when applicable.
7. Install and test through Homebrew before announcing the update.

For an official Cask, Homebrew's `brew bump-cask-pr` tooling can automate version updates once the Cask exists.

## First-release checklist

- [ ] Public source repository created.
- [ ] License and third-party notices added.
- [ ] README prepared for public users.
- [ ] Universal or separate Intel artifact strategy chosen.
- [ ] Version `0.1.0` and build number verified.
- [ ] Tests and app bundle verification pass.
- [ ] Developer ID signing and Apple notarization pass.
- [ ] Final ZIP checksum recorded.
- [ ] GitHub `v0.1.0` release published.
- [ ] Personal tap and `github-inbox` Cask created.
- [ ] Cask audit, install, launch, and uninstall tested.
- [ ] Release automation added.
- [ ] Official `homebrew/cask` submission considered after stabilization.
