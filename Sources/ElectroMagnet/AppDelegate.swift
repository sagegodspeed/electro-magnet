import AppKit
import ElectroMagnetCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let engine = LayoutEngine()
    let store: LayoutStore
    private var statusItem: NSStatusItem!
    private var busy = false
    private var storageError: String?
    private var lastReport = "Remember your arrangement, then select Restore when you need it back."
    private var reportWindow: NSWindow?
    private var cacheObservers: [NSObjectProtocol] = []

    override init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ElectroMagnet", isDirectory: true)
        store = LayoutStore(url: directory.appendingPathComponent("layouts.json"))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { try store.load() } catch { storageError = error.localizedDescription; lastReport = error.localizedDescription }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Electro Magnet")
        statusItem.button?.toolTip = "Electro Magnet: remember and restore windows"
        rebuildMenu()
        WindowAccess.primeVisibleWindows()
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            cacheObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { WindowAccess.primeVisibleWindows() }
            })
        }
        if !WindowAccess.trusted { showSetup() }
    }
    func menuWillOpen(_ menu: NSMenu) { if !busy { rebuildMenu() } }
    private func item(_ title: String, _ action: Selector?, id: UUID? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; item.representedObject = id
        return item
    }
    private func rebuildMenu() {
        let menu = statusItem.menu ?? NSMenu()
        menu.removeAllItems(); menu.autoenablesItems = false; menu.delegate = self
        let header = item(busy ? "Working…" : "Electro Magnet", nil); header.isEnabled = false; menu.addItem(header)
        if !WindowAccess.trusted {
            let permission = item("Accessibility permission required", #selector(setup)); menu.addItem(permission)
        }
        menu.addItem(.separator())
        let remember = item("Remember Layout…", #selector(remember))
        remember.isEnabled = !busy && WindowAccess.trusted && storageError == nil
        menu.addItem(remember)
        if store.layouts.isEmpty {
            let empty = item("No layouts saved", nil); empty.isEnabled = false; menu.addItem(empty)
        }
        for layout in store.layouts {
            let entry = item(layout.name, nil); entry.isEnabled = !busy
            let submenu = NSMenu(); submenu.autoenablesItems = false
            let restore = item("Restore", #selector(restoreLayout(_:)), id: layout.id)
            restore.isEnabled = WindowAccess.trusted && !busy
            submenu.addItem(restore)
            let detail = item("\(layout.windows.count) windows · \(Set(layout.windows.map(\.displayUUID)).count) displays", nil)
            detail.isEnabled = false; submenu.addItem(detail); submenu.addItem(.separator())
            let overwrite = item("Overwrite with Current Layout…", #selector(overwrite(_:)), id: layout.id)
            overwrite.isEnabled = WindowAccess.trusted && storageError == nil && !busy
            submenu.addItem(overwrite)
            submenu.addItem(item("Rename…", #selector(rename(_:)), id: layout.id))
            submenu.addItem(item("Delete…", #selector(deleteLayout(_:)), id: layout.id))
            entry.submenu = submenu; menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(item("Last Result…", #selector(showResult)))
        menu.addItem(item("Setup & About…", #selector(setup)))
        menu.addItem(.separator()); menu.addItem(item("Quit Electro Magnet", #selector(quit)))
        statusItem.menu = menu
    }

    @objc private func remember() {
        guard let name = askName(title: "Remember Layout", value: "My Layout") else { return }
        capture(name: name)
    }
    private func capture(name: String, replacing id: UUID? = nil) {
        busy = true; rebuildMenu()
        Task { @MainActor in
            do {
                let captured = try engine.capture()
                let layout = try store.save(name: name, windows: captured.windows, replacing: id)
                lastReport = "Remembered \(layout.windows.count) windows in “\(layout.name)”.\n\n" +
                    (captured.omissions.isEmpty ? "No windows were moved." : "Not remembered:\n" + captured.omissions.joined(separator: "\n"))
            } catch { lastReport = error.localizedDescription }
            busy = false; rebuildMenu(); showResult()
        }
    }
    @objc private func restoreLayout(_ sender: NSMenuItem) {
        guard !busy, let id = sender.representedObject as? UUID,
              let layout = store.layouts.first(where: { $0.id == id }) else { return }
        busy = true; rebuildMenu()
        Task { @MainActor in
            do { lastReport = "Restore “\(layout.name)”\n\n" + (try await engine.restore(layout)).text }
            catch { lastReport = error.localizedDescription }
            busy = false; rebuildMenu(); showResult()
        }
    }
    @objc private func overwrite(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let layout = store.layouts.first(where: { $0.id == id }) else { return }
        let alert = NSAlert(); alert.messageText = "Overwrite “\(layout.name)”?"
        alert.informativeText = "Replace its remembered arrangement with the current windows across all Spaces."
        alert.addButton(withTitle: "Overwrite"); alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { capture(name: layout.name, replacing: id) }
    }
    @objc private func rename(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let layout = store.layouts.first(where: { $0.id == id }),
              let name = askName(title: "Rename Layout", value: layout.name) else { return }
        do { try store.rename(id: id, to: name); rebuildMenu() }
        catch { lastReport = error.localizedDescription; showResult() }
    }
    @objc private func deleteLayout(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let layout = store.layouts.first(where: { $0.id == id }) else { return }
        let alert = NSAlert(); alert.messageText = "Delete “\(layout.name)”?"
        alert.informativeText = "Your windows will stay where they are."
        alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            do { try store.delete(id: id); rebuildMenu() } catch { lastReport = error.localizedDescription; showResult() }
        }
    }
    private func askName(title: String, value: String) -> String? {
        let alert = NSAlert(); alert.messageText = title
        let input = NSTextField(string: value); input.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = input; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true); alert.window.initialFirstResponder = input
        return alert.runModal() == .alertFirstButtonReturn ? input.stringValue : nil
    }
    @objc private func setup() { showSetup() }
    private func showSetup() {
        let alert = NSAlert(); alert.messageText = "Electro Magnet"
        alert.informativeText = "Arrange your windows with Magnet, then choose Remember Layout from the menu bar. Choose Restore to recover that arrangement across monitors and desktop Spaces.\n\nEnable Electro Magnet in System Settings → Privacy & Security → Accessibility (Device Control & Data Access on macOS 27). If it is missing, use + to add this app. Return here after enabling it.\n\nIf Last Result reports windows that could not be inspected, visit each Space once and Remember again. Some browsers expose their windows only after that Space is visited.\n\nNothing moves automatically. Existing browser tabs and logged-in sessions stay open.\n\nSpace restoration uses limited private macOS APIs and may need updating after macOS upgrades. No SIP changes or privileged helper are required.\n\nLayouts are stored locally in Application Support/ElectroMagnet."
        alert.addButton(withTitle: WindowAccess.trusted ? "Done" : "Open System Settings")
        if !WindowAccess.trusted { alert.addButton(withTitle: "Later") }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn && !WindowAccess.trusted {
            WindowAccess.requestPermission()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        if let storageError { lastReport = storageError; showResult() }
    }
    @objc private func showResult() {
        if reportWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 380),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Electro Magnet · Last Result"; window.isReleasedWhenClosed = false
            let scroll = NSScrollView(frame: window.contentView!.bounds); scroll.autoresizingMask = [.width, .height]
            scroll.hasVerticalScroller = true; scroll.borderType = .noBorder
            let text = NSTextView(frame: scroll.bounds); text.isEditable = false; text.isSelectable = true
            text.font = .systemFont(ofSize: 13); text.textContainerInset = NSSize(width: 16, height: 16)
            text.isVerticallyResizable = true; text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
            scroll.documentView = text; window.contentView?.addSubview(scroll)
            window.center(); reportWindow = window
        }
        if let scroll = reportWindow?.contentView?.subviews.first as? NSScrollView,
           let text = scroll.documentView as? NSTextView { text.string = lastReport }
        NSApp.activate(ignoringOtherApps: true); reportWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
