import Cocoa
import SafariServices

class ViewController: NSViewController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 270))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let button = NSButton(title: "Open Extension Preferences", target: self, action: #selector(openExtensionPrefs))
        button.bezelStyle = .rounded
        button.frame = NSRect(x: 168, y: 116, width: 144, height: 32)
        view.addSubview(button)
    }

    @objc func openExtensionPrefs(_ sender: Any?) {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: "com.alexv.safari-cleaner.Extension") { _ in }
    }
}
