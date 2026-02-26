import SwiftUI

struct SettingsView: View {
    // Persisted settings
    @AppStorage("existingPolicy") private var existingPolicyRaw: String = ExistingFilePolicy.skip.rawValue
    @AppStorage("errorPolicy") private var errorPolicyRaw: String = ErrorPolicy.stop.rawValue
    @AppStorage("folderScanPolicy") private var folderScanPolicyRaw: String = FolderScanPolicy.recursive.rawValue

    var body: some View {
        Form {
            Section("Existing .m4a files") {
                Picker("", selection: $existingPolicyRaw) {
                    ForEach(ExistingFilePolicy.allCases) { p in
                        Text(p.rawValue).tag(p.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("On conversion error") {
                Picker("", selection: $errorPolicyRaw) {
                    ForEach(ErrorPolicy.allCases) { p in
                        Text(p.rawValue).tag(p.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Folder scan") {
                Picker("", selection: $folderScanPolicyRaw) {
                    ForEach(FolderScanPolicy.allCases) { p in
                        Text(p.rawValue).tag(p.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}

// Shared enums (must be visible to ContentView too)
enum ExistingFilePolicy: String, CaseIterable, Identifiable {
    case skip = "Skip"
    case overwrite = "Overwrite"
    case rename = "Rename"
    var id: String { rawValue }
}

enum ErrorPolicy: String, CaseIterable, Identifiable {
    case stop = "Stop"
    case `continue` = "Continue"
    var id: String { rawValue }
}

enum FolderScanPolicy: String, CaseIterable, Identifiable {
    case recursive = "Recursive"
    case topLevelOnly = "Top-level only"
    var id: String { rawValue }
}