import Cocoa
import SwiftUI
import WebKit

// MARK: - Model

struct Bookmark: Identifiable {
    let id: String
    let title: String
    let url: String
    let path: [String]
}

struct DuplicateGroup: Identifiable {
    let id: String   // normalized URL
    let url: String
    let title: String
    let bookmarks: [Bookmark]
}

// MARK: - Store

@MainActor
class BookmarkStore: ObservableObject {
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var isLoading = false
    @Published var loadError: String?
    @Published var resolvedCount = 0

    private let bookmarksURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Safari/Bookmarks.plist")

    func load() {
        isLoading = true
        loadError = nil
        resolvedCount = 0

        guard let data = try? Data(contentsOf: bookmarksURL) else {
            loadError = "Could not read Safari bookmarks.\n\nIf you're on macOS Ventura or later, grant Full Disk Access to this app in:\nSystem Settings → Privacy & Security → Full Disk Access"
            isLoading = false
            return
        }

        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            loadError = "Could not parse Safari bookmarks file."
            isLoading = false
            return
        }

        var all: [Bookmark] = []
        collect(node: root, path: [], into: &all)
        duplicateGroups = computeDuplicateGroups(from: all)
        isLoading = false
    }

    private func collect(node: [String: Any], path: [String], into result: inout [Bookmark]) {
        let type = node["WebBookmarkType"] as? String
        if type == "WebBookmarkTypeLeaf",
           let urlString = node["URLString"] as? String,
           let uuid = node["WebBookmarkUUID"] as? String {
            let title: String
            if let d = node["URIDictionary"] as? [String: Any],
               let t = d["title"] as? String, !t.isEmpty {
                title = t
            } else {
                title = urlString
            }
            result.append(Bookmark(id: uuid, title: title, url: urlString, path: path))
            return
        }
        if let children = node["Children"] as? [[String: Any]] {
            let folderTitle = (node["Title"] as? String) ?? ""
            let nextPath = folderTitle.isEmpty ? path : path + [folderTitle]
            for child in children {
                collect(node: child, path: nextPath, into: &result)
            }
        }
    }

    private func normalizedURL(_ url: String) -> String {
        var s = url.lowercased()
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func computeDuplicateGroups(from bookmarks: [Bookmark]) -> [DuplicateGroup] {
        var groups: [String: [Bookmark]] = [:]
        var order: [String] = []
        for b in bookmarks {
            let key = normalizedURL(b.url)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(b)
        }
        return order.compactMap { key -> DuplicateGroup? in
            guard let group = groups[key], group.count > 1 else { return nil }
            return DuplicateGroup(id: key, url: group[0].url, title: group[0].title, bookmarks: group)
        }
    }

    func keepDuplicate(groupID: String, keepID: String) {
        guard let groupIndex = duplicateGroups.firstIndex(where: { $0.id == groupID }) else { return }
        let group = duplicateGroups[groupIndex]
        let toDelete = group.bookmarks.filter { $0.id != keepID }

        guard let data = try? Data(contentsOf: bookmarksURL),
              var root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            duplicateGroups.remove(at: groupIndex)
            resolvedCount += 1
            return
        }

        for bookmark in toDelete {
            remove(id: bookmark.id, from: &root)
        }

        if let newData = try? PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0) {
            try? newData.write(to: bookmarksURL)
        }

        duplicateGroups.remove(at: groupIndex)
        resolvedCount += 1
    }

    func deleteAllInGroup(groupID: String) {
        guard let groupIndex = duplicateGroups.firstIndex(where: { $0.id == groupID }) else { return }
        let group = duplicateGroups[groupIndex]

        guard let data = try? Data(contentsOf: bookmarksURL),
              var root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            duplicateGroups.remove(at: groupIndex)
            resolvedCount += 1
            return
        }

        for bookmark in group.bookmarks {
            remove(id: bookmark.id, from: &root)
        }

        if let newData = try? PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0) {
            try? newData.write(to: bookmarksURL)
        }

        duplicateGroups.remove(at: groupIndex)
        resolvedCount += 1
    }

    private func remove(id: String, from node: inout [String: Any]) {
        guard let children = node["Children"] as? [[String: Any]] else { return }
        var updated: [[String: Any]] = []
        for var child in children {
            if (child["WebBookmarkUUID"] as? String) == id { continue }
            remove(id: id, from: &child)
            updated.append(child)
        }
        node["Children"] = updated
    }
}

// MARK: - WebView

struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}
}

// MARK: - Main View

struct DuplicateReviewMainView: View {
    @StateObject private var store = BookmarkStore()

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView("Loading bookmarks…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = store.loadError {
                errorView(message: err)
            } else if store.duplicateGroups.isEmpty {
                doneView
            } else {
                DuplicateGroupView(store: store, group: store.duplicateGroups[0])
            }
        }
        .frame(minWidth: 500, minHeight: 460)
        .onAppear { store.load() }
    }

    func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry") { store.load() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var doneView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            if store.resolvedCount > 0 {
                Text("All duplicates resolved!")
                    .font(.largeTitle).bold()
                Text("Resolved \(store.resolvedCount) duplicate URL\(store.resolvedCount == 1 ? "" : "s") this session.")
                    .foregroundStyle(.secondary)
            } else {
                Text("No duplicates found!")
                    .font(.largeTitle).bold()
                Text("Your bookmarks are clean.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Scan Again") { store.load() }
                Button("Done") { NSApp.terminate(nil) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Duplicate Group View

struct DuplicateGroupView: View {
    @ObservedObject var store: BookmarkStore
    let group: DuplicateGroup
    @State private var showDeleteAllConfirm = false
    @State private var refreshToken = UUID()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                let count = store.duplicateGroups.count
                Text("\(count) duplicate URL\(count == 1 ? "" : "s") to review")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // URL info
            VStack(alignment: .leading, spacing: 3) {
                Text(group.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(group.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            Text("Saved in \(group.bookmarks.count) locations — choose which one to keep:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 4)

            VStack(spacing: 0) {
                ForEach(group.bookmarks) { bookmark in
                    HStack(spacing: 12) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(bookmark.path.isEmpty ? "Bookmarks Root" : bookmark.path.joined(separator: " / "))
                            .font(.subheadline)
                        Spacer()
                        Button("Keep") {
                            store.keepDuplicate(groupID: group.id, keepID: bookmark.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)

                    Divider()
                        .padding(.leading, 48)
                }

                HStack {
                    Spacer()
                    Button("Delete All Copies") { showDeleteAllConfirm = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }

            Divider()

            // Live webpage preview
            if let url = URL(string: group.url) {
                WebView(url: url)
                    .id("\(group.url)-\(refreshToken)")
                    .overlay(alignment: .topTrailing) {
                        Button(action: { refreshToken = UUID() }) {
                            Image(systemName: "arrow.clockwise")
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                        .background(.regularMaterial, in: Circle())
                        .padding(8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("Delete All Copies?", isPresented: $showDeleteAllConfirm) {
            Button("Delete All", role: .destructive) {
                store.deleteAllInGroup(groupID: group.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all \(group.bookmarks.count) saved copies of this URL from your bookmarks.")
        }
    }
}
