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
    @Published var pending: [Bookmark] = []
    @Published var isLoading = false
    @Published var loadError: String?
    @Published var resolvedCount = 0
    @Published var keptCount = 0
    @Published var deletedCount = 0
    @Published var showSamePathPrompt = false
    @Published var samePathDuplicateCount = 0
    @Published var canUndoDuplicates = false
    @Published var canUndoReviewAll = false

    private struct DuplicateSnapshot {
        let plistData: Data?
        let groups: [DuplicateGroup]
        let pending: [Bookmark]
        let resolvedCount: Int
    }
    private struct ReviewAllSnapshot {
        let plistData: Data?
        let keptIDs: [String]
        let pending: [Bookmark]
        let keptCount: Int
        let deletedCount: Int
    }
    private var duplicateUndoStack: [DuplicateSnapshot] = []
    private var reviewAllUndoStack: [ReviewAllSnapshot] = []

    private let bookmarksURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Safari/Bookmarks.plist")

    private let keptKey = "com.safariCleaner.keptBookmarks"

    private var keptIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: keptKey) ?? [])
    }

    var isSafariRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Safari" }
    }

    func load() {
        duplicateUndoStack = []
        reviewAllUndoStack = []
        canUndoDuplicates = false
        canUndoReviewAll = false
        isLoading = true
        loadError = nil
        resolvedCount = 0
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

        // Count same-path duplicates for the toolbar button
        samePathDuplicateCount = samePathDuplicateIDs().count

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

    // MARK: Duplicate actions

    func deduceSamePath() {
        guard let data = try? Data(contentsOf: bookmarksURL),
              var root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            showSamePathPrompt = false
            return
        }

        // Within each group, delete any bookmark whose (url, path) combo was already seen
        let toDeleteIDs = samePathDuplicateIDs()

        for id in toDeleteIDs { remove(id: id, from: &root) }

        if let newData = try? PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0) {
            try? newData.write(to: bookmarksURL)
        }

        let previousResolved = resolvedCount + toDeleteIDs.count
        showSamePathPrompt = false
        load()
        resolvedCount = previousResolved
    }

    private func samePathDuplicateIDs() -> [String] {
        var toDelete: [String] = []
        for group in duplicateGroups {
            var seen = Set<String>()
            for b in group.bookmarks {
                let key = b.url + "|" + b.path.joined(separator: "/")
                if seen.contains(key) { toDelete.append(b.id) } else { seen.insert(key) }
            }
        }
        return toDelete
    }

    func undoLastDuplicateAction() {
        guard let snap = duplicateUndoStack.popLast() else { return }
        canUndoDuplicates = !duplicateUndoStack.isEmpty
        if let data = snap.plistData { try? data.write(to: bookmarksURL) }
        duplicateGroups = snap.groups
        pending = snap.pending
        resolvedCount = snap.resolvedCount
    }

    func undoLastReviewAllAction() {
        guard let snap = reviewAllUndoStack.popLast() else { return }
        canUndoReviewAll = !reviewAllUndoStack.isEmpty
        if let data = snap.plistData { try? data.write(to: bookmarksURL) }
        UserDefaults.standard.set(snap.keptIDs, forKey: keptKey)
        pending = snap.pending
        keptCount = snap.keptCount
        deletedCount = snap.deletedCount
    }

    private func pushDuplicateSnapshot(plistData: Data? = nil) {
        duplicateUndoStack.append(DuplicateSnapshot(
            plistData: plistData, groups: duplicateGroups,
            pending: pending, resolvedCount: resolvedCount))
        if duplicateUndoStack.count > 50 { duplicateUndoStack.removeFirst() }
        canUndoDuplicates = true
    }

    private func pushReviewAllSnapshot(plistData: Data? = nil) {
        reviewAllUndoStack.append(ReviewAllSnapshot(
            plistData: plistData,
            keptIDs: UserDefaults.standard.stringArray(forKey: keptKey) ?? [],
            pending: pending, keptCount: keptCount, deletedCount: deletedCount))
        if reviewAllUndoStack.count > 50 { reviewAllUndoStack.removeFirst() }
        canUndoReviewAll = true
    }

    func skipGroup(groupID: String) {
        pushDuplicateSnapshot()
        guard let index = duplicateGroups.firstIndex(where: { $0.id == groupID }) else { return }
        let group = duplicateGroups.remove(at: index)
        duplicateGroups.append(group)
    }

    func keepDuplicate(groupID: String, keepID: String) {
        guard let groupIndex = duplicateGroups.firstIndex(where: { $0.id == groupID }) else { return }
        pushDuplicateSnapshot(plistData: try? Data(contentsOf: bookmarksURL))
        let group = duplicateGroups[groupIndex]
        let toDelete = group.bookmarks.filter { $0.id != keepID }

        guard let data = try? Data(contentsOf: bookmarksURL),
              var root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            duplicateGroups.remove(at: groupIndex)
            resolvedCount += 1
            return
        }

        for bookmark in toDelete { remove(id: bookmark.id, from: &root) }

        if let newData = try? PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0) {
            try? newData.write(to: bookmarksURL)
        }

        let deletedIDs = Set(toDelete.map { $0.id })
        pending.removeAll { deletedIDs.contains($0.id) }
        duplicateGroups.remove(at: groupIndex)
        resolvedCount += 1
    }

    func deleteAllInGroup(groupID: String) {
        guard let groupIndex = duplicateGroups.firstIndex(where: { $0.id == groupID }) else { return }
        pushDuplicateSnapshot(plistData: try? Data(contentsOf: bookmarksURL))
        let group = duplicateGroups[groupIndex]

        guard let data = try? Data(contentsOf: bookmarksURL),
              var root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            duplicateGroups.remove(at: groupIndex)
            resolvedCount += 1
            return
        }

        for bookmark in group.bookmarks { remove(id: bookmark.id, from: &root) }

        if let newData = try? PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0) {
            try? newData.write(to: bookmarksURL)
        }

        let deletedIDs = Set(group.bookmarks.map { $0.id })
        pending.removeAll { deletedIDs.contains($0.id) }
        duplicateGroups.remove(at: groupIndex)
        resolvedCount += 1
    }

    // MARK: Review All actions

    func keep() {
        pushReviewAllSnapshot()
        guard !pending.isEmpty else { return }
        let id = pending.removeFirst().id
        var ids = UserDefaults.standard.stringArray(forKey: keptKey) ?? []
        ids.append(id)
        UserDefaults.standard.set(ids, forKey: keptKey)
        keptCount += 1
    }

    func delete() {
        pushReviewAllSnapshot(plistData: try? Data(contentsOf: bookmarksURL))
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

    func clearKeptAndReload() {
        UserDefaults.standard.removeObject(forKey: keptKey)
        load()
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

final class WebViewState: ObservableObject {
    @Published var progress: Double = 0
    @Published var currentURL: String = ""
}

struct WebView: NSViewRepresentable {
    let url: URL
    let state: WebViewState

    class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: String = ""
        var observation: NSKeyValueObservation?
        weak var state: WebViewState?
        deinit { observation?.invalidate() }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, let scheme = url.scheme?.lowercased() else {
                decisionHandler(.allow)
                return
            }
            switch scheme {
            case "http", "https", "about", "data", "blob", "javascript":
                decisionHandler(.allow)
            default:
                NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            state?.progress = 0
            let msg = error.localizedDescription
            let html = "<html><body style=\"font-family:-apple-system,sans-serif;"
                + "text-align:center;padding-top:80px;color:#666;background:#f5f5f5\">"
                + "<h2 style=\"color:#333\">Page couldn't be loaded</h2>"
                + "<p>" + msg + "</p></body></html>"
            webView.loadHTMLString(html, baseURL: nil)
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            state?.progress = 0
            let msg = error.localizedDescription
            let html = "<html><body style=\"font-family:-apple-system,sans-serif;"
                + "text-align:center;padding-top:80px;color:#666;background:#f5f5f5\">"
                + "<h2 style=\"color:#333\">Page couldn't be loaded</h2>"
                + "<p>" + msg + "</p></body></html>"
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        view.navigationDelegate = context.coordinator
        context.coordinator.state = state
        let c = context.coordinator
        context.coordinator.observation = view.observe(\.estimatedProgress, options: [.new]) { [weak c] wv, _ in
            let p = wv.estimatedProgress
            let u = wv.url?.absoluteString ?? ""
            DispatchQueue.main.async {
                c?.state?.progress = p
                if !u.isEmpty { c?.state?.currentURL = u }
            }
        }
        view.load(URLRequest(url: url))
        context.coordinator.loadedURL = url.absoluteString
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.state = state
        guard context.coordinator.loadedURL != url.absoluteString else { return }
        view.evaluateJavaScript("document.querySelectorAll('video,audio').forEach(m => m.pause())")
        view.load(URLRequest(url: url))
        context.coordinator.loadedURL = url.absoluteString
    }
}

// MARK: - Main View

enum ReviewTab { case duplicates, reviewAll }

struct MainView: View {
    @StateObject private var store = BookmarkStore()
    @State private var selectedTab: ReviewTab = .duplicates

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView("Loading bookmarks…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = store.loadError {
                errorView(message: err)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Picker("", selection: $selectedTab) {
                            Text("Review Duplicates").tag(ReviewTab.duplicates)
                            Text("Review All").tag(ReviewTab.reviewAll)
                        }
                        .pickerStyle(.segmented)
                        if store.samePathDuplicateCount > 0 {
                            Button("Remove \(store.samePathDuplicateCount) Same-Path") {
                                store.showSamePathPrompt = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)

                    Divider()

                    if store.isSafariRunning {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Safari is open. Close it before making changes, or they may be overwritten.")
                                .font(.caption)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(.orange.opacity(0.08))
                        Divider()
                    }

                    switch selectedTab {
                    case .duplicates:
                        if store.duplicateGroups.isEmpty {
                            duplicatesDoneView
                        } else {
                            DuplicateGroupView(store: store, group: store.duplicateGroups[0])
                        }
                    case .reviewAll:
                        if store.pending.isEmpty {
                            reviewAllDoneView
                        } else {
                            ReviewAllView(store: store)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 460)
        .onAppear { store.load() }
        .alert("Remove Exact Duplicates?", isPresented: $store.showSamePathPrompt) {
            Button("Remove \(store.samePathDuplicateCount)", role: .destructive) { store.deduceSamePath() }
            Button("Skip", role: .cancel) { store.showSamePathPrompt = false }
        } message: {
            Text("Found \(store.samePathDuplicateCount) bookmark\(store.samePathDuplicateCount == 1 ? "" : "s") that are exact copies saved in the same folder. Remove the extras and keep one of each?")
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

    var duplicatesDoneView: some View {
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
            Button("Scan Again") { store.load() }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var reviewAllDoneView: some View {
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
}

// MARK: - Duplicate Group View

struct DuplicateGroupView: View {
    @ObservedObject var store: BookmarkStore
    let group: DuplicateGroup
    @StateObject private var webState = WebViewState()
    @State private var refreshToken = UUID()
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            VStack(spacing: 6) {
                let total = store.resolvedCount + store.duplicateGroups.count
                ProgressView(value: Double(store.resolvedCount), total: Double(max(total, 1)))
                HStack {
                    Text("\(store.resolvedCount) reviewed")
                    Spacer()
                    Text("\(store.duplicateGroups.count) remaining")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            // Title + URL + actions
            HStack(alignment: .top, spacing: 12) {
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
                Button(action: { store.skipGroup(groupID: group.id) }) {
                    keyHintLabel("Skip", hints: "s")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(action: { store.deleteAllInGroup(groupID: group.id) }) {
                    keyHintLabel("Delete All Copies", hints: "d")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            Text("Saved in \(group.bookmarks.count) locations — choose which one to keep:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 4)

            VStack(spacing: 0) {
                ForEach(Array(group.bookmarks.enumerated()), id: \.element.id) { index, bookmark in
                    HStack(spacing: 12) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(bookmark.path.isEmpty ? "Bookmarks Root" : bookmark.path.joined(separator: " / "))
                            .font(.subheadline)
                        Spacer()
                        keepButton(for: bookmark, index: index)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    Divider()
                        .padding(.leading, 48)
                }
            }

            // Hint footer
            Text("⌘Z Back    1–\(min(group.bookmarks.count, 9)) Keep    D Delete All    S Skip")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.vertical, 6)

            Divider()

            // Preview toolbar
            HStack {
                Button(action: { refreshToken = UUID() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                let displayURL = webState.currentURL.isEmpty ? group.url : webState.currentURL
                Text(displayURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
                if let u = URL(string: group.url) {
                    Button(action: { NSWorkspace.shared.open(u, configuration: NSWorkspace.OpenConfiguration()) }) {
                        Image(systemName: "safari")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * webState.progress, height: 2)
                        .opacity(webState.progress > 0 && webState.progress < 1 ? 1 : 0)
                }
                .frame(height: 2)
            }

            Divider()

            if let url = URL(string: group.url) {
                WebView(url: url, state: webState)
                    .id("\(group.url)-\(refreshToken)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            let s = store
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty ||
                      (event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z")
                else { return event }
                let chars = event.charactersIgnoringModifiers ?? ""
                if event.modifierFlags.contains(.command) && chars == "z" {
                    s.undoLastDuplicateAction(); return nil
                }
                guard let gid = s.duplicateGroups.first?.id else { return event }
                switch chars {
                case "s": s.skipGroup(groupID: gid); return nil
                case "d": s.deleteAllInGroup(groupID: gid); return nil
                default:
                    if let n = Int(chars), n >= 1, n <= 9,
                       let g = s.duplicateGroups.first, n - 1 < g.bookmarks.count {
                        s.keepDuplicate(groupID: gid, keepID: g.bookmarks[n - 1].id)
                        return nil
                    }
                    return event
                }
            }
        }
        .onDisappear {
            if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
        }
    }

    @ViewBuilder
    private func keepButton(for bookmark: Bookmark, index: Int) -> some View {
        Button(action: { store.keepDuplicate(groupID: group.id, keepID: bookmark.id) }) {
            keyHintLabel("Keep", hints: index < 9 ? "\(index + 1)" : "")
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.small)
    }

    private func keyHintLabel(_ title: String, hints: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
            if !hints.isEmpty {
                Text(hints)
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
    }
}

// MARK: - Review All View

struct ReviewAllView: View {
    @ObservedObject var store: BookmarkStore
    @StateObject private var webState = WebViewState()
    @State private var refreshToken = UUID()
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            VStack(spacing: 6) {
                let reviewed = store.keptCount + store.deletedCount
                let total = reviewed + store.pending.count
                ProgressView(value: Double(reviewed), total: Double(total))
                HStack {
                    Text("\(reviewed) reviewed")
                    Spacer()
                    Text("\(store.pending.count) remaining")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            if let bookmark = store.pending.first {
                VStack(alignment: .leading, spacing: 3) {
                    Text(bookmark.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(bookmark.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider()

                if let url = URL(string: bookmark.url) {
                    // Preview toolbar
                    HStack {
                        Button(action: { refreshToken = UUID() }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        let displayURL = webState.currentURL.isEmpty ? bookmark.url : webState.currentURL
                        Text(displayURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity)
                        Button(action: { NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) }) {
                            Image(systemName: "safari")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * webState.progress, height: 2)
                                .opacity(webState.progress > 0 && webState.progress < 1 ? 1 : 0)
                        }
                        .frame(height: 2)
                    }

                    Divider()

                    WebView(url: url, state: webState)
                        .id("\(bookmark.id)-\(refreshToken)")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Divider()

                HStack(spacing: 16) {
                    Button(action: { store.delete() }) {
                        HStack(spacing: 4) {
                            Label("Delete", systemImage: "trash").frame(maxWidth: .infinity)
                            Text("d").font(.caption2).foregroundStyle(.secondary.opacity(0.8))
                        }
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Button(action: { store.keep() }) {
                        HStack(spacing: 4) {
                            Label("Keep", systemImage: "checkmark").frame(maxWidth: .infinity)
                            Text("k").font(.caption2).foregroundStyle(.secondary.opacity(0.8))
                        }
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .padding(20)

                Text("⌘Z Back    D Delete    K Keep")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 8)
            }
        }
        .onAppear {
            let s = store
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty ||
                      (event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z")
                else { return event }
                let chars = event.charactersIgnoringModifiers ?? ""
                if event.modifierFlags.contains(.command) && chars == "z" {
                    s.undoLastReviewAllAction(); return nil
                }
                switch chars {
                case "d": s.delete(); return nil
                case "k": s.keep(); return nil
                default: return event
                }
            }
        }
        .onDisappear {
            if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
        }
    }
}
