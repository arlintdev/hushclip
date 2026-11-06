import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    if CommandLine.arguments.contains("--snapshot") {
        Snapshot.run(arguments: CommandLine.arguments)
    }

    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) {
        app.run()
    }
}
