import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var isRunning = false
    @State private var status = "Drag FLAC files or folders into the panel to convert to ALAC (.m4a) in-place."
    @State private var currentFile = ""
    @State private var processed = 0
    @State private var total = 0
    @State private var ignored = 0
    @State private var skipped = 0

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("FLAC → ALAC (.m4a)")
                .font(.title2)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundStyle(isDropTargeted ? .primary : .secondary)
                    .frame(height: 150)

                VStack(spacing: 8) {
                    Text("Drag & drop FLAC files or folders here")
                        .font(.headline)
                    Text("Outputs .m4a next to each source file (skips if already exists)")
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
                guard !isRunning else { return false }
                Task { await handleDrop(providers: providers) }
                return true
            }

            ProgressView(value: total == 0 ? 0 : Double(processed), total: Double(max(total, 1)))

            HStack {
                Text("Progress: \(processed)/\(total)")
                if skipped > 0 { Text("Skipped: \(skipped)") }
                if ignored > 0 { Text("Ignored: \(ignored)") }
            }
            .foregroundStyle(.secondary)

            if !currentFile.isEmpty {
                Text("Current: \(currentFile)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }

            Text(status)
                .font(.callout)

            Spacer()
        }
        .padding(16)
        .frame(width: 760, height: 320)
    }

    // MARK: - Drop handling

    private func handleDrop(providers: [NSItemProvider]) async {
        isRunning = true
        processed = 0
        total = 0
        ignored = 0
        skipped = 0
        currentFile = ""
        status = "Reading dropped items…"

        let urls = await loadDroppedFileURLs(from: providers)
        if urls.isEmpty {
            status = "No dropped items could be read."
            isRunning = false
            return
        }

        // Expand: if folder dropped, enumerate flacs inside
        var flacs: [URL] = []
        var localIgnored = 0

        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    // Folder: add flacs recursively
                    do {
                        let found = try listFlacs(inFolder: url)
                        flacs.append(contentsOf: found)
                    } catch {
                        localIgnored += 1
                    }
                } else {
                    // File: only accept flac
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

        // De-dupe
        flacs = Array(Set(flacs)).sorted { $0.path < $1.path }

        ignored = localIgnored
        total = flacs.count

        if flacs.isEmpty {
            status = "No FLAC files found. Ignored \(ignored) item(s)."
            isRunning = false
            return
        }

        status = "Converting \(total) file(s)… (stops on first error)"

        do {
            for f in flacs {
                currentFile = f.lastPathComponent
                let result = try await convertOneInPlace(file: f)
                switch result {
                case .converted:
                    processed += 1
                case .skipped:
                    skipped += 1
                }
            }

            currentFile = ""
            status = "Done. Converted \(processed), skipped \(skipped), ignored \(ignored)."
        } catch {
            status = "Stopped: \(error.localizedDescription)"
        }

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

    private func listFlacs(inFolder folder: URL) throws -> [URL] {
        let fm = FileManager.default
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

    private enum ConvertResult { case converted, skipped }

    private func convertOneInPlace(file: URL) async throws -> ConvertResult {
        let fm = FileManager.default
        let folder = file.deletingLastPathComponent()

        let base = file.deletingPathExtension().lastPathComponent
        let outFile = folder.appendingPathComponent(base).appendingPathExtension("m4a")

        let log = folder.appendingPathComponent("convert.log")
        writeLog("CONVERT: \(file.path) -> \(outFile.path)\n", to: log)

        if fm.fileExists(atPath: outFile.path) {
            writeLog("SKIP (exists): \(outFile.path)\n", to: log)
            return .skipped
        }

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

        return .converted
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
}