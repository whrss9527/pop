<div align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Pop icon">
  <h1>Pop</h1>
  <p><strong>Hold right click. Flick. Done.</strong></p>
  <p>A right-click toolbox that lives in the macOS menu bar. Native Swift, glass UI, free and open source.</p>
  <p>
    <a href="https://github.com/whrss9527/pop/releases"><img alt="Latest release" src="https://img.shields.io/github/v/release/whrss9527/pop?include_prereleases&label=release&color=5B7BFF"></a>
    <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-111827?logo=apple&logoColor=white">
    <img alt="Liquid Glass" src="https://img.shields.io/badge/UI-Liquid%20Glass-7C6CFF">
    <a href="LICENSE"><img alt="GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-2563EB"></a>
  </p>
  <p><b>English</b> · <a href="README.zh-CN.md">简体中文</a></p>
  <p>
    <a href="https://github.com/whrss9527/pop/releases"><b>Download</b></a> ·
    <a href="CHANGELOG.md">Changelog</a> ·
    <a href="plugins/README.md">Plugin library</a>
  </p>
</div>

### **Pop** /pɒp/

Hold down the right mouse button and a bubble pops up next to the pointer. Flick toward where you want to go, let go, and the bubble pops — the job is done.

In English, **pop** means both *to appear suddenly* and the light sound a bubble makes when it bursts. That is the kind of interaction Pop is after: light, direct, and out of the way as soon as you're done.

Pop's interface is available in English and Simplified Chinese and follows your system language (System Settings → General → Language & Region).

## Highlights

- **Hold right click to open it**: a short click still opens the context menu. Only a long press brings up Pop, so right-dragging in games and 3D apps keeps working.
- **One flick and it's done**: arrange 80+ actions on the ring any way you like; flick toward a slot and let go to run it.
- **It knows what you selected**: text in another language is translated, math is calculated, units and colors are converted, and images are read with OCR — right away.
- **Add your own actions**: turn URLs, shell scripts, JavaScript or Shortcuts into plugins, or install one from the plugin library with a click.
- **Handy tools**: clipboard history, pinning to the screen, screenshot annotation, color picker and screen ruler, plus AI polish, summary and explanations.
- **Your data stays with you**: Pop has no servers. Clipboard history stays on your Mac and API keys stay in the keychain.

## Installation

