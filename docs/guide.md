# Pop guide

[← Back to the README](../README.md) · [简体中文](guide.zh-CN.md)

## Installation

Download the latest `Pop-<version>.zip` from [Releases](https://github.com/whrss9527/pop/releases), unzip it and drag `Pop.app` into the Applications folder (every release note also lists the steps). Builds that aren't notarized by Apple need this in Terminal before the first launch:

```bash
xattr -dr com.apple.quarantine /Applications/Pop.app
```

Builds made on GitHub don't include iCloud sync (it needs signing with your own paid developer account; see [iCloud sync](development.md#icloud-sync) under Development). Everything else works.

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

> Ad-hoc signed builds get a different signature with every version, so macOS treats the updated Pop as a different app and its Accessibility permission stops working: Pop's switch in System Settings still looks on, but has no effect. In that case click Reset Old Permission in Pop's Settings → General and grant it again. Builds signed with a fixed certificate don't have this problem; see [Signing and notarization](development.md#signing-and-notarization).

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

### Plugins

Some actions come as separate plugin bundles that aren't part of the Pop download. Install one when you need it under Plugins at the top of Settings → Actions: it downloads from this version's GitHub release in a few seconds and works right away, without a restart. You can also search for it in All Actions on the ring: plugins that aren't installed are listed after the installed actions; click one (or select it and press Return) to install it, and it runs right away if it can handle the current content. Each plugin shows its download size and how much space it takes once installed. Click Uninstall when you no longer need it: the plugin and its settings are deleted, and the action is removed from the ring and from shortcuts. With iCloud sync on, installing and uninstalling sync to your other Macs.

These actions are plugins now (they're also listed in the Built-in actions table below), with more to follow:

| Category | Plugins |
| --- | --- |
| Text | Translate Screenshot, Speak, Save Web Page, Text to Image, Large Type, Clean Up Text, Extract Info, ID Numbers, Lines, Add to Reminders, Spell Check, Compare Text, Inbox |
| Convert | Number Statistics, Case, Encode & Decode, YAML ↔ JSON, Format XML, Format SQL, Convert Table, Markdown Rich Text (Markdown Preview, Copy as Rich Text), Convert to Markdown, Markdown Table of Contents, Date Difference, Numbers, Contrast |
| Developer | Hash, QR Code, Base64 Image, Random, Parse Link, Decode JWT, Regex Tester, Cron Expression, Code Screenshot, JSON to Code, Character Info |
| Screen & Images | Recognize Table, Scan Code, Beautify Screenshot, Remove Background, Convert Images, Stitch Images, Split Image, Compare Images, Make App Icon, Watermark, ID Photo, Crop Image, Redact, Image Colors, Screen Ruler |
| Recording & Presenting | Record Screen, Scrolling Screenshot, Show Keystrokes, Draw on Screen, Camera Bubble, Highlight Pointer, Spotlight, Screen Zoom, Teleprompter |
| Files & System | Folder Tree, Lines of Code, Compare Files, Batch Rename, Zip and Unzip, Open in Terminal, PDF, Convert Video, Trim, Transcribe, AirDrop, Send to Phone, Window Layout, Keyboard Shortcuts, Keep Awake, System Actions, Quit Apps, Uninstall App, App Info, Clean Keyboard, Timer, Folder Tools (Disk Usage, Find Duplicates, Compare Folders), Tidy Folder, New File, File Encoding, Similar Photos |

When you upgrade from an older version, the ones you use (on the ring, with a shortcut, or used recently) are installed automatically; install the others when you need them. After Pop updates, installed plugins are replaced with the matching new versions automatically. Recognize Table in the clipboard history's image menu needs the Recognize Table plugin.

### Built-in actions

| Category | Actions |
| --- | --- |
| Text | Translate (System Translation, AI translation and DeepL, with a side-by-side comparison; replace the selection, switch the target language, read the translation aloud), Dictionary (the system Dictionary), Vocabulary (add words from translation and dictionary cards, review them, export to CSV or a file Anki can import), Speak (or save the speech as an .m4a audio file in Downloads), Search, Save Web Page (save the whole page at the selected URL as one long PDF or a long image in Downloads, or just the article text as Markdown), Text to Image (lay out the selected text as a long image 1080 pixels wide, on a white, cream or dark background), Large Type (show the selected text across the whole screen to show someone a phone number, Wi-Fi password or pickup code), Copy as Plain Text, Spell Check (built into macOS, offline), Text Statistics, Clean Up Text (join lines, remove blank lines and extra spaces, add spaces between Chinese and Latin text, full-width to half-width, remove invisible characters such as zero-width spaces, Simplified ↔ Traditional Chinese, Pinyin, sort lines and remove duplicates), Extract Info (links, email addresses, phone numbers and IP addresses in a piece of text), ID Numbers (Chinese resident ID numbers, unified social credit codes and bank card numbers: checks the check digit and reads out the birth date, age, sex, region and registration authority, offline), Lines (quote and comma-separate a list, convert to a JSON array, add or remove numbering, reverse, shuffle, split a comma-separated line into lines), Add to Reminders (understands Chinese time phrases such as “明天下午 3 点” (tomorrow at 3 pm) or “周五之前” (by Friday) and adds a reminder or calendar event), Compare Text (compares the selection with the clipboard and marks deleted and added words), Snippets, Inbox (appends to “Documents/Pop 收集箱.md”) |
| Convert | Case (camelCase, snake_case, kebab-case…), Encode (Base64, URL, Unicode, HTML entities), Numbers (bases, thousands separators, RMB in words), Convert Units (length, weight, temperature, volume, area, speed, data size and transfer rate, including Chinese units such as 斤, 两, 亩 and 里), Color (HEX / RGB / HSL / SwiftUI, with contrast on white and black and a light-to-dark scale), Contrast of two colors (WCAG AA / AAA), Time (timestamp ↔ date, with the Chinese lunar date and week number), Date Difference (days, weeks and months between two dates, and how many are workdays), Convert to Markdown (formatted text from web pages and documents, keeping tables, code blocks and task lists), Markdown Table of Contents (from headings, with anchors), Format / Minify JSON, YAML ↔ JSON (key order preserved), Format / Minify XML, Format SQL (one clause per line, or all on one line), Calculate, Number Statistics (sum, average, median, max and min of a list of numbers) |
| Developer | Hash (MD5, SHA-1, SHA-256, SHA-512 of text or files), QR Code (generate one, or a Code 128 barcode for letters and digits; or read QR codes and barcodes in an image), Base64 Image (show it as an image, or copy an image as a data URI), Random (UUID, password, number), Parse Link (split out parameters, remove tracking parameters, expand short links), Decode JWT, Regex Tester (live highlighting of matches and groups, try replacements), Cron (explains the expression in words and lists the next runs), Code Screenshot (syntax highlighting, gradient background), copy Markdown as rich text or preview it, Convert Table (table / CSV / Markdown table / JSON), JSON to Code (TypeScript, Swift, Go and Kotlin type definitions), Character Info (Unicode code point, name and encoding of each character; finds invisible characters) |
| Screen & Images | Recognize Text in images (offline OCR), Screenshot OCR, Translate Screenshot, Recognize Table (on macOS 26, reads rows and columns and converts them to a Markdown table, CSV or tab-separated text), Scan Code (select a QR code or barcode on screen; Wi-Fi QR codes show the password), Annotate Screenshot (arrows, boxes, text, pixelation, numbered markers, with an optional gradient background and shadow), Beautify Screenshot (a gradient background, padding, rounded corners and a shadow, optionally filled out to 1:1, 4:3 or 16:9), Pin, Remove Background (keeps only the subject, offline), Stitch Images (stack several images vertically or horizontally into one long image, or make an animated image), Split Image (cut an image into a 3 × 3 or 2 × 2 grid of squares for social posts, three squares side by side, or a long image into pages, numbered in posting order in a folder next to the original), Compare Images (two images side by side, with a swipe divider or a translucent overlay, or with the pixels that differ marked in red and each changed area boxed; copying or saving gives you the current view), Make App Icon (a macOS .icns and an Xcode icon set, a 1024 iOS icon, and a website favicon with the usual PNG sizes from one image; the macOS icon can take the rounded square shape and size of the system's app icons; everything goes into a folder next to the image), Image Colors (main colors and their values), Pick Color, Screen Ruler (measure distances between interface elements and the size of an area) |
| Recording & Presenting | Record Screen (drag out an area, click a window or record the whole screen to MP4; can record the Mac's sound or the microphone, show clicks and keystrokes and count down 3 seconds before starting, and the recording can be turned into a GIF), Scrolling Screenshot (select an area and scroll down while Pop captures it into one long image, keeping toolbars and bottom bars only once; then recognize the text in the whole image if you like), Show Keystrokes (show the shortcuts you press, such as ⌘C and ⇧⌘4, plus Return and the arrow keys at the bottom of the screen for demos and tutorials; pressing one again shows “⌘Z ×3”, and ordinary typing isn't shown), Draw on Screen (draw right on the screen for demos and tutorials with a pen, highlighter, arrows, rectangles and ellipses; hold ⇧ for straight lines and even shapes; strokes can fade after a few seconds or stay while you use the windows underneath, and screen recordings include them), Camera Bubble (show the camera in a small round window in a corner of the screen so you appear in your recordings; drag it, resize it, make it a rounded square or switch cameras), Highlight Pointer (a yellow halo around the pointer that ripples when you click), Spotlight (dims the screen except for a circle around the pointer that follows it), Screen Zoom (magnifies the area around the pointer so small text is easy to read; move the pointer to look around, scroll or press ↑↓ to change the magnification), Teleprompter (the selected script scrolls up slowly at the top of the screen so you can read it to the camera; Space pauses, ↑ and ↓ change the speed, and screen recordings leave it out) |
| Files | Copy Path, File Info (size, number of files, dates, image dimensions, PDF page count, audio and video duration; for photos, the camera, aperture, shutter speed, time and place they were taken), Show in Finder, Open With (choose an app for a file or link), Open in Terminal, AirDrop (files, images, links, text), Send to Phone (scan a QR code with your phone to open a temporary web page that downloads the selected files, images or text, and uploads files from the phone to your Mac's Downloads folder; the phone and Mac just need to be on the same Wi-Fi, and Android phones work too), Convert Images (PNG / JPEG / HEIC, half size, compress or compress under a given size, rotate, flip, remove location or all capture info from photos; saved next to the original), Watermark (images and PDFs; tiles semi-transparent text diagonally across them), ID Photo (white, blue or red background, cropped around the face to the small 1-inch, 1-inch, large 1-inch, small 2-inch or 2-inch Chinese ID photo sizes at 300 dpi; can also save a print layout for 6-inch photo paper; processed on your Mac), Crop Image (crop to 1:1, 4:3, 3:4, 16:9 or 9:16, centered on the subject; saved as a copy), Redact (find faces, phone numbers, email addresses, ID and bank card numbers and license plates in images and pixelate them; saved as a copy without capture info or location), Convert Video (to GIF or MP4, compress to 720p, extract audio, or a contact sheet of 16 evenly spaced frames), Trim (cut a range of audio or video by start and end time), Transcribe (turn speech in recordings and videos into text and SRT subtitles saved next to the original; Mandarin, English, Cantonese and Japanese, recognized on your Mac when it supports it; on macOS 26 it uses the system's new transcription, which handles long recordings in full), Batch Rename (numbering, find and replace, prefixes and suffixes, by capture date, change case; preview first and undo afterwards), Folder Tree (as a tree or Markdown list), Find Duplicates (files with identical contents in folders; keep one of each and move the rest to the Trash), Disk Usage (drill into a folder to see what takes the most space and list the largest files), Tidy Folder (sort the files at the top of Downloads or the selected folder into subfolders by type or by month, or sort photos and videos by the month they were taken; subfolders and unfinished downloads stay put; preview first and undo afterwards), New File (create a text, Markdown, rich text, JSON, HTML, CSV, Python or shell script file in the selected folder or the folder open in Finder, or save the selected text or the text or image on the clipboard as a file), File Encoding (see which encoding and line endings text files use, such as UTF-8, GBK or Big5, and convert them to UTF-8, UTF-8 with a BOM for opening CSV files in Excel, or GBK, with LF or CRLF line endings; undo afterwards), Similar Photos (find burst shots and photos saved twice, resized or recompressed in a folder, keep the sharpest one of each group and move the rest to the Trash), Lines of Code (files and lines per language), Compare Folders (files only on one side, and files that differ), Compare Files (the lines and words that changed between two text files), Compress to zip, Unzip, PDF (combine images and PDFs into one PDF, save each page as an image, copy all text, extract pages, split into single pages, add or remove a password, compress), Shelf |
| Windows & System | Window Layout: move the current window to the left or right half, top or bottom half, a third, maximize, center, or move it to another display (arrow keys and Return work too); Keyboard Shortcuts (list every shortcut in the current app's menus, search them or all menu items, and click one to run it); Keep Awake (30 minutes, 1 hour, 2 hours or indefinitely; stop it from the menu bar any time); Timer (plays a sound and sends a notification when time is up; also a Pomodoro timer that alternates 25 minutes of focus with 5-minute breaks); System Actions (lock the screen, turn off the display, sleep, screen saver, switch between Dark and Light Mode, mute, hide or show desktop icons, show hidden files, eject all disks); Quit Apps (list running apps and how much memory each uses, quit one with a click or force quit it if it doesn’t respond, or quit all the others at once; apps ask before closing unsaved documents); Uninstall App (select an app to find the settings, caches, containers and other files it left in your Library, see how much space each takes, and move them to the Trash together with the app; check only the leftover files to reset the app to a fresh install); App Info (which chips an app is built for, who signed it, whether it is notarized and sandboxed, which permissions it may ask for, what it is built with and where it was downloaded from, ready to copy); Clean Keyboard (lock the keyboard for a minute so you can wipe it without typing anything, brightness and volume keys included; end it with the mouse any time) |
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

Settings → Actions → Plugin Library lists the plugins in this repository's [`plugins`](../plugins) folder (`index.json` records each plugin's name, description, author, download URL and sha256). Search them and click Install to download one; it's put in your plugins folder only if its sha256 matches. When a plugin in the library gets a new version, installed copies show Update. If GitHub can't be reached, a mirror is used automatically, and plugins that run shell scripts show you the script before installing. To share your own plugin, add it to the `plugins` folder and to `index.json` as described in [plugins/README.md](../plugins/README.md), then open a pull request.

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
| Installed plugin bundles | `~/Library/Application Support/Pop/PluginBundles/*.bundle` | Which ones are installed syncs with your settings; each Mac downloads the plugins from the release |
| Clipboard history | `~/Library/Application Support/Pop/Clipboard/history.sqlite` (WAL mode); images are stored as PNG files in the `Images` folder next to it. Text recognized in images is also stored in the database for searching | Not synced; stays on this Mac |
| Inbox | `~/Documents/Pop 收集箱.md` | Follows your Documents folder |
| Vocabulary | `~/Library/Application Support/Pop/Vocabulary.json` | Not synced; can be exported |
| Files sent from a phone (Send to Phone) | `~/Downloads`; duplicate names get 2, 3… appended | Not synced |

Clipboard history is deduplicated by content (copying the same thing again just moves it to the top). Items older than the retention period or beyond the item limit are cleaned up every hour; pinned items are kept. Sensitive content that password managers mark with types such as `org.nspasteboard.ConcealedType` is never recorded, and you can exclude specific apps in Settings.

## Known limitations

- Pop needs Accessibility permission, and because the App Store sandbox doesn't allow Accessibility, it can only be distributed through its website / GitHub.
- Ad-hoc signed release builds need Accessibility permission granted again after every one-click update; builds signed with a fixed certificate don't (see [Signing and notarization](development.md#signing-and-notarization)).
- A few apps neither support reading the selection through Accessibility nor have a Copy menu item; Pop then simulates ⌘C. Simulated keystrokes may be wrong with non-QWERTY keyboard layouts.
- Replace and pasting from clipboard history simulate ⌘V, so they have no effect where the selection isn't editable.
- Screenshot OCR, Translate Screenshot, Scan Code, Annotate Screenshot and Screen Ruler need Screen Recording permission; without it, captures may show only the desktop background.
- Record Screen needs Screen & System Audio Recording permission too; after allowing it the first time, reopen Pop before recording. It records either the Mac's sound or the microphone, not both at once.
- Scrolling Screenshot needs Screen & System Audio Recording permission as well; if you scroll too fast to connect with the previous screen, the panel asks you to scroll back a little.
- Show Keystrokes only shows shortcuts with ⌘ or ⌃ and special keys such as Return and the arrow keys. While you type in a password field, macOS doesn't pass keys to other apps, so nothing is shown.
- The first time you open Camera Bubble, allow Pop to use the camera (you can change this later in System Settings → Privacy & Security → Camera).
- The first time you switch between Dark and Light Mode in System Actions, macOS asks whether Pop may control System Events; allow it (you can change this later in System Settings → Privacy & Security → Automation).
- The first time you use Transcribe, allow Speech Recognition. On-device recognition needs Dictation turned on (System Settings → Keyboard → Dictation); languages this Mac can't recognize on its own are sent to Apple's servers, and very long recordings may be only partly transcribed.
- Save Web Page opens the page in Pop itself, without your browser's sign-ins, so a page that needs you to sign in is saved as the sign-in page. Pages whose content scrolls inside its own area (such as some web apps) are saved as only the first screen.
- The first time you use Add to Reminders, allow Pop to access Reminders or Calendar (Calendar only needs write access). Development builds you sign yourself need the `com.apple.security.personal-information.calendars` entitlement (already set up in the project).
- The clipboard has no change notifications, so Pop checks it every 0.5 seconds; if you copy several times within that time, only the last one is recorded.
- System Translation can read stiffly for long paragraphs. Switch to AI translation or DeepL on the translation card (set up AI or enter a DeepL API key first).
- The Send to Phone page only opens on the same local network: it doesn't work on Wi-Fi that isolates devices (offices, hotels), or when the firewall's “Block all incoming connections” is on. The URL contains a random token, and the page stops working when you stop sharing or after 10 minutes without access.
