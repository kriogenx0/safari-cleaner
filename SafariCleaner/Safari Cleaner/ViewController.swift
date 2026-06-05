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
    @Published var pending: [Bookmark] = []
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var isLoading = false
    @Published var loadError: String?
    @Published var keptCount = 0
    @Published var deletedCount = 0

    private var duplicateWindow: NSWindow?

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
        collect(node: root, path: [], into: &all)
        duplicateGroups = computeDuplicateGroups(from: all)
        let kept = keptIDs
        pending = all.filter { !kept.contains($0.id) }
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

    func openDuplicateReviewWindow() {
        if let w = duplicateWindow, w.isVisible { w.makeKeyAndOrderFront(nil); return }
        let controller = NSHostingController(rootView: DuplicatesWindowView(store: self))
        let window = NSWindow(contentViewController: controller)
        window.title = "Review Duplicates"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 580))
        window.minSize = NSSize(width: 440, height: 420)
        window.center()
        window.makeKeyAndOrderFront(nil)
        duplicateWindow = window
    }

    func closeDuplicateWindow() {
        duplicateWindow?.close()
        duplicateWindow = nil
    }

    func keepDuplicate(groupID: String, keepID: String) {
        guard let groupIndex = duplicateGroups.firstIndex(where: { $0.id == groupID }) else { return }
        let group = duplicateGroups[groupIndex]
        let toDelete = group.bookmarks.filter { $0.id != keepID }

        guard let data = try? Data(contentsOf: bookmarksURL),
              var root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            duplicateGroups.remove(at: groupIndex)
            return
        }

        for bookmark in toDelete {
            remove(id: bookmark.id, from: &root)
        }

        if let newData = try? PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0) {
            try? newData.write(to: bookmarksURL)
        }

        let deletedIDs = Set(toDelete.map { $0.id })
        pending.removeAll { deletedIDs.contains($0.id) }
        deletedCount += toDelete.count
        duplicateGroups.remove(at: groupIndex)
    }

    func deleteAllInGroup(groupID: String) {
        guard let groupIndex = duplicateGroups.firstIndex(where: { $0.id == groupID }) else { return }
        let group = duplicateGroups[groupIndex]

        guard let data = try? Data(contentsOf: bookmarksURL),
              var root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            duplicateGroups.remove(at: groupIndex)
            return
        }

        for bookmark in group.bookmarks {
            remove(id: bookmark.id, from: &root)
        }

        if let newData = try? PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0) {
            try? newData.write(to: bookmarksURL)
        }

        let deletedIDs = Set(group.bookmarks.map { $0.id })
        pending.removeAll { deletedIDs.contains($0.id) }
        deletedCount += group.bookmarks.count
        duplicateGroups.remove(at: groupIndex)
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

// MARK: - WebView

struct WebView: NSViewRepresentable {
    let url: URL

    class Coordinator {
        var loadedURL: String = ""
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.load(URLRequest(url: url))
        context.coordinator.loadedURL = url.absoluteString
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url.absoluteString else { return }
        view.load(URLRequest(url: url))
        context.coordinator.loadedURL = url.absoluteString
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
                let count = store.duplicateGroups.count
                Text("\(count) URL\(count == 1 ? "" : "s") saved in multiple locations")
                    .font(.subheadline)
                Spacer()
                Button("Review Duplicates") { store.openDuplicateReviewWindow() }
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

            if !store.duplicateGroups.isEmpty {
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

// MARK: - Duplicates Window

struct DuplicatesWindowView: View {
    @ObservedObject var store: BookmarkStore

    var body: some View {
        if store.duplicateGroups.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("All duplicates resolved!")
                    .font(.title2).bold()
                Button("Done") { store.closeDuplicateWindow() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            DuplicateGroupView(store: store, group: store.duplicateGroups[0])
        }
    }
}

struct DuplicateGroupView: View {
    @ObservedObject var store: BookmarkStore
    let group: DuplicateGroup
    @State private var showDeleteAllConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                let count = store.duplicateGroups.count
                Text("\(count) duplicate URL\(count == 1 ? "" : "s") to review")
                    .font(.headline)
                Spacer()
                Button("Close") { store.closeDuplicateWindow() }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // URL info + path list
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

            ScrollView {
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

                    // Delete all option
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
            }
            .frame(maxHeight: 220)

            Divider()

            // Live webpage preview at the bottom
            if let url = URL(string: group.url) {
                WebView(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 440, minHeight: 420)
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
