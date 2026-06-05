import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        let vc = ViewController()
        let win = NSWindow(
            contentRect: NSRect(x: 196, y: 200, width: 480, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.minSize = NSSize(width: 380, height: 400)
        win.title = "Safari Cleaner"
        win.contentViewController = vc
        win.makeKeyAndOrderFront(nil)
        window = win
    }

    func applicationWillTerminate(_ n: Notification) {}
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
