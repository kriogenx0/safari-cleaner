import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        let vc = ViewController()
        let win = NSWindow(
            contentRect: NSRect(x: 196, y: 240, width: 480, height: 270),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Safari Cleaner"
        win.contentViewController = vc
        win.makeKeyAndOrderFront(nil)
        window = win
    }

    func applicationWillTerminate(_ n: Notification) {}
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
