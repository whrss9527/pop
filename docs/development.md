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

**Sandbox build** (in preparation for the Mac App Store, which requires App Sandbox): `POP_SANDBOX=1 scripts/build-app.sh 99.0.0 build/sandbox` builds Pop2, Pop with App Sandbox on (`Pop/Resources/Pop-Sandbox.entitlements`); its name, process name and bundle ID (`io.github.whrss9527.pop2`) differ from Pop, so it can sit next to the installed Pop with its own Accessibility permission. Pushing to a `claude/app-store*` branch or running `.github/workflows/sandbox-check.yml` by hand checks on a runner that it runs in the sandbox, lists what the sandbox blocks at launch, and uploads a `Pop2` zip to try the Accessibility features on your own Mac.

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
PluginBundles/  plugin bundles: each folder builds into its own .bundle (PopXxx.bundle), downloaded from the release when installed
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

### Plugin bundles

Pop's features are moving into plugin bundles one by one. Each plugin bundle builds into its own `.bundle` that isn't part of the Pop download: it's fetched from this version's release when the user installs it in Settings → Actions → Plugins, and uninstalling deletes it along with its preferences. Pop itself keeps only the most common actions (translation, search, dictionary, clipboard…).

- **Code**: `PluginBundles/<folder>/`, starting with `@testable import Pop` so it can use Pop's types directly. The entry point is a class that implements `PopPluginBundle` (`Pop/Plugins/PluginBundles.swift`) with a fixed name given by `@objc(PopXxxEntry)`: `makePlugins()` returns the actions it provides, `didLoad(_:)` registers hooks into Pop (windows to leave out of screen recordings, demo scenes for the CI screenshots) and `willUninstall()` closes anything it has open. Pop's own code never refers to types inside a plugin bundle.
- **Project**: add a target with `templates: [PopPlugin]` to `project.yml`, named Pop plus the folder name, set `POP_PLUGIN_ID` (the plugin ID) and `POP_PLUGIN_ENTRY` (the entry class name) and add it to the scheme. Also add the folder to the `PopTests` sources so the unit tests can test the plugin code directly, and add the entry class to `bundles` in `PopTests/TestCatalog.swift`.
- **Catalog**: add an entry to `Pop/Plugins/PluginCatalog.swift` with the plugin ID, file name, name and summary, the actions it provides and the preferences to delete when it's uninstalled. The settings page lists plugins that aren't installed from it, and when existing users upgrade, the moved actions they use are installed automatically (`AppSettings.adoptPluginBundles`).
- **Build**: a plugin bundle only works with the Pop it was built with, because Swift has no stable module interface here. `scripts/build-app.sh` writes "version+commit" into `PopBuildID` of both Pop and its plugins, puts the plugins next to Pop.app and signs them with the same certificate. So that plugins can find Pop's symbols, Pop keeps testability on in Release and strips only local symbols.
- **Release**: `scripts/package-plugins.sh` zips each plugin bundle as `plugin-<ID>.zip` and writes the plugin list `plugins-<version>.json` (file names, SHA-256, sizes, build ID). The release workflow uploads them to the release together with Pop and notarizes them when signing with Developer ID.
- **Install**: Pop downloads the plugin list and the archive, checks the SHA-256, the build ID and the signature (if Pop is signed with a certificate, the plugin must be signed with the same one), unzips it into `~/Library/Application Support/Pop/PluginBundles` and loads it right away without a restart. After Pop updates, installed plugins are replaced with the matching versions automatically.
- **Try it locally**: when running from Xcode the plugins sit next to Pop.app; set `POP_PLUGIN_DIR` to that folder to load them too. Point `POP_PLUGIN_SOURCE` at a folder with the output of `package-plugins.sh` to use it as the release and go through download and installation. The CI launch test does both.
- **Publishing on their own**: a plugin bundle can also ship without a new Pop version. Put a `plugin.json` in its folder (`id`, `version`, `zh-Hans` and `en` names and summaries, `symbol`, `category`, `functions`, and the `defaultsKeys`, `keychainAccounts` and `dataFolders` to delete on uninstall); packaging copies it into the plugin list, and Pop lists plugins it doesn't know about from it. Its interface text lives in its own `en.lproj/Localizable.strings` (the code looks it up with `bundle:`, and `check-localization.py` checks it there), and its action IDs are its own constants rather than entries in `PluginCatalog`. Once merged into main, the Plugins workflow (`scripts/publish-plugins.sh`) rebuilds these plugins on the tag of the latest release with their code dropped in (so the build ID matches the release), has the released Pop load them and install one by itself, then uploads them to that release and merges them into its plugin list; in pull requests it only checks. To publish a change to a plugin that's already out, bump its `version`: Pop downloads the new one in the background and uses it the next time it opens. Pop rereads the plugin list when Settings opens and at launch when the copy it keeps is more than 6 hours old. Plugins published this way can only use Pop code that's already in the latest release, and they're rebuilt along with the next Pop release.

### Releasing a new version

Changes accumulate under `## Unreleased` (or `## 未发布`) at the top of `CHANGELOG.md`. Set `MARKETING_VERSION` in `project.yml` to the next stable version when starting a new cycle. Every main push that passes the full CI publishes `<version>-beta.<CI run number>`; new installations receive stable versions by default.

To publish a stable version, rename the top section to that version and date, matching `MARKETING_VERSION`. CI publishes at most one stable release per weekday in Asia/Shanghai. If today's allowance is used or it is a weekend, weekday CI retries. Manual stable releases use the same rules; rebuilding an existing tag does not count as a new release. Drafts become public only after all assets are uploaded. Release notes also list changed plugin bundles and their versions relative to the previous stable release.

Plugin-only updates keep using the Plugins workflow on the latest stable tag. They do not need a new Pop stable version. To publish a beta manually:

```bash
make release VERSION=0.69.0-beta.1 BETA=1
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

### Plugin startup

`PluginBundles.loadInstalled()` is asynchronous. Signature checks run on a background queue; bundle code and registration stay on the main actor, with queued main-thread work processed between bundles. Concurrent startup requests await the same task. `AppDelegate` awaits completion before constructing `AppController`, retaining incoming URLs and reopen requests until it is ready. Shortcuts await the same loader before reading their function catalog. Build and signature validation remain mandatory; startup and screenshot checks retain their two-second responsiveness limit.
