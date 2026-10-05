import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
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
