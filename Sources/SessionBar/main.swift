import AppKit

let arguments = CommandLine.arguments

if arguments.contains(HookInstaller.flag) {
    exit(HookHandler.run())
}

if arguments.contains("--install-hooks") || arguments.contains("--uninstall-hooks") {
    do {
        if arguments.contains("--install-hooks") {
            try HookInstaller.install()
            print("Hooks installed: \(HookInstaller.command)")
        } else {
            try HookInstaller.uninstall()
            print("Hooks removed from ~/.claude/settings.json")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
