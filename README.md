# PhotoFlow

Native macOS photo browser for fast culling: browse → EXIF → filter → rate / color / pick.

Original files are never modified. Ratings, color labels, pick flags, and cached EXIF live in a local SQLite database.

## V1

- Folder scan: JPG, HEIC, TIFF, WebP, and common RAW (CR3, ARW, NEF, RAF, DNG, …)
- Loupe + filmstrip, or thumbnail grid
- Pinch / double-click zoom in loupe
- ImageIO EXIF: camera, lens, shutter, aperture, ISO, focal length
- Shutter and aperture stored as numbers (`1/500` → `0.002s`, `f/2.8` → `2.8`) so ranges work
- Combined filters: brand + body + lens + shutter + aperture + ISO + focal length + rating + color + pick
- Sort by filename, capture date, rating, or pick
- Lightroom-style 0–5 stars
- Color labels (6–9 / −); right-click a color in the sidebar to give it a meaning (Maybe, Keep…)
- Pick / Reject / Unflag, with optional auto-advance
- Export picked or visible photos as copies
- 14 skins: Adobe-style (Lightroom Classic, Photoshop, Adobe Light, Neutral 18% Gray), dark and light themes; switch from the Skin menu, the toolbar palette, Settings, or `⌥⌘K`
- Info inspector for the selected photo
- Auto groups: people, sports, pets, birds, animals, nature, flowers, architecture, food, vehicles, night, events, documents — detected on-device with Apple Vision (nothing uploaded, files untouched). A photo can be in several groups; edit them by hand in the Info panel or right-click ▸ Content Groups. Search also matches content (e.g. "dog", "beach").
- Search: words separated by spaces must all match — content in Chinese or English (鸟, 狗, 海边, 风景, sunset), places (上海, Yosemite), file and folder names, camera / lens, and dates (2024-10, 2024年10月). Example: `鸟 上海 2024`.
- Places: GPS photos are named via Apple's geocoder (coordinates only; can be turned off in Settings) and listed under Places in the sidebar. Photos without GPS can be tagged with right-click ▸ Set Location…
- Collections: hand-picked sets that can span folders. `B` adds to the target collection, `⌘N` creates one, drag photos onto a collection, `⌫` removes from the open collection (never deletes files)
- Bilingual UI (简体中文 / English / follow system): Settings, the palette menu in the toolbar, or PhotoFlow ▸ Language. Switches instantly. English strings in code are the keys (`tr("…")`); Chinese lives in `Models/Localization+Chinese.swift`
- Compact sidebar: every section folds (state is remembered), Auto Groups show as chips with the 6 largest first and "More +N", color labels sit on one row, Places shows the top 5
- Persistence in `~/Library/Application Support/PhotoFlow/photoflow.sqlite`

## Keyboard

Modeled on Lightroom Classic / Photoshop. `⌘/` shows the full list in the app.

| Key | Action |
| --- | --- |
| `1`–`5` / `0` | Set stars / clear rating |
| `[` `]` | Decrease / increase rating |
| `P` `X` `U` | Pick / Reject / Unflag (Pick and Reject advance if auto-advance is on) |
| `` ` `` | Toggle pick flag |
| `6`–`9` / `-` | Red / Yellow / Green / Blue / Purple |
| `⇧` + any marking key | Apply, then go to the next photo |
| `⌘Z` / `⇧⌘Z` | Undo / redo ratings, colors and flags |
| `←` `→` (Loupe also `↑` `↓`), `Home` / `End` | Previous / next, first / last in the current filter |
| `G` / `E` / `Return` | Grid / Loupe / open Loupe from Grid |
| `Z` / `Space` (Loupe) | Toggle Fit / 1:1 |
| `⌘=` `⌘-` / `⌘0` / `⌘1` | Zoom in / out (thumbnail size in Grid), Fit, actual pixels |
| Scroll wheel / pinch | Zoom around the cursor (Loupe); drag to pan; double-click toggles Fit / 1:1 |
| `F` | Full-screen preview (`F` or `Esc` to exit) |
| `Tab` / `⇧Tab` | Toggle side panels / all panels |
| `F5` `F6` `F7` `F8` | Top bar / Filmstrip / Library / Inspector |
| `\` or `⌘F` / `I` / `'` | Filter panel / Info panel / Info bar |
| `⌘`-click / `⇧`-click | Add to / extend the multi-selection; marks then apply to every selected photo |
| `⌘A` / `⌘D` / `Esc` | Select all / select none / keep only the current photo |
| `⌘C` | Copy selected original files (paste in Finder) |
| `F2` | Rename |
| `⌘O` / `⇧⌘I` | Open folder / Import |
| `⇧⌘E` / `⇧⌘S` / `⌘P` | Export / Save As / Print |
| `⌘E` / `⌘R` | Edit in Preview / Show in Finder |
| `B` / `⌘B` | Add to (or remove from) the target collection / show it |
| `⌘N` / `⌫` | New collection / remove from the open collection |
| `⌥⌘K` / `⇧⌥⌘K` | Next / previous skin |
| `⌘,` / `⌘/` | Settings / keyboard shortcuts |
| `Esc` / `Return` in search | Leave the search field so arrows page photos again |

On laptops, F-keys may need `fn`. Shortcuts are ignored while a text field is focused.

## Layout

```
PhotoFlow    ◀ ▶    Search          Sort    Filter  ℹ  ⚙
Folders |              IMAGE                 | Filter | Info
Smart   |                                    | brand / body / lens
        | filmstrip with ★ and color         | shutter / aperture
filename  ★★★★☆  🟢   ISO 400  1/500  f/2.8
```

## Run

`Package.swift` is the only build definition (macOS 14+, Swift 5.10+). Command Line Tools are enough.

```
./scripts/package.sh      # release build → dist/PhotoFlow.app (signed ad hoc)
swift test                # Swift Testing: search, filters, exposure parsing, translations
```

Xcode can open `Package.swift` directly for debugging.

## Layout of the code

```
PhotoFlowApp.swift        menus and window
Models/                   PhotoItem, FilterState, SearchQuery, skins, Preferences keys, localization
Services/                 SQLite, folder scan, EXIF, Vision classifier, geocoding, thumbnails, export
ViewModels/PhotoLibrary   state + indexes; +Loading, +Marks, +Panels, +Keyboard, +Files, +Organize, +Actions
Views/                    screens; Views/Components holds shared controls
Tests/PhotoFlowTests      unit tests
```

Adding UI text: write `tr("English")` and add the Chinese to `Models/Localization+Chinese.swift`. `swift test` fails if a translation is missing or unused.

## Data flow

```
ImageIO EXIF  →  SQLite (rating / color / pick / EXIF cache)  →  SwiftUI
```

Export copies files into a folder you choose. It never writes into the originals.

The next natural extensions are AI tags, duplicates, faces, map, timeline, Smart Albums, and XMP export.
