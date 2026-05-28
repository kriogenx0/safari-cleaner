import Cocoa
import SafariServices

class ViewController: NSViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    @IBAction func openExtensionPrefs(_ sender: Any?) {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: "com.alexv.safari-swipe.Extension") { _ in }
    }
}
