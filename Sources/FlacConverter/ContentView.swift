import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct ContentView: View {
    // Settings (controlled by SettingsView via @AppStorage)
    @AppStorage("existingPolicy") private var existingPolicyRaw: String = ExistingFilePolicy.skip.rawValue
    @AppStorage("errorPolicy") private var errorPolicyRaw: String = ErrorPolicy.stop.rawValue
    @AppStorage("folderScanPolicy") private var folderScanPolicyRaw: String = FolderScanPolicy.recursive.rawValue

    private var existingPolicy: ExistingFilePolicy { ExistingFilePolicy(rawValue: existingPolicyRaw) ?? .skip }
    private var errorPolicy: ErrorPolicy { ErrorPolicy(rawValue: errorPolicyRaw) ?? .stop }
    private var folderScanPolicy: FolderScanPolicy { FolderScanPolicy(rawValue: folderScanPolicyRaw) ?? .recursive }

    // UI state
    @State private var isRunning = false
    @State private var isDropTargeted = false

    @State private var status = "Drop FLAC files or folders to convert to ALAC (.m4a) next to the originals."
    @State private var errorText: String? = nil

    @State private var currentFile = ""
    @State private var processed = 0
    @State private var total = 0
    @State private var ignored = 0
    @State private var skipped = 0
    @State private var overwritten = 0
    @State private var renamed = 0
    @State private var failed = 0

    @State private var lastLogURL: URL? = nil
    @State private var lastOutputFolderURL: URL? = nil

    @State private var youtubeURL = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            header

            GroupBox { dropZone }

            GroupBox { youtubeSection }

            GroupBox { progressAndStats }

            if let errorText {
                errorBanner(text: errorText)
            }

            footer
        }
        .padding(16)
        .frame(width: 760, height: 490)
    }

    // MARK: - UI

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)

                Text("FlacConverter")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Text(isRunning ? "Working…" : "Ready")
                    .foregroundStyle(.secondary)
            }

            Text("FLAC → Apple Lossless (ALAC) for Apple Music import")
                .foregroundStyle(.secondary)
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isDropTargeted ? .primary : .secondary,
                            style: StrokeStyle(lineWidth: isDropTargeted ? 2.5 : 1.5, dash: [8])
                        )
                        .opacity(isDropTargeted ? 0.9 : 0.6)
                )
                .animation(.easeInOut(duration: 0.12), value: isDropTargeted)

            VStack(spacing: 8) {
                Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                    .font(.system(size: 26, weight: .semibold))

                Text("Drop FLAC files or folders here")
                    .font(.headline)

                Text("Creates .m4a next to each FLAC")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)

                Text(hintText)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 14)
        }
        .frame(height: 160)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            guard !isRunning else { return false }
            Task { await handleDrop(providers: providers) }
            return true
        }
    }

    private var youtubeSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            TextField("YouTube URL  (e.g. https://youtube.com/watch?v=…)", text: $youtubeURL)
                .textFieldStyle(.roundedBorder)
                .disabled(isRunning)
                .onSubmit {
                    guard !youtubeURL.trimmingCharacters(in: .whitespaces).isEmpty, !isRunning else { return }
                    Task { await downloadFromYouTube() }
                }

            Button("Download") {
                Task { await downloadFromYouTube() }
            }
            .disabled(youtubeURL.trimmingCharacters(in: .whitespaces).isEmpty || isRunning)
        }
        .padding(.vertical, 4)
    }

    private var hintText: String {
        let existing = "Existing: \(existingPolicy.rawValue)"
        let err = "On error: \(errorPolicy.rawValue)"
        let scan = "Scan: \(folderScanPolicy.rawValue)"
        return "\(existing) • \(err) • \(scan) (change in FlacConverter → Settings…)"
    }

    private var progressAndStats: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: total == 0 ? 0 : Double(processed + skipped + failed), total: Double(max(total, 1)))
                .controlSize(.large)

            HStack {
                statChip(title: "Total", value: "\(total)")
                statChip(title: "Converted", value: "\(processed)")
                statChip(title: "Skipped", value: "\(skipped)")
                if overwritten > 0 { statChip(title: "Overwritten", value: "\(overwritten)") }
                if renamed > 0 { statChip(title: "Renamed", value: "\(renamed)") }
                if failed > 0 { statChip(title: "Failed", value: "\(failed)") }
                if ignored > 0 { statChip(title: "Ignored", value: "\(ignored)") }
                Spacer()
            }

            if !currentFile.isEmpty {
                HStack(spacing: 8) {
                    Text("Current:")
                        .foregroundStyle(.secondary)
                    Text(currentFile)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.callout)
            }

            Text(status)
                .font(.callout)
                .foregroundStyle(isRunning ? .secondary : .primary)
        }
        .padding(.vertical, 4)
    }

    private func statChip(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func errorBanner(text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer()
            Button("Dismiss") { errorText = nil }
        }
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Open Last Log") {
                if let lastLogURL { NSWorkspace.shared.open(lastLogURL) }
            }
            .disabled(lastLogURL == nil)

            Button("Show Folder") {
                if let lastOutputFolderURL {
                    NSWorkspace.shared.activateFileViewerSelecting([lastOutputFolderURL])
                }
            }
            .disabled(lastOutputFolderURL == nil)

            Spacer()

            Button("Reset") { resetUI() }
                .disabled(isRunning)
        }
    }

    private func resetUI() {
        errorText = nil
        status = "Drop FLAC files or folders to convert to ALAC (.m4a) next to the originals."
        currentFile = ""
        processed = 0
        total = 0
        ignored = 0
        skipped = 0
        overwritten = 0
        renamed = 0
        failed = 0
        lastLogURL = nil
        lastOutputFolderURL = nil
    }

    // MARK: - Drop handling

    private func handleDrop(providers: [NSItemProvider]) async {
        resetUI()
        isRunning = true
        status = "Reading dropped items…"

        let urls = await loadDroppedFileURLs(from: providers)
        if urls.isEmpty {
            status = "No dropped items could be read."
            isRunning = false
            return
        }

        var flacs: [URL] = []
        var localIgnored = 0

        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    do {
                        let found = try listFlacs(inFolder: url, policy: folderScanPolicy)
                        flacs.append(contentsOf: found)
                    } catch {
                        localIgnored += 1
                    }
                } else {
                    if url.pathExtension.lowercased() == "flac" {
                        flacs.append(url)
                    } else {
                        localIgnored += 1
                    }
                }
            } else {
                localIgnored += 1
            }
        }

        flacs = Array(Set(flacs)).sorted { $0.path < $1.path }
        ignored = localIgnored
        total = flacs.count

        if flacs.isEmpty {
            status = "No FLAC files found. Ignored \(ignored) item(s)."
            isRunning = false
            return
        }

        status = "Converting \(total) file(s)…"

        for f in flacs {
            currentFile = f.lastPathComponent

            do {
                let result = try await convertOneInPlace(file: f, existingPolicy: existingPolicy)
                switch result {
                case .converted:
                    processed += 1
                case .skipped:
                    skipped += 1
                case .overwritten:
                    overwritten += 1
                case .renamed:
                    renamed += 1
                }
            } catch {
                failed += 1
                errorText = error.localizedDescription
                status = "Error on \(f.lastPathComponent)."

                if errorPolicy == .stop {
                    isRunning = false
                    return
                } else {
                    continue
                }
            }
        }

        currentFile = ""
        status = "Done. Converted \(processed), skipped \(skipped), failed \(failed), ignored \(ignored)."
        isRunning = false
    }

    private func loadDroppedFileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        urls.reserveCapacity(providers.count)

        for p in providers {
            if let url = await loadFileURL(from: p) {
                urls.append(url)
            }
        }
        return urls
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    cont.resume(returning: url)
                    return
                }
                if let url = item as? URL {
                    cont.resume(returning: url)
                    return
                }
                cont.resume(returning: nil)
            }
        }
    }

    private func listFlacs(inFolder folder: URL, policy: FolderScanPolicy) throws -> [URL] {
        let fm = FileManager.default

        if policy == .topLevelOnly {
            let items = try fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            return items.filter { $0.pathExtension.lowercased() == "flac" }
        }

        let enumr = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var files: [URL] = []
        while let url = enumr?.nextObject() as? URL {
            if url.pathExtension.lowercased() == "flac" {
                files.append(url)
            }
        }
        return files
    }

    // MARK: - Conversion

    private enum ConvertResult { case converted, skipped, overwritten, renamed }

    private func convertOneInPlace(file: URL, existingPolicy: ExistingFilePolicy) async throws -> ConvertResult {
        let fm = FileManager.default
        let folder = file.deletingLastPathComponent()

        let base = file.deletingPathExtension().lastPathComponent
        var outFile = folder.appendingPathComponent(base).appendingPathExtension("m4a")

        let log = folder.appendingPathComponent("convert.log")
        lastLogURL = log
        lastOutputFolderURL = folder

        if fm.fileExists(atPath: outFile.path) {
            switch existingPolicy {
            case .skip:
                writeLog("SKIP (exists): \(outFile.path)\n", to: log)
                return .skipped
            case .overwrite:
                writeLog("OVERWRITE: \(outFile.path)\n", to: log)
            case .rename:
                outFile = nextAvailableName(for: outFile)
                writeLog("RENAME -> \(outFile.lastPathComponent)\n", to: log)
            }
        }

        writeLog("CONVERT: \(file.path) -> \(outFile.path)\n", to: log)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        proc.arguments = [file.path, outFile.path, "-f", "m4af", "-d", "alac"]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        try proc.run()
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if !data.isEmpty {
            writeLog(String(decoding: data, as: UTF8.self), to: log)
        }

        if proc.terminationStatus != 0 {
            writeLog("ERROR: afconvert exited with \(proc.terminationStatus)\n", to: log)
            throw NSError(
                domain: "afconvert",
                code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "afconvert failed on \(file.lastPathComponent). See convert.log in that folder."]
            )
        }

        switch existingPolicy {
        case .overwrite:
            return fm.fileExists(atPath: folder.appendingPathComponent(base).appendingPathExtension("m4a").path) ? .overwritten : .converted
        case .rename:
            return .renamed
        case .skip:
            return .converted
        }
    }

    private func nextAvailableName(for url: URL) -> URL {
        let fm = FileManager.default
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var i = 1
        while true {
            let candidate = folder
                .appendingPathComponent("\(base) (\(i))")
                .appendingPathExtension(ext)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            i += 1
        }
    }

    private func writeLog(_ text: String, to logURL: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: logURL.path) {
            fm.createFile(atPath: logURL.path, contents: nil, attributes: nil)
        }
        guard let data = text.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            do { try handle.seekToEnd() } catch { }
            do { try handle.write(contentsOf: data) } catch { }
        }
    }

    // MARK: - YouTube Download

    private func findYtDlp() -> URL? {
        // Bundled binary (installed .app via Install.sh)
        if let bundled = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("yt-dlp"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        // Fallback: Homebrew (development builds via swift run)
        return ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func downloadFromYouTube() async {
        let rawURL = youtubeURL.trimmingCharacters(in: .whitespaces)
        guard !rawURL.isEmpty else { return }

        guard let ytDlp = findYtDlp() else {
            errorText = "yt-dlp not found. Install it with: brew install yt-dlp"
            return
        }

        isRunning = true
        errorText = nil

        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let log = downloads.appendingPathComponent("yt-download.log")
        lastLogURL = log
        writeLog("=== YouTube download: \(rawURL)\n", to: log)

        // Step 1: Get the video title
        status = "Fetching video title…"
        let titleProc = Process()
        titleProc.executableURL = ytDlp
        titleProc.arguments = ["--skip-download", "--print", "title", "--no-playlist", rawURL]
        let titlePipe = Pipe()
        let titleErrPipe = Pipe()
        titleProc.standardOutput = titlePipe
        titleProc.standardError = titleErrPipe

        do { try titleProc.run() } catch {
            writeLog("ERROR launching yt-dlp (title): \(error)\n", to: log)
            errorText = "Failed to launch yt-dlp: \(error.localizedDescription)"
            isRunning = false
            return
        }
        titleProc.waitUntilExit()

        let titleData = titlePipe.fileHandleForReading.readDataToEndOfFile()
        let titleErrData = titleErrPipe.fileHandleForReading.readDataToEndOfFile()
        if !titleErrData.isEmpty { writeLog(String(decoding: titleErrData, as: UTF8.self), to: log) }
        writeLog(String(decoding: titleData, as: UTF8.self), to: log)

        guard titleProc.terminationStatus == 0 else {
            errorText = "yt-dlp could not fetch the video title (exit \(titleProc.terminationStatus)). Check the URL."
            isRunning = false
            return
        }

        let rawTitle = String(decoding: titleData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let illegalChars = CharacterSet(charactersIn: #"/\:*?"<>|"#)
        let safeTitle = rawTitle.components(separatedBy: illegalChars).joined(separator: "_")
        let finalTitle = safeTitle.isEmpty ? "YouTube_Audio" : safeTitle

        // Step 2: Download best m4a audio to a temp file
        status = "Downloading audio…"
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let tmpTemplate = tmpDir.appendingPathComponent("flacconverter_%(id)s.%(ext)s").path

        let dlProc = Process()
        dlProc.executableURL = ytDlp
        dlProc.arguments = ["-f", "bestaudio[ext=m4a]", "--no-playlist", "-o", tmpTemplate, rawURL]
        let dlPipe = Pipe()
        dlProc.standardOutput = dlPipe
        dlProc.standardError = dlPipe

        do { try dlProc.run() } catch {
            writeLog("ERROR launching yt-dlp (download): \(error)\n", to: log)
            errorText = "Failed to launch yt-dlp download: \(error.localizedDescription)"
            isRunning = false
            return
        }
        dlProc.waitUntilExit()

        let dlOutput = String(decoding: dlPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        writeLog(dlOutput, to: log)

        // Parse the downloaded file path from yt-dlp output
        var tempFile: URL? = nil
        for line in dlOutput.components(separatedBy: .newlines) {
            if line.contains("Destination:") {
                if let pathPart = line.components(separatedBy: "Destination:").last?.trimmingCharacters(in: .whitespaces),
                   !pathPart.isEmpty {
                    tempFile = URL(fileURLWithPath: pathPart)
                    break
                }
            }
            // Handle "has already been downloaded" (yt-dlp skips re-download of existing temp file)
            if tempFile == nil, line.contains("has already been downloaded") {
                let trimmed = line.replacingOccurrences(of: "[download]", with: "").trimmingCharacters(in: .whitespaces)
                if let range = trimmed.range(of: " has already been downloaded") {
                    tempFile = URL(fileURLWithPath: String(trimmed[trimmed.startIndex..<range.lowerBound]))
                    break
                }
            }
        }

        if dlProc.terminationStatus != 0 || tempFile == nil {
            errorText = "No m4a audio stream found for this video. The video may not have an AAC/m4a stream."
            status = "Download failed."
            isRunning = false
            return
        }

        guard let srcFile = tempFile, FileManager.default.fileExists(atPath: srcFile.path) else {
            errorText = "Downloaded file not found at expected temp path. See yt-download.log."
            isRunning = false
            return
        }

        // Step 3: Remux DASH m4a → standard m4a (required for Apple Music playback)
        status = "Processing audio…"
        var outFile = downloads.appendingPathComponent(finalTitle).appendingPathExtension("m4a")

        if FileManager.default.fileExists(atPath: outFile.path) {
            switch existingPolicy {
            case .skip:
                writeLog("SKIP (exists): \(outFile.path)\n", to: log)
                try? FileManager.default.removeItem(at: srcFile)
                status = "Skipped — file already exists in Downloads."
                lastOutputFolderURL = downloads
                youtubeURL = ""
                isRunning = false
                return
            case .overwrite:
                writeLog("OVERWRITE: \(outFile.path)\n", to: log)
                try? FileManager.default.removeItem(at: outFile)
            case .rename:
                outFile = nextAvailableName(for: outFile)
                writeLog("RENAME -> \(outFile.lastPathComponent)\n", to: log)
            }
        }

        writeLog("REMUX: \(srcFile.path) -> \(outFile.path)\n", to: log)
        do {
            try await remuxToM4A(src: srcFile, dst: outFile)
        } catch {
            writeLog("ERROR remuxing: \(error)\n", to: log)
            try? FileManager.default.removeItem(at: srcFile)
            errorText = "Failed to process audio: \(error.localizedDescription)"
            isRunning = false
            return
        }
        try? FileManager.default.removeItem(at: srcFile)
        writeLog("DELETED temp: \(srcFile.path)\n", to: log)

        writeLog("SUCCESS: \(outFile.path)\n", to: log)
        lastOutputFolderURL = downloads
        status = "Saved: \(outFile.lastPathComponent)"
        youtubeURL = ""
        isRunning = false
    }

    private func remuxToM4A(src: URL, dst: URL) async throws {
        let asset = AVURLAsset(url: src)

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(
                domain: "FlacConverter", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not create export session for downloaded audio."]
            )
        }
        session.outputURL = dst
        session.outputFileType = .m4a

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { cont.resume() }
        }

        if session.status != .completed {
            let msg = session.error?.localizedDescription ?? "Unknown export error"
            throw NSError(
                domain: "FlacConverter", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Audio remux failed: \(msg)"]
            )
        }
    }
}