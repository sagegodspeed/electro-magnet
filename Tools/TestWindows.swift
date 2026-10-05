import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let statePath = CommandLine.arguments[1]
let commandPath = CommandLine.arguments[2]
var windows: [NSWindow] = []
for index in 0..<2 {
    let screen = NSScreen.screens[index % NSScreen.screens.count]
    let rect = NSRect(x: screen.visibleFrame.minX + 100 + CGFloat(index * 50),
                      y: screen.visibleFrame.minY + 100, width: 500, height: 330)
    let window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false, screen: screen)
    window.title = "Electro Magnet test \(index + 1)"
    window.minSize = NSSize(width: 240, height: 180)
    window.isReleasedWhenClosed = false
    let label = NSTextField(labelWithString: "Disposable test window. Your working windows are not part of this test.")
    label.frame = NSRect(x: 20, y: 100, width: 460, height: 80)
    label.maximumNumberOfLines = 3
    window.contentView?.addSubview(label)
    window.orderFrontRegardless()
    windows.append(window)
}
let panel = NSPanel(contentRect: NSRect(x: 50, y: 80, width: 280, height: 100), styleMask: [.titled, .utilityWindow], backing: .buffered, defer: false)
panel.title = "Electro Magnet unsupported test panel"; panel.orderFrontRegardless()
var lastCommand = ""
let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
    if let data = try? Data(contentsOf: URL(fileURLWithPath: commandPath)),
       let command = String(data: data, encoding: .utf8), command != lastCommand {
        lastCommand = command
        if command == "close-second" { windows[1].close() }
        if command == "change-titles" { windows.forEach { $0.title = "Changed browser tab title" } }
        if command == "quit" { app.terminate(nil) }
    }
    let records = windows.filter(\.isVisible).map { ["windowID": $0.windowNumber, "title": $0.title] as [String: Any] }
    let data = try! JSONSerialization.data(withJSONObject: ["pid": ProcessInfo.processInfo.processIdentifier, "windows": records])
    try? data.write(to: URL(fileURLWithPath: statePath), options: .atomic)
}
app.run()
