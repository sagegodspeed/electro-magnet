import AppKit
import ElectroMagnetCore

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--diagnose-layout" {
        do {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ElectroMagnet", isDirectory: true)
            let store = LayoutStore(url: directory.appendingPathComponent("layouts.json"))
            try store.load()
            guard let layout = store.layouts.first(where: { $0.name == CommandLine.arguments[2] }) else { throw LayoutError.missingLayout }
            let report = try LayoutEngine().diagnostics(layout)
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            let output = URL(fileURLWithPath: CommandLine.arguments[3])
            try data.write(to: output, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
            print("Read-only layout diagnostics saved.")
            exit(0)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--integration-test",
       let pid = Int32(CommandLine.arguments[2]) {
        let directory = URL(fileURLWithPath: CommandLine.arguments[3])
        Task { @MainActor in await IntegrationTest.run(pid: pid, directory: directory) }
        app.run()
        exit(0)
    }
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
