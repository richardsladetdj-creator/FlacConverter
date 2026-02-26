# FlacConverter

Lightweight drag-and-drop macOS utility for converting FLAC files to Apple Lossless (ALAC).

## Screenshot

![FlacConverter](docs/screenshot.png)

## Features

- FLAC → ALAC (.m4a)
- Drag & drop files or folders
- Outputs converted files into the same folder as the source
- Skips existing files
- Shows ignored non-FLAC files
- Progress tracking
- Logging

## Build (macOS)

Requires Xcode Command Line Tools.

```bash
swift build
swift run