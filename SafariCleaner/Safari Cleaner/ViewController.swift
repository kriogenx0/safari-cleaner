import Cocoa
import SwiftUI

// MARK: - Model

struct Bookmark: Identifiable {
    let id: String
    let title: String
    let url: String
}

// MARK: - Store

@MainActor
class BookmarkStore: ObservableObject {
    @Published var pending: [Bookmark] = []
    @Published var isLoading = false
    @Published var loadError: String?
    @Published var keptCount = 0
    @Published var deletedCount = 0
    @Published var duplicateCount = 0
    @Published var showDedupeConfirm = false

    private let bookmarksURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Safari/Bookmarks.plist")

    private let keptKey = "com.safariCleaner.keptBookmarks"

    private var keptIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: keptKey) ?? [])
    }

    func load() {
        isLoading = true
        loadError = nil
        keptCount = 0
        deletedCount = 0

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
        collect(node: root, into: &all)
        duplicateCount = countDuplicates(in: all)
        let kept = keptIDs
        pending = all.filter { !kept.contains($0.id) }
        isLoading = false
    }

    private func collect(node: [String: Any], into result: inout [Bookmark]) {
        if let type = node["WebBookmarkType"] as? String,
           type == "WebBookmarkTypeLeaf",
           let urlString = node["URLString"] as? String,
           let uuid = node["WebBookmarkUUID"] as? String {
            let title: String
            if let d = node["URIDictionary"] as? [String: Any],
               let t = d["title"] as? String, !t.isEmpty {
                title = t
            } else {
                title = urlString
            }
            result.append(Bookmark(id: uuid, title: title, url: urlString))
        }
        if let children = node["Children"] as? [[String: Any]] {
            for child in children { collect(node: child, into: &result) }
        }
    }

    // Normalize for duplicate comparison: lowercase, strip trailing slash
    private func normalizedURL(_ url: String) -> String {
        var s = url.lowercased()
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func countDuplicates(in bookmarks: [Bookmark]) -> Int {
        var seen = Set<String>()
        var count = 0
        for b in bookmarks {
            let key = normalizedURL(b.url)
            if seen.contains(key) { count += 1 } else { seen.insert(key) }
        }
        return count
    }

    func dedupeAll() {
        let removed = duplicateCount

        guard let data = try? Data(contentsOf: bookmarksURL),
              var root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }

        var seen = Set<String>()
        removeDuplicates(from: &root, seen: &seen)

        if let newData = try? PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0) {
            try? newData.write(to: bookmarksURL)
        }

        load()
        deletedCount = removed
    }

    private func removeDuplicates(from node: inout [String: Any], seen: inout Set<String>) {
        guard let children = node["Children"] as? [[String: Any]] else { return }
        var updated: [[String: Any]] = []
        for var child in children {
            if let type = child["WebBookmarkType"] as? String,
               type == "WebBookmarkTypeLeaf",
               let url = child["URLString"] as? String {
                let key = normalizedURL(url)
                if seen.contains(key) { continue }
                seen.insert(key)
            }
            removeDuplicates(from: &child, seen: &seen)
            updated.append(child)
        }
        node["Children"] = updated
    }

    func keep() {
        guard !pending.isEmpty else { return }
        let id = pending.removeFirst().id
        var ids = UserDefaults.standard.stringArray(forKey: keptKey) ?? []
        ids.append(id)
        UserDefaults.standard.set(ids, forKey: keptKey)
        keptCount += 1
    }

    func delete() {
        guard !pending.isEmpty else { return }
        let bookmark = pending.removeFirst()

        guard let data = try? Data(contentsOf: bookmarksURL),
              var root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            deletedCount += 1
            return
        }

        remove(id: bookmark.id, from: &root)

        if let newData = try? PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0) {
            try? newData.write(to: bookmarksURL)
        }
        deletedCount += 1
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

    func clearKeptAndReload() {
        UserDefaults.standard.removeObject(forKey: keptKey)
        load()
    }
}

// MARK: - Views

struct BookmarkReviewView: View {
    @StateObject private var store = BookmarkStore()

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView("Loading bookmarks…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = store.loadError {
                errorView(message: err)
            } else if store.pending.isEmpty {
                doneView
            } else {
                reviewView
            }
        }
        .frame(minWidth: 460, minHeight: 420)
        .onAppear { store.load() }
        .alert(
            "Remove \(store.duplicateCount) Duplicate Bookmark\(store.duplicateCount == 1 ? "" : "s")?",
            isPresented: $store.showDedupeConfirm
        ) {
            Button("Remove", role: .destructive) { store.dedupeAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeps the first occurrence of each URL and deletes the rest.")
        }
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
            Text("All done!")
                .font(.largeTitle).bold()
            if store.keptCount + store.deletedCount > 0 {
                Text("Kept \(store.keptCount) · Deleted \(store.deletedCount) this session.")
                    .foregroundStyle(.secondary)
            } else {
                Text("No bookmarks left to review.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Review All Again") { store.clearKeptAndReload() }
                Button("Done") { NSApp.terminate(nil) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var dupeBanner: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundStyle(.orange)
                Text("\(store.duplicateCount) duplicate URL\(store.duplicateCount == 1 ? "" : "s") found")
                    .font(.subheadline)
                Spacer()
                Button("Remove Duplicates") { store.showDedupeConfirm = true }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.orange.opacity(0.08))

            Divider()
        }
    }

    var reviewView: some View {
        VStack(spacing: 0) {
            // Progress header
            VStack(spacing: 6) {
                let reviewed = store.keptCount + store.deletedCount
                let total = reviewed + store.pending.count
                ProgressView(value: Double(reviewed), total: Double(total))
                HStack {
                    Text("\(store.pending.count) remaining")
                    Spacer()
                    Text("\(reviewed) reviewed")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            if store.duplicateCount > 0 {
                dupeBanner
            }

            // Bookmark card
            if let bookmark = store.pending.first {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(bookmark.title)
                            .font(.title2).bold()
                            .fixedSize(horizontal: false, vertical: true)
                        if let url = URL(string: bookmark.url) {
                            Link(destination: url) {
                                Text(bookmark.url)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Text(bookmark.url)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
                .frame(maxHeight: .infinity)
            }

            Divider()

            // Action buttons
            HStack(spacing: 16) {
                Button(action: { store.delete() }) {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button(action: { store.keep() }) {
                    Label("Keep", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .padding(20)

            Text("← Delete    Keep →")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
    }
}
