import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        installEditKeyMonitor()
        MainActor.assumeIsolated { AppState.shared.launch() }
    }
}

extension AppDelegate {
    /// The menu-bar panel doesn't route ⌘-shortcuts through the main menu, so handle the editing keys directly.
    func installEditKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .option, .control]) == .command,
                  NSApp.keyWindow?.firstResponder is NSText else { return event }
            let action: Selector?
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "v": action = #selector(NSText.paste(_:))
            case "c": action = #selector(NSText.copy(_:))
            case "x": action = #selector(NSText.cut(_:))
            case "a": action = #selector(NSText.selectAll(_:))
            case "z": action = Selector(("undo:"))
            default: action = nil
            }
            if let action, NSApp.sendAction(action, to: nil, from: nil) { return nil }
            return event
        }
    }

    /// An accessory (menu-bar) app has no main menu, so ⌘V never reaches text fields. Give it a minimal Edit menu.
    func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Claude Avatar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
    }
}

@main
struct ClaudeAvatarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra("Claude Avatar", systemImage: "person.crop.square") {
            MenuPanel(app: state)
        }
        .menuBarExtraStyle(.window)
    }
}
