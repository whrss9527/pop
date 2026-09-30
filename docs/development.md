# Developing Pop

[← Back to the README](../README.md) · [简体中文](guide.zh-CN.md)

## Development

Requires macOS 15+ and Xcode 16+ (Xcode 26 recommended).

```bash
brew install xcodegen
cp Config/Local.xcconfig.example Config/Local.xcconfig   # fill in your DEVELOPMENT_TEAM
make open                                                # generate Pop.xcodeproj and open it in Xcode
```

After running from Xcode:

1. Turn on Pop in System Settings → Privacy & Security → Accessibility when prompted.
2. Select some text in another language in any app and hold right click to see the translation card.
3. The first time you translate a language pair, download the offline languages in Settings → Translate as the card suggests.

> **Always sign with a fixed development certificate** (set `DEVELOPMENT_TEAM` in `Local.xcconfig`). With ad-hoc signing (“-”), macOS treats every rebuild as a new app and the Accessibility permission stops working; you then have to click Reset Old Permission in Pop's Settings → General (or remove Pop in System Settings) and grant it again.

**No paid developer account?** Add these two lines to `Config/Local.xcconfig` to develop without the iCloud capability (iCloud sync shows as unavailable):

```
POP_ENTITLEMENTS = Pop/Resources/Pop-NoCloud.entitlements
CODE_SIGN_IDENTITY = -
```

Common commands:

```bash
make build   # build
make test    # run unit tests (content detection, conversions, calculator, ring geometry, settings coding and migration, sync conflicts, plugins and scripts, plugin library, clipboard database, update checks)
make app     # build a Release Pop.app on this Mac (universal, ad-hoc signed) into build/app
make clean
```

On every push, GitHub Actions generates the project on macOS, builds it and runs the tests (`.github/workflows/ci.yml`), checks the translations, then actually launches a Release build and walks through a complete one-click update against a fake local release (a wrong checksum must be rejected, a different signing certificate must be rejected, a valid version must be installed and restarted; tested with both ad-hoc and certificate signing).

### Localization

Pop's development language is Simplified Chinese, and interface text uses the Chinese source text as its key. English translations live in `Pop/Resources/en.lproj/Localizable.strings` (and `InfoPlist.strings` for permission prompts):

