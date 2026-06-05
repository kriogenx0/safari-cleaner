import SwiftUI

@main
struct SafariCleanerApp: App {
    var body: some Scene {
        WindowGroup {
            BookmarkReviewView()
        }
        .defaultSize(width: 480, height: 500)
    }
}
