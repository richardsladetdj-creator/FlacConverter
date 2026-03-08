# FlacConverter

Lightweight drag-and-drop macOS utility for converting FLAC files to Apple Lossless (ALAC).

## Screenshot

![FlacConverter](docs/screenshot.png)

## Features

- FLAC → ALAC (.m4a) conversion using macOS built-in `afconvert` — no external dependencies
- Drag & drop files or folders onto the app window
- Outputs converted files into the same folder as the source
- YouTube download: paste a URL and download audio directly as ALAC (requires `yt-dlp`)
- Configurable policies (via Settings):
  - **Existing file:** skip / overwrite / rename
  - **On error:** stop / continue
  - **Folder scan:** recursive / top-level only
- Progress tracking with file counts and success/failure stats
- Logging — per-folder `convert.log` for FLAC conversions, `~/Downloads/yt-download.log` for YouTube downloads

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools
- `yt-dlp` (optional, for YouTube downloads): `brew install yt-dlp`

## Build (macOS)

```bash
swift build
swift run