- In SwiftUI, `Text("中文")`, `Button("中文")` and similar views look up translations automatically. Other text written in code uses `String(localized: "中文")`.
- After adding or changing interface text, add a line `"中文原文" = "English";` to `en.lproj/Localizable.strings`, then run `scripts/check-localization.py --sync-zh-hans` to update the `zh-Hans` file.
- CI builds with `SWIFT_EMIT_LOC_STRINGS=YES` and runs `scripts/check-localization.py`, which checks that both languages have the same keys and placeholders and that every Chinese string used in the code has an English translation. Missing keys are listed in the log in `.strings` format.
- Unit tests run with the Chinese interface (the scheme's test language is `zh-Hans`).

### iCloud sync

- Uses iCloud key-value storage (`NSUbiquitousKeyValueStore`). Pop has no servers; data lives in the user's own iCloud.
- Requires signing with a paid developer account. `Config/Pop.xcconfig` uses `Pop/Resources/Pop.entitlements`, which includes the iCloud capability, by default.
- When several Macs make changes, the latest one wins. A newly set up Mac adopts the cloud settings on its first sync instead of overwriting them with defaults.
- The iCloud storage identifier is made of the Team ID and bundle ID, so **don't change the bundle ID after releasing**, or existing users' synced data can't be found. Before releasing, change `POP_BUNDLE_ID` in `Config/Pop.xcconfig` to your own.

### Project layout

```
Pop/
├── App/        entry point, wiring (AppController), the full flow of one invocation (PopCoordinator)
├── Core/       pure logic: settings model and persistence, content detection, text conversions, calculator, ring/screen geometry
├── Plugins/    plugin protocol, routing rules (Router), built-in actions, custom plugins (manifest, runners, plugins folder), plugin library
├── AI/         AI API (OpenAI Chat Completions compatible, streaming), built-in system model, AI card, API key in the keychain
├── Annotate/   screenshot annotation: model (arrows, boxes, text, pixelation, markers, background) and window
├── Clipboard/  clipboard history: SQLite storage, clipboard monitoring, history panel
├── System/     event tap (MouseTrigger), global shortcuts, reading the selection, pasting back, permissions, notifications, keep awake, timer
├── UI/         floating panels, ring, result/translation cards, All Actions list, menu bar icon, pins, shelf, screen ruler
├── Settings/   Settings window pages (including the drag-and-drop ring editor and plugin editor)
├── Sync/       iCloud sync
├── Update/     update checks (GitHub Releases), download verification, replace and restart
└── Resources/  Info.plist, entitlements, translations (zh-Hans.lproj, en.lproj)
PopTests/       unit tests
plugins/        plugin library: index (index.json) and plugins that install with a click
Config/         xcconfig (signing, bundle ID)
scripts/        build, signing, notarization, test and translation-check scripts (used by releases and CI)
```

### Extending Pop

Most needs are covered by [custom plugins](guide.md#custom-plugins) without changing code. To add a built-in action, implement the `PopPlugin` protocol (`Pop/Plugins/Plugin.swift`), declare the kinds of content it handles, add an ID to `BuiltinPluginID` and add it to `BuiltinPlugins.make()` (existing users get new built-in actions installed automatically after upgrading). Remember to add English translations for its name, summary and messages:

```swift
struct UppercasePlugin: PopPlugin {
    let info = PluginInfo(id: "uppercase", name: String(localized: "转大写"), symbol: "textformat.size.larger",
                          summary: String(localized: "把选中的文字转成大写"), accepts: [.text], pattern: "[a-z]")

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有文字")) }
        let upper = text.uppercased()
        return .card(ResultCard(title: String(localized: "转大写"), body: upper, copyText: upper, replaceText: upper))
    }
}
```

A `PluginOutcome` can be a result card (`ResultCard` supports multi-row results, images, color swatches and custom buttons), a hand-off to the translation card, a direct replacement of the selection, a brief message, or opening the clipboard history or the All Actions list.

Planned: web-based plugins with their own interface.

### Releasing a new version

Releases are driven by `CHANGELOG.md`; you don't tag by hand:

1. Add a section for the new version at the top of `CHANGELOG.md`, titled with the version and date, e.g. `## 0.4.0（2026-09-29）`. Its content goes into the release notes as is.
2. Push (or merge) the change to main. Once CI passes and there's no `v0.4.0` tag yet, it builds a universal app (Apple silicon / Intel), runs the launch test, packages `Pop-<version>.zip`, generates `SHA256SUMS.txt`, tags the commit and publishes the release. The release is created as a draft and made public only after the assets are uploaded.
3. Macs with Pop installed get the version on their next check and are offered a one-click update.

If you only change CI, docs or tests and don't want a release, don't add a new version to `CHANGELOG.md`. To try a beta with a few people first, run the Release workflow manually on the Actions page and check “as a beta”, or use the GitHub CLI on your Mac (`brew install gh && gh auth login`):

```bash
make release VERSION=0.4.0          # publish a release manually
make release VERSION=0.4.0 BETA=1   # publish a beta (pre-release) manually
```

- The workflow fails if the version was already released; when running it manually, check overwrite to rebuild from the tagged code, replace the assets and update the notes.
- `CFBundleShortVersionString` is the version you enter; `CFBundleVersion` is the Git commit count.
- Versions are compared number by number, and a version with a suffix such as `-beta.1` is older than the same version without one.

### Signing and notarization

Releases are ad-hoc signed by default, with nothing to configure. Add a certificate in the repository's Settings → Secrets and variables → Actions, and every later release is signed with it:

| Signing | What you need | Accessibility permission after an update | First launch |
| --- | --- | --- | --- |
| Ad-hoc (default) | Nothing | Must be granted again after every update | Remove quarantine first |
| Self-signed certificate | Generate one with `make signing-certificate` | Kept | Remove quarantine first |
| Developer ID + notarization | Paid developer account | Kept | Double-click to open |

**Self-signed certificate** (free):

```bash
make signing-certificate    # scripts/create-signing-certificate.sh; files go to ~/.pop-signing
```

Following the instructions the script prints at the end, put the contents of `certificate.p12.base64` into the secret `MACOS_CERTIFICATE_P12` and the contents of `password.txt` into `MACOS_CERTIFICATE_PASSWORD`. **Back up this folder**: Pop signed with a certificate only accepts updates signed with the same certificate. If you lose it, you can only switch to a new one, and installed copies of Pop will need to download the new version manually and grant permission once more.

**Developer ID**: in Keychain Access, export the “Developer ID Application: …” certificate with its private key as a .p12, run `base64 -i certificate.p12 | pbcopy` and put the result into `MACOS_CERTIFICATE_P12`, and the export password into `MACOS_CERTIFICATE_PASSWORD`. Add either set of notarization credentials below and releases are submitted for notarization and stapled automatically:

| Secrets | Description |
| --- | --- |
| `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | App Store Connect API key: the contents of the .p8 file (or its base64), the key ID and the issuer ID (leave empty for individual keys) |
| `NOTARY_APPLE_ID`, `NOTARY_PASSWORD`, `NOTARY_TEAM_ID` | Apple ID, app-specific password (generated at appleid.apple.com) and Team ID |

After switching from ad-hoc to certificate signing, the first update still needs Accessibility permission granted once more; after that it doesn't.
