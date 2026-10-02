import AppKit
import SwiftUI
import NotchCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var state: AppState!
    var controller: PanelController!
    var settingsWindow: NSWindow?
    var statusItem: NSStatusItem?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if InstallationLocation.classify(Bundle.main.bundleURL).mustInstallBeforePermissions {
            let alert = NSAlert()
            alert.messageText = "Install NotchHarbor before setting it up"
            alert.informativeText = "Drag NotchHarbor.app into Applications from the disk image, eject the disk image, then open the installed copy. This keeps privacy permissions attached to one copy of the app."
            alert.addButton(withTitle: "Open Applications")
            alert.addButton(withTitle: "Quit")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true)) }
            NSApp.terminate(nil)
            return
        }
        state = AppState(); controller = PanelController(state: state)
        state.openSettings = { [weak self] in self?.showSettings() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "NotchHarbor")
        let menu = NSMenu()
        menu.addItem(item("Open NotchHarbor", #selector(showNotch)))
        menu.addItem(item("Settings…", #selector(settings), key: ","))
        menu.addItem(state.updates.menuItem())
        menu.addItem(.separator())
        menu.addItem(item("Toggle Keep Awake", #selector(toggleAwake)))
        menu.addItem(.separator())
        menu.addItem(item("Quit NotchHarbor", #selector(quit), key: "q"))
        statusItem?.menu = menu
        let appMenu = NSMenu(); let mainMenu = NSMenu(); let appItem = NSMenuItem()
        appMenu.addItem(item("Open NotchHarbor", #selector(showNotch), key: "o"))
        appMenu.addItem(item("Settings…", #selector(settings), key: ","))
        appMenu.addItem(state.updates.menuItem())
        appMenu.addItem(item("Quit NotchHarbor", #selector(quit), key: "q"))
        appItem.submenu = appMenu; mainMenu.addItem(appItem)
        let edit = NSMenu(title: "Edit"), editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        editItem.submenu = edit; mainMenu.addItem(editItem); NSApp.mainMenu = mainMenu
        state.updates.start()
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched"); showSettings(setup: true)
        }
        if CommandLine.arguments.contains("--show") { controller.open(keyboard: true) }
    }
    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; return item
    }
    @objc func showNotch() { controller.open(keyboard: true) }
    @objc func settings() { showSettings() }
    @objc func toggleAwake() { if state.preferences.powerEnabled { state.power.toggle() } }
    @objc func quit() { NSApp.terminate(nil) }
    func showSettings(setup: Bool = false) {
        controller.close()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 730, height: 555), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "NotchHarbor Settings"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
            window.contentView = NSHostingView(rootView: SettingsView(state: state, showSetup: setup)); window.isReleasedWhenClosed = false
            window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) { state?.shutdown() }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    if CommandLine.arguments.contains("--check-visualizer") {
        let diagnostic = AudioVisualizerDiagnostic()
        app.setActivationPolicy(.accessory)
        diagnostic.start()
        withExtendedLifetime(diagnostic) { app.run() }
    } else {
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
