import AppKit

@MainActor
final class PulseApplicationDelegate: NSObject, NSApplicationDelegate {
    var reopen: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let file=Bundle.main.object(forInfoDictionaryKey:"CFBundleIconFile") as? String,
           let resources=Bundle.main.resourceURL,
           let icon=NSImage(contentsOf:resources.appendingPathComponent(file)) {
            NSApp.applicationIconImage=icon
        }
        Self.applyDockVisibility(UserDefaults.standard.object(forKey:"showInDock") as? Bool ?? true)
    }

    static func activationPolicy(showInDock:Bool) -> NSApplication.ActivationPolicy {
        showInDock ? .regular:.accessory
    }

    static func applyDockVisibility(_ visible:Bool) {
        NSApp.setActivationPolicy(activationPolicy(showInDock:visible))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopen?()
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu=NSMenu()
        let show=NSMenuItem(title:"打开 Codex Pulse",action:#selector(showWindow),keyEquivalent:"")
        show.target=self
        menu.addItem(show)
        let hide=NSMenuItem(title:"隐藏 Codex Pulse",action:#selector(NSApplication.hide(_:)),keyEquivalent:"")
        hide.target=sender
        menu.addItem(hide)
        return menu
    }

    @objc private func showWindow() {reopen?()}
}
