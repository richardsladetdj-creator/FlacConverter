# FlacConverter — Claude Code Guide

## Project Purpose

FlacConverter is a macOS drag-and-drop utility that converts FLAC audio files to Apple Lossless (ALAC/m4a) in-place. It uses Apple's built-in `afconvert` tool — no external dependencies. Target audience: macOS power users migrating music libraries.

## Build & Run

```bash
# Development
swift build
swift run FlacConverter

# Install to /Applications (builds release, bundles, signs, launches)
./Install.sh
```

Minimum macOS: 13 (Ventura). Swift Tools Version: 5.9. No external packages.

## Architecture

Three Swift source files in `Sources/FlacConverter/`:

| File | Responsibility |
|------|---------------|
| `FlacConverterApp.swift` | `@main` entry point, `WindowGroup` + `Settings` scene |
| `ContentView.swift` | All conversion logic, drag-and-drop handling, YouTube download pipeline, UI state |
| `SettingsView.swift` | Settings form UI, shared policy enums |

**Pattern:** SwiftUI state-driven. No separate ViewModel objects — `ContentView` is large by design (~460 lines) and uses extracted computed-property subviews (`header`, `dropZone`, `youtubeSection`, `progressAndStats`, `footer`) for organisation.

**Settings persistence:** `@AppStorage` (UserDefaults). Policy enums defined in `SettingsView.swift` are imported by `ContentView` via computed properties:

```swift
@AppStorage("existingPolicy") private var existingPolicyRaw: String = ExistingFilePolicy.skip.rawValue
private var existingPolicy: ExistingFilePolicy {
    ExistingFilePolicy(rawValue: existingPolicyRaw) ?? .skip
}
```

**Conversion:** `convertOneInPlace()` shells out to `/usr/bin/afconvert <input.flac> <output.m4a> -f m4af -d alac`. Output is captured via `Pipe` and written to `convert.log` in the same folder.

## Key Policies (Enums in SettingsView.swift)

- `ExistingFilePolicy` — `.skip` / `.overwrite` / `.rename`
- `ErrorPolicy` — `.stop` / `.continue`
- `FolderScanPolicy` — `.recursive` / `.topLevelOnly`

## Coding Conventions

- **Naming:** PascalCase types, camelCase vars/functions. Verbose and descriptive (`nextAvailableName`, `writeLog`, `loadDroppedFileURLs`).
- **State:** `@State` for local UI, `@AppStorage` for persistent settings, no external state management.
- **Subviews:** Extracted as `private var` computed properties returning `some View`, kept within `ContentView`.
- **File I/O:** `FileManager.default` throughout. Always check for file existence before acting.
- **Async:** Drop handling uses `async`/`await`. Conversion runs on a background thread to keep UI responsive.
- **Error handling:** Throw `NSError` with localized descriptions; catch at the call site and surface via `errorBanner`.
- **No external dependencies:** Keep it that way. Leverage macOS system tools and frameworks only.

## Window & UI

- Fixed window size: **760×490 px**.
- Four vertical sections: header → drop zone → progress/stats → footer.
- Material backgrounds: `.thinMaterial` (drop zone), `.regularMaterial` (stats).
- Animate drop-zone border on hover using `.animation(.easeInOut, value: isDropTargeted)`.

## YouTube Download Feature

A second input method added to the UI between the drop zone and progress section. The user pastes a YouTube URL and clicks **Download** (or presses Return).

**Pipeline:** `yt-dlp --skip-download --print title` → sanitize title → `yt-dlp -f "bestaudio[ext=m4a]"` (downloads AAC m4a to `/tmp/`) → `AVAssetExportSession` with `AVAssetExportPresetAppleM4A` (remuxes to standard m4a for Apple Music compatibility) → saves to `~/Downloads/<title>.m4a` → deletes temp file.

**Dependency:** `yt-dlp` must be installed (`brew install yt-dlp`). The app checks `/opt/homebrew/bin/yt-dlp` and `/usr/local/bin/yt-dlp` at runtime and surfaces a clear error if not found. No `ffmpeg` required.

**Key functions in ContentView.swift:**
- `findYtDlp() -> URL?` — locates yt-dlp (bundled in .app bundle first, then Homebrew fallback)
- `downloadFromYouTube()` — full async pipeline (in `// MARK: - YouTube Download`)
- `remuxToM4A(src:dst:)` — wraps `AVAssetExportSession` to remux DASH m4a → standard m4a
- `youtubeSection` — the UI row (TextField + Button)

**Log:** Written to `~/Downloads/yt-download.log`, surfaced by the existing "Open Last Log" button. Respects `existingPolicy` for the output file.

## Common Tasks

### Adding a new setting

1. Add a `CaseIterable` enum to `SettingsView.swift`.
2. Add a `Picker` to `SettingsView`'s `Form`.
3. Add an `@AppStorage` property + computed accessor in `ContentView`.
4. Apply the policy in `convertOneInPlace()` or the file-enumeration loop.

### Changing conversion behaviour

Edit `convertOneInPlace()` in `ContentView.swift`. The `afconvert` invocation is a `Process` call — adjust arguments there. Always append results to the log via `writeLog()`.

### Adding a new UI section

Add a computed property `private var mySection: some View` to `ContentView` and insert it into the main `VStack`. Keep business logic out of the property body — call functions instead.

### Debugging conversion failures

- Check `convert.log` in the same folder as the source files — it captures `afconvert` stdout/stderr and exit codes.
- Reproduce with `afconvert <input.flac> <output.m4a> -f m4af -d alac` in Terminal directly.
- `errorPolicy` controls whether the UI stops or continues on failure; set to `.stop` to isolate a failing file.

### Debugging UI state issues

- All meaningful UI state is `@State` in `ContentView` — inspect with `print()` or SwiftUI Previews.
- `isRunning` gates all drop handling and button enabled states; ensure it is reset in all code paths (including error paths).

## What to Avoid

- Do not add external Swift packages — the whole point is zero dependencies.
- Do not split `ContentView` into a separate ViewModel class unless complexity clearly demands it; the current pattern is intentional.
- Do not change the window size without updating all `.frame()` constraints consistently.
- Do not swallow errors silently — always surface them via the `errorBanner` or log.
