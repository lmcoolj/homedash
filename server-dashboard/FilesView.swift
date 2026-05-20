import SwiftUI

struct FilesView: View {
    @AppStorage("filesShowHidden") private var showHidden = false
    @State private var pathStack: [String] = []

    var body: some View {
        NavigationStack(path: $pathStack) {
            FileListView(path: "/", showHidden: showHidden)
                .navigationDestination(for: String.self) { p in
                    FileListView(path: p, showHidden: showHidden)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Toggle("Show hidden", isOn: $showHidden)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
        }
    }
}

private struct FileListView: View {
    @Environment(AppState.self) private var state
    let path: String
    let showHidden: Bool

    @State private var listing: FileListing?
    @State private var error: String?
    @State private var selectedFile: FileEntry?

    var body: some View {
        List {
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
            if let listing {
                if listing.items.isEmpty {
                    Text("Empty folder")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                ForEach(listing.items) { item in
                    if item.isDir {
                        NavigationLink(value: item.rel) {
                            FileRow(entry: item)
                        }
                    } else {
                        Button {
                            selectedFile = item
                        } label: {
                            FileRow(entry: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if error == nil {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: showHidden) { await load() }
        .sheet(item: $selectedFile) { entry in
            FileDetailSheet(entry: entry)
                .presentationDetents([.medium, .large])
        }
    }

    private var displayTitle: String {
        if path == "/" { return "Files" }
        return (path as NSString).lastPathComponent
    }

    private func load() async {
        do {
            listing = try await HomeDashAPI.shared.listFiles(path: path, showHidden: showHidden)
            error = nil
        } catch APIError.notAuthenticated {
            await state.logout()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct FileRow: View {
    let entry: FileEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isDir ? "folder.fill" : iconName(for: entry.name))
                .foregroundStyle(entry.isDir ? Color.accentColor : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .lineLimit(1)
                if let sub = subtitle {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var subtitle: String? {
        var parts: [String] = []
        if !entry.isDir, let s = entry.size { parts.append(bytes(s)) }
        if let m = entry.mtime { parts.append(dateString(m)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func iconName(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "heic", "webp": return "photo"
        case "mp4", "mov", "mkv", "avi": return "film"
        case "mp3", "wav", "m4a", "flac": return "music.note"
        case "zip", "tar", "gz", "7z": return "archivebox"
        case "json", "js", "ts", "swift", "py", "go", "rs", "java", "c", "h", "cpp", "rb": return "curlybraces"
        case "md", "txt", "log": return "doc.text"
        case "pdf": return "doc.richtext"
        default: return "doc"
        }
    }

    private func bytes(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB, .useKB, .useBytes]
        f.countStyle = .binary
        return f.string(fromByteCount: n)
    }

    private func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
}

private struct FileDetailSheet: View {
    let entry: FileEntry
    @State private var downloading = false
    @State private var downloadedURL: URL?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section("File") {
                    LabeledContent("Name", value: entry.name)
                    LabeledContent("Path") {
                        Text(entry.rel)
                            .font(.caption.monospaced())
                            .multilineTextAlignment(.trailing)
                    }
                    if let s = entry.size {
                        LabeledContent("Size", value: bytes(s))
                    }
                    if let m = entry.mtime {
                        LabeledContent("Modified", value: dateString(m))
                    }
                }
                Section {
                    if let url = downloadedURL {
                        ShareLink(item: url) {
                            Label("Share / Save", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            Task { await download() }
                        } label: {
                            if downloading {
                                HStack { ProgressView(); Text("Downloading…") }
                            } else {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                        }
                        .disabled(downloading)
                    }
                    if let error {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func download() async {
        downloading = true
        defer { downloading = false }
        do {
            downloadedURL = try await HomeDashAPI.shared.download(path: entry.rel)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func bytes(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB, .useKB, .useBytes]
        f.countStyle = .binary
        return f.string(fromByteCount: n)
    }

    private func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
}