Download the latest `Pop-<version>.zip` from [Releases](https://github.com/whrss9527/pop/releases), unzip it and drag `Pop.app` into the Applications folder (every release note also lists the steps). Builds that aren't notarized by Apple need this in Terminal before the first launch:

```bash
xattr -dr com.apple.quarantine /Applications/Pop.app
```

Builds made on GitHub don't include iCloud sync (it needs signing with your own paid developer account; see [iCloud sync](#icloud-sync) under Development). Everything else works.

### One-click updates

Pop checks for updates directly on this repository's GitHub Releases; there's no separate update server:

- With “Check for updates automatically” on (the default), Pop checks at launch and every 6 hours after that. You can also check any time in Settings → Update or from the menu bar icon. Beta versions (pre-releases) are included by default; you can turn that off in Settings.
- When there's a new version, Pop sends a notification and the menu bar icon turns into a download arrow. Settings → Update shows the release notes; you can update right away or skip that version.
- When you click Update Now, Pop:
  1. downloads `Pop-<version>.zip` and `SHA256SUMS.txt` and verifies the SHA-256 checksum;
  2. unzips it and checks the bundle ID, the version and that the code signature is intact;
  3. if the current version is signed with a certificate, requires the new version to be signed with **the same certificate**, and refuses to install otherwise;
  4. replaces Pop.app (asking for an administrator password if the folder isn't writable) and restarts. Settings, plugins and clipboard history are stored elsewhere and aren't affected.
- If you opened Pop straight from the Downloads folder, the update installs it into Applications and moves the old copy to the Trash.

> Ad-hoc signed builds get a different signature with every version, so macOS treats the updated Pop as a different app and its Accessibility permission stops working: Pop's switch in System Settings still looks on, but has no effect. In that case click Reset Old Permission in Pop's Settings → General and grant it again. Builds signed with a fixed certificate don't have this problem; see [Signing and notarization](#signing-and-notarization).

## Features

Pop is a macOS menu bar productivity tool. **Hold down the right mouse button** in any app and Pop reads what you've selected:

- Text in another language: a translation card appears right away (System Translation by default: offline and free; you can switch to AI or DeepL, or compare several side by side).
- Math, measurements, color values or images: Pop calculates the result, converts the units, converts the color notation or recognizes the text in the image.
- Anything else (or nothing selected): the **ring**, a radial menu, appears. Keep holding, flick toward a slot and release to run that action; release in the center to close it. (You can also have the ring stay open after you release and then click.)

Which actions are installed, which slot each one takes, and which kind of content runs which action directly are all up to you in Settings. Besides 80+ built-in actions, you can **write your own plugins** with URL templates, shell scripts, JavaScript or Shortcuts, or install ready-made ones from the **plugin library** with a click. Pop also has a **clipboard history** (stored only on your Mac and cleaned up after the time you choose), and you can **pin** screenshots, images and text on top of all windows for reference. Select text and have **AI** polish, summarize or explain it, or ask a question: on macOS 26 you can use the built-in system model (runs on your Mac, no setup), or enter your own AI API. Settings and plugins can **sync through iCloud** to your other Macs, and new versions download from GitHub and **update in one click** inside the app.

| Area | Details |
| --- | --- |
| Triggers | Hold right click (default; a short click still opens the context menu), modifier + right click, middle click, or a global shortcut. Every action can also have its own global shortcut that runs it on the current selection. You can also turn on “Show a toolbar after selecting text”: after drag-selecting or double-clicking a word, a row of common actions appears above the selection (off by default; can be excluded per app) |
| Reading the selection | Accessibility API → the app's Copy menu item → a simulated ⌘C, three levels of fallback. The clipboard is backed up and restored, and the alert sound is muted while keys are simulated |
| Content detection | Chinese / other languages, single words, links, email addresses, JSON, math, measurements (5 km, 100°F, 2 斤, 16 GB…), numbers (including 0x/0b/0o), colors (#RGB, rgb(), hsl()), dates and times, Unix timestamps, local paths, files and images |
| Ring | 4–12 slots, with a separate ring per app if you like. Hold and flick toward a slot, release to run it, release in the center to close (or keep it open after release and click). Number keys 1–9/0 pick a slot directly, arrow keys + Return work too, Esc closes it. Near a screen edge the whole ring shifts inward and the pointer moves to its center, so flick directions stay the same |
| Interface | Glass look (Liquid Glass on macOS 26). The ring springs open from the pointer, the highlight slides around it, and result cards grow out from the pointer's corner. With Reduce Motion on, only fades are used |
| Built-in actions | See the table below; each one can be turned off |
| Custom plugins | URL template / shell script / JavaScript / Shortcuts. One JSON file per plugin; create, test run, import and export them in Settings |
| Shortcuts | Two actions, “Process Text with Pop” and “Translate with Pop”, pass results to the next step; see [Shortcuts](#shortcuts) |
| Links | Shortcuts, launchers and scripts can call Pop with `pop://` links: run an action on some text or the current selection, open the ring, clipboard history or Settings; see [Links](#links) |
| Plugin library | Browse and search plugins made by others in Settings → Actions → Plugin Library and install them with a click (sha256 is checked after downloading). It starts with 10: GitHub search, Douban, Juejin, MDN, Stack Overflow, Zhihu, Bilibili, Wikipedia, npm and Can I use |
| Snippets | Save text you use often and pick one from the ring to paste it into the current app. Placeholders such as {date}, {clipboard} and {selection} are supported, and the clipboard is restored afterwards |
| Clipboard history | Keeps text, images and files. Search (including text in images, recognized on your Mac), filter by type, pin items, paste quickly with ⌘1–9, and ⌘-click several items to paste them together. Tracking parameters can be removed from copied links automatically. Right-click to translate text, save it as a snippet, recognize text in an image, annotate an image or pin it to the screen. Stored in a local SQLite database and cleaned up by age and item limit |
| Result cards | Copy, **Replace** (paste back into the original app), copy row by row; QR code images, color swatches, red/green text diffs, and generated code you can switch between languages. Translations can be pinned to the screen |
| Shelf | Hold a few files for a while, then drag them elsewhere together or one by one. Put files on it from the ring, drag them onto it, or shake while dragging files to make it appear next to the pointer |
| Pins | Pin screenshots, selected images or text on top of all windows: drag to move, scroll or pinch to zoom, hold ⌥ and scroll to change opacity; ⌘C copies, ⌘S saves to Downloads, right-click to recognize text or annotate, double-click or Esc closes. The menu bar can close all pins at once |
| Rules | Choose which action runs directly, skipping the ring, for each kind of content (defaults: other languages → Translate, math → Calculate, measurements → Convert Units, colors → Convert Color, images → Recognize Text) |
| AI | Select text and have AI polish, summarize, explain or translate it, or ask a question. Answers stream in and can be copied, used to replace the selection, or pinned to the screen. On macOS 26, on Macs that support Apple Intelligence, you can use the built-in system model (runs on your Mac, offline, no setup), or enter an API compatible with OpenAI Chat Completions in Settings → AI (model servers running on your Mac work too). Selected text is sent only when you use an AI action, and the API key stays in this Mac's keychain |
| iCloud sync | Ring layouts (including per-app rings), installed actions, custom plugins, rules, triggers and action shortcuts, translation, clipboard and AI API settings (except the API key), stored in your own iCloud key-value storage. You can also export them to a file in Settings → Sync and import it on another Mac (works in builds without iCloud sync too) |
| Updates | Reads GitHub Releases directly (beta versions optional). After downloading, Pop verifies the SHA-256 checksum and code signature before replacing Pop.app and restarting. New versions are announced with a notification and a download arrow on the menu bar icon, without interrupting you; after updating, the first launch sends a notification about what’s new |

### Built-in actions

| Category | Actions |
| --- | --- |
| Text | Translate (System Translation, AI translation and DeepL, with a side-by-side comparison; replace the selection, switch the target language, read the translation aloud), Dictionary (the system Dictionary), Vocabulary (add words from translation and dictionary cards, review them, export to CSV or a file Anki can import), Speak, Search, Save Web Page (save the whole page at the selected URL as one long PDF or a long image in Downloads, or just the article text as Markdown), Text to Image (lay out the selected text as a long image 1080 pixels wide, on a white, cream or dark background), Copy as Plain Text, Spell Check (built into macOS, offline), Text Statistics, Clean Up Text (join lines, remove blank lines and extra spaces, add spaces between Chinese and Latin text, full-width to half-width, remove invisible characters such as zero-width spaces, Simplified ↔ Traditional Chinese, Pinyin, sort lines and remove duplicates), Extract Info (links, email addresses, phone numbers and IP addresses in a piece of text), ID Numbers (Chinese resident ID numbers, unified social credit codes and bank card numbers: checks the check digit and reads out the birth date, age, sex, region and registration authority, offline), Lines (quote and comma-separate a list, convert to a JSON array, add or remove numbering, reverse, shuffle, split a comma-separated line into lines), Add to Reminders (understands Chinese time phrases such as “明天下午 3 点” (tomorrow at 3 pm) or “周五之前” (by Friday) and adds a reminder or calendar event), Compare Text (compares the selection with the clipboard and marks deleted and added words), Snippets, Inbox (appends to “Documents/Pop 收集箱.md”) |
| Convert | Case (camelCase, snake_case, kebab-case…), Encode (Base64, URL, Unicode, HTML entities), Numbers (bases, thousands separators, RMB in words), Convert Units (length, weight, temperature, volume, area, speed, data size and transfer rate, including Chinese units such as 斤, 两, 亩 and 里), Color (HEX / RGB / HSL / SwiftUI, with contrast on white and black and a light-to-dark scale), Contrast of two colors (WCAG AA / AAA), Time (timestamp ↔ date, with the Chinese lunar date and week number), Date Difference (days, weeks and months between two dates, and how many are workdays), Convert to Markdown (formatted text from web pages and documents, keeping tables, code blocks and task lists), Markdown Table of Contents (from headings, with anchors), Format / Minify JSON, YAML ↔ JSON (key order preserved), Format / Minify XML, Format SQL (one clause per line, or all on one line), Calculate, Number Statistics (sum, average, median, max and min of a list of numbers) |
| Developer | Hash (MD5, SHA-1, SHA-256, SHA-512 of text or files), QR Code (generate one, or a Code 128 barcode for letters and digits; or read QR codes and barcodes in an image), Base64 Image (show it as an image, or copy an image as a data URI), Random (UUID, password, number), Parse Link (split out parameters, remove tracking parameters, expand short links), Decode JWT, Regex Tester (live highlighting of matches and groups, try replacements), Cron (explains the expression in words and lists the next runs), Code Screenshot (syntax highlighting, gradient background), copy Markdown as rich text or preview it, Convert Table (table / CSV / Markdown table / JSON), JSON to Code (TypeScript, Swift, Go and Kotlin type definitions), Character Info (Unicode code point, name and encoding of each character; finds invisible characters) |
| Screen & Images | Recognize Text in images (offline OCR), Screenshot OCR, Translate Screenshot, Recognize Table (on macOS 26, reads rows and columns and converts them to a Markdown table, CSV or tab-separated text), Scan Code (select a QR code or barcode on screen; Wi-Fi QR codes show the password), Annotate Screenshot (arrows, boxes, text, pixelation, numbered markers, with an optional gradient background and shadow), Record Screen (drag out an area, click a window or record the whole screen to MP4; can record the Mac's sound or the microphone and show clicks, and the recording can be turned into a GIF), Pin, Remove Background (keeps only the subject, offline), Stitch Images (stack several images vertically or horizontally into one long image, or make an animated image), Image Colors (main colors and their values), Pick Color, Screen Ruler (measure distances between interface elements and the size of an area) |
| Files | Copy Path, File Info (size, number of files, dates, image dimensions, PDF page count, audio and video duration; for photos, the camera, aperture, shutter speed, time and place they were taken), Show in Finder, Open With (choose an app for a file or link), Open in Terminal, AirDrop (files, images, links, text), Send to Phone (scan a QR code with your phone to open a temporary web page that downloads the selected files, images or text, and uploads files from the phone to your Mac's Downloads folder; the phone and Mac just need to be on the same Wi-Fi, and Android phones work too), Convert Images (PNG / JPEG / HEIC, half size, compress or compress under a given size, rotate, flip, remove location or all capture info from photos; saved next to the original), Watermark (images and PDFs; tiles semi-transparent text diagonally across them), ID Photo (white, blue or red background, cropped around the face to the small 1-inch, 1-inch, large 1-inch, small 2-inch or 2-inch Chinese ID photo sizes at 300 dpi; can also save a print layout for 6-inch photo paper; processed on your Mac), Crop Image (crop to 1:1, 4:3, 3:4, 16:9 or 9:16, centered on the subject; saved as a copy), Redact (find faces, phone numbers, email addresses, ID and bank card numbers and license plates in images and pixelate them; saved as a copy without capture info or location), Convert Video (to GIF or MP4, compress to 720p, extract audio, or a contact sheet of 16 evenly spaced frames), Trim (cut a range of audio or video by start and end time), Transcribe (turn speech in recordings and videos into text and SRT subtitles saved next to the original; Mandarin, English, Cantonese and Japanese, recognized on your Mac when it supports it; on macOS 26 it uses the system's new transcription, which handles long recordings in full), Batch Rename (numbering, find and replace, prefixes and suffixes, by capture date, change case; preview first and undo afterwards), Folder Tree (as a tree or Markdown list), Find Duplicates (files with identical contents in folders; keep one of each and move the rest to the Trash), Disk Usage (drill into a folder to see what takes the most space and list the largest files), Lines of Code (files and lines per language), Compare Folders (files only on one side, and files that differ), Compare Files (the lines and words that changed between two text files), Compress to zip, Unzip, PDF (combine images and PDFs into one PDF, save each page as an image, copy all text, extract pages, split into single pages, add or remove a password, compress), Shelf |
| Windows & System | Window Layout: move the current window to the left or right half, top or bottom half, a third, maximize, center, or move it to another display (arrow keys and Return work too); Keyboard Shortcuts (list every shortcut in the current app's menus, search them or all menu items, and click one to run it); Keep Awake (30 minutes, 1 hour, 2 hours or indefinitely; stop it from the menu bar any time); Timer (plays a sound and sends a notification when time is up); System Actions (lock the screen, turn off the display, sleep, screen saver, hide or show desktop icons, eject all disks) |
| AI | AI Assistant (ask a question, or polish, summarize, explain or translate); AI Polish, AI Summary and AI Explain (not installed by default; turn them on in Settings → Actions to put them on the ring and run them with a flick) |
| Other | Clipboard history, All Actions (searchable), open Settings |

Chinese-specific tools such as Simplified ↔ Traditional conversion, Pinyin, RMB in words, Chinese units and Chinese ID numbers work the same in the English interface; only their names are translated.

## Custom plugins

Create one from a template in Settings → Actions → My Plugins, or put a JSON file straight into the plugins folder (`~/Library/Application Support/Pop/Plugins`) and Pop loads it automatically. A plugin looks like this:

```json
{
  "id": "user-github",
  "name": "GitHub Search",
  "symbol": "magnifyingglass",
  "summary": "Search GitHub for the selected text",
  "localized": { "zh-Hans": { "name": "GitHub 搜索", "summary": "在 GitHub 上搜索选中的文字" } },
  "match": { "kinds": ["text"], "pattern": null },
  "action": { "type": "url", "template": "https://github.com/search?q={text}" },
  "output": "none"
}
```

| Field | Description |
| --- | --- |
| `id` | Plugin ID, also the file name. Letters, digits, `.`, `-` and `_` only, and it can't match a built-in action. You can leave it out in hand-written files; the file name is used instead |
| `name` / `symbol` / `summary` | The name, [SF Symbol](https://developer.apple.com/sf-symbols/) icon name and description shown on the ring and in lists |
| `localized` | Optional names and descriptions in other languages, keyed by language code: `{"en": {"name": "GitHub Search", "summary": "…"}, "zh-Hans": {"name": "GitHub 搜索"}}`. When Pop's interface is in that language (a regional code such as `zh-Hant-HK` falls back to `zh-Hant`, then `zh`), they replace `name` and `summary`; otherwise `name` and `summary` are shown |
| `match.kinds` | Kinds of content it handles: `text`, `foreignText`, `chineseText`, `word`, `url`, `email`, `json`, `number`, `measurement`, `color`, `dateTime`, `timestamp`, `math`, `files`, `imageFile`, `image`. Empty means always available |
| `match.pattern` | Optional regex that the selected text (or file path) must match |
| `action.type` | `url`: open a URL, with `{text}` replaced by the URL-encoded text and `{raw}` by the original text. `shell`: run `script` with zsh; the text comes in on standard input and in `$POP_TEXT` and `$POP_FILES`. `javascript`: run `script` in JavaScriptCore; define `function run(input, files)` and return the result. `shortcut`: pass the text to the shortcut named `shortcut`. `ai`: send the instructions in `prompt` together with the selected text to the service in Settings → AI; `{text}` is replaced with the selection (without it, the text is appended to the prompt), and results shown on a card stream in as they're generated |
| `action.timeout` | Maximum run time of a script in seconds; it's stopped after that (not used by AI prompts) |
| `output` | What to do with the script's result: `card` result card, `copy` copy, `replace` replace the selected text, `toast` brief message, `none` nothing |

All fields are parsed leniently: missing or invalid values fall back to defaults, so exchanging plugins between old and new versions never fails outright. Like ring layouts, plugins can sync through iCloud, and you can send the JSON file to someone else to import.

### Plugin library

Settings → Actions → Plugin Library lists the plugins in this repository's [`plugins`](plugins) folder (`index.json` records each plugin's name, description, author, download URL and sha256). Search them and click Install to download one; it's put in your plugins folder only if its sha256 matches. When a plugin in the library gets a new version, installed copies show Update. If GitHub can't be reached, a mirror is used automatically, and plugins that run shell scripts show you the script before installing. To share your own plugin, add it to the `plugins` folder and to `index.json` as described in [plugins/README.md](plugins/README.md), then open a pull request.

## Links

| Link | What it does |
| --- | --- |
| `pop://run?plugin=textStats&text=Hello` | Runs an action on this text; the result appears next to the pointer. `plugin` is the action's ID: right-click an action in Settings → Actions (for your own plugins, use the “…” menu) and choose Copy Link to get the full link |
| `pop://run?plugin=translate` | Without `text`, handles the current selection, like an action shortcut |
| `pop://run?plugin=revealInFinder&file=/Users/me/a.pdf` | Handles files; `file` can be given several times |
| `pop://translate?text=Hello` | Translates this text (short for `pop://run?plugin=translate`) |
| `pop://ring`, `pop://clipboard` | Opens the ring at the pointer, or the clipboard history |
| `pop://settings`, `pop://settings/translation` | Opens a Settings page (`general`, `ring`, `plugins`, `rules`, `hotKeys`, `clipboard`, `translation`, `ai`, `sync`, `update`) |
| `pop://plugin-library` | Opens the plugin library |

For example, run `open "pop://translate?text=Hello"` in Terminal, or use Open URLs in Shortcuts. Text with spaces, non-ASCII characters or symbols such as `&` must be encoded first (use URL Encode in Shortcuts); links from Copy Link are already encoded. Text from a link wasn't selected in any app, so its result card has no Replace button; actions that are turned off can still run from links. When a link would pass text to one of your own shell script or Shortcuts plugins, Pop asks first, so a link on a web page can't run scripts for you.

### Shortcuts

Links make Pop do things but can't return results. To pass a result to the next step, use Pop's two actions in the Shortcuts app (on macOS 26 they also work straight from Spotlight):

| Action | What it does |
| --- | --- |
| Process Text with Pop | Choose an action (built-in actions that handle text, and your own plugins), give it some text, and get the result back: what Copy would copy on the result card, or the full AI answer |
| Translate with Pop | Translates text with AI or DeepL into the language you choose; without an engine, the default one from Settings → Translate is used. System Translation only works on the translation card; in Shortcuts you can use the built-in Translate Text action |

Actions that need Pop's own interface (clipboard history, batch rename and so on) report in Shortcuts that they can't return a result.

## How it works (key points)

**How does holding right click leave normal right clicks alone?** macOS opens the context menu the moment the button goes down, so Pop uses a `CGEventTap` to hold back the right-button-down event and start a timer:

```
Right button down → hold it back, start the timer (250 ms by default, adjustable)
 ├─ released before the timer ends → re-post down + up in order → the context menu opens as usual
 ├─ dragged more than 6 pixels     → re-post the down event and let the drag through (right-dragging in games and 3D apps is unaffected)
 └─ timer ends                     → this press belongs to Pop: read the selection → translation card or ring
```

Re-posted events are marked and pass straight through when they come back to the tap. Because the down event never reaches the target app, the right click doesn't change the selection there either.

**Why don't the floating panels steal focus?** The ring and cards are `nonactivatingPanel`s: the original app stays frontmost, the selection isn't lost, and the simulated ⌘C doesn't go to Pop itself. Replace depends on this too: Pop hides the panel first so keyboard focus naturally returns to the original app, then writes the clipboard, simulates ⌘V and restores the clipboard afterwards.

## Where data is stored

| Data | Location | Sync |
| --- | --- | --- |
| Settings (ring, rules, triggers…) | `UserDefaults` (`io.github.whrss9527.pop`) | iCloud key-value storage |
| Custom plugins | `~/Library/Application Support/Pop/Plugins/*.json`, one file per plugin | iCloud key-value storage |
| Clipboard history | `~/Library/Application Support/Pop/Clipboard/history.sqlite` (WAL mode); images are stored as PNG files in the `Images` folder next to it. Text recognized in images is also stored in the database for searching | Not synced; stays on this Mac |
| Inbox | `~/Documents/Pop 收集箱.md` | Follows your Documents folder |
| Vocabulary | `~/Library/Application Support/Pop/Vocabulary.json` | Not synced; can be exported |
| Files sent from a phone (Send to Phone) | `~/Downloads`; duplicate names get 2, 3… appended | Not synced |

Clipboard history is deduplicated by content (copying the same thing again just moves it to the top). Items older than the retention period or beyond the item limit are cleaned up every hour; pinned items are kept. Sensitive content that password managers mark with types such as `org.nspasteboard.ConcealedType` is never recorded, and you can exclude specific apps in Settings.

## Known limitations

- Pop needs Accessibility permission, and because the App Store sandbox doesn't allow Accessibility, it can only be distributed through its website / GitHub.
- Ad-hoc signed release builds need Accessibility permission granted again after every one-click update; builds signed with a fixed certificate don't (see [Signing and notarization](#signing-and-notarization)).
- A few apps neither support reading the selection through Accessibility nor have a Copy menu item; Pop then simulates ⌘C. Simulated keystrokes may be wrong with non-QWERTY keyboard layouts.
- Replace and pasting from clipboard history simulate ⌘V, so they have no effect where the selection isn't editable.
- Screenshot OCR, Translate Screenshot, Scan Code, Annotate Screenshot and Screen Ruler need Screen Recording permission; without it, captures may show only the desktop background.
- Record Screen needs Screen & System Audio Recording permission too; after allowing it the first time, reopen Pop before recording. It records either the Mac's sound or the microphone, not both at once.
- The first time you use Transcribe, allow Speech Recognition. On-device recognition needs Dictation turned on (System Settings → Keyboard → Dictation); languages this Mac can't recognize on its own are sent to Apple's servers, and very long recordings may be only partly transcribed.
- Save Web Page opens the page in Pop itself, without your browser's sign-ins, so a page that needs you to sign in is saved as the sign-in page. Pages whose content scrolls inside its own area (such as some web apps) are saved as only the first screen.
- The first time you use Add to Reminders, allow Pop to access Reminders or Calendar (Calendar only needs write access). Development builds you sign yourself need the `com.apple.security.personal-information.calendars` entitlement (already set up in the project).
- The clipboard has no change notifications, so Pop checks it every 0.5 seconds; if you copy several times within that time, only the last one is recorded.
- System Translation can read stiffly for long paragraphs. Switch to AI translation or DeepL on the translation card (set up AI or enter a DeepL API key first).
- The Send to Phone page only opens on the same local network: it doesn't work on Wi-Fi that isolates devices (offices, hotels), or when the firewall's “Block all incoming connections” is on. The URL contains a random token, and the page stops working when you stop sharing or after 10 minutes without access.

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

Most needs are covered by [custom plugins](#custom-plugins) without changing code. To add a built-in action, implement the `PopPlugin` protocol (`Pop/Plugins/Plugin.swift`), declare the kinds of content it handles, add an ID to `BuiltinPluginID` and add it to `BuiltinPlugins.make()` (existing users get new built-in actions installed automatically after upgrading). Remember to add English translations for its name, summary and messages:

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

## Buy me a coffee

Pop is free and open source. If you find it useful, you can buy me a coffee by scanning this WeChat code ☕ (it's also in the app under Settings → Update; click it to enlarge).

<p align="center"><img src="Pop/Resources/donate-wechat.png" width="300" alt="WeChat tip code: buy me a coffee"></p>

## License

Copyright © 2026 whrss9527

Pop is free software, released under the [GNU General Public License version 3 (GPL-3.0)](LICENSE): you may use, study, modify and share it freely. If you distribute Pop or a modified version, you must provide the source code under the same license.

The name “Pop” and Pop's icon are not covered by the GPL (GPL-3.0 section 7(e)). You may use them to talk about Pop and to share unmodified copies; if you distribute a modified version, please use your own name and icon.

Contributions are subject to the contributor agreement in [CONTRIBUTING.md](CONTRIBUTING.md).

---

<div align="center">
  <p><b>Also living in the menu bar</b></p>
  <a href="https://github.com/whrss9527/meno"><img src="https://raw.githubusercontent.com/whrss9527/whrss9527/master/assets/cards/meno.svg" width="30%" alt="Meno: a quiet menu bar, made of glass"></a>
  <a href="https://github.com/whrss9527/stox"><img src="https://raw.githubusercontent.com/whrss9527/whrss9527/master/assets/cards/stox.svg" width="30%" alt="Stox: markets at a glance, hidden in a click"></a>
  <a href="https://github.com/whrss9527/proxi"><img src="https://raw.githubusercontent.com/whrss9527/whrss9527/master/assets/cards/proxi.svg" width="30%" alt="Proxi: one switch for all your proxies"></a>
</div>
