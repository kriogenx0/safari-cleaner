import SwiftUI

@main
struct SafariCleanerApp: App {
    var body: some Scene {
        WindowGroup {
            DuplicateReviewMainView()
        }
        .defaultSize(width: 580, height: 680)
    }
}
