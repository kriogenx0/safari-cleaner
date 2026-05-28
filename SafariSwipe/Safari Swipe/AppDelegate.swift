import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {}
    func applicationWillTerminate(_ n: Notification) {}
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
