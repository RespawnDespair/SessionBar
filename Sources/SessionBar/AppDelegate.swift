import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = SessionStore()
    private let touchBar = TouchBarController()
    private var statusItem: NSStatusItem?
    private var pollTimer: Timer?
    private var animationTimer: Timer?
    private let openOnAttentionKey = "openOnAttention"

    private var openOnAttention: Bool {
        get { UserDefaults.standard.object(forKey: openOnAttentionKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: openOnAttentionKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        try? FileManager.default.removeItem(at: SessionFiles.quitMarker)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        touchBar.onSelect = { [weak self] session in self?.open(session) }
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        touchBar.close()
    }

    private func refresh() {
        store.reload()
        touchBar.update(store.sessions, openOnAttention: openOnAttention)
        updateStatusIcon(at: Date.timeIntervalSinceReferenceDate)
        updateAnimationTimer()
    }

    private func updateAnimationTimer() {
        if store.needsAnimation, animationTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    let t = Date.timeIntervalSinceReferenceDate
                    self?.touchBar.redraw(at: t)
                    self?.updateStatusIcon(at: t)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            animationTimer = timer
        } else if !store.needsAnimation, let timer = animationTimer {
            timer.invalidate()
            animationTimer = nil
        }
    }

    private func updateStatusIcon(at t: TimeInterval) {
        statusItem?.button?.image = Appearance.summaryImage(
            store.sessions.map(\.display), at: t, height: 18, dot: 7, maxDots: 8)
    }

    // MARK: Opening a session

    private func open(_ session: DisplaySession) {
        store.markSeen(session.record.id)
        refresh()
        if session.record.isDesktop || session.record.termProgram.isEmpty {
            activate(bundleID: "com.anthropic.claudefordesktop")
            return
        }
        // Only the terminal app can be raised; picking the exact tab needs Automation access.
        switch session.record.termProgram {
        case "Apple_Terminal": activate(bundleID: "com.apple.Terminal")
        case "iTerm.app": activate(bundleID: "com.googlecode.iterm2")
        case "vscode": activate(bundleID: "com.microsoft.VSCode")
        case "WarpTerminal": activate(bundleID: "dev.warp.Warp-Stable")
        case "ghostty": activate(bundleID: "com.mitchellh.ghostty")
        default:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", session.record.termProgram]
            try? process.run()
        }
    }

    private func activate(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if store.sessions.isEmpty {
            menu.addItem(disabled("Geen actieve Claude-sessies"))
        }
        for session in store.sessions {
            let surface = session.record.isDesktop ? "app" : "cli"
            let detail = session.display == .idle ? "" : " — \(session.record.label)"
            let item = NSMenuItem(title: "\(session.name)\(detail)  (\(surface))", action: #selector(openFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = session.record.id
            item.image = Appearance.summaryImage([session.display], at: 0, height: 12, dot: 8, maxDots: 1)
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let show = NSMenuItem(title: "Touch Bar tonen", action: #selector(showTouchBar), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let attention = NSMenuItem(title: "Touch Bar openen bij aandacht", action: #selector(toggleOpenOnAttention), keyEquivalent: "")
        attention.target = self
        attention.state = openOnAttention ? .on : .off
        menu.addItem(attention)

        let login = NSMenuItem(title: "Starten bij inloggen", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let installed = HookInstaller.isInstalled()
        let hooks = NSMenuItem(title: installed ? "Claude Code-hooks verwijderen" : "Claude Code-hooks installeren",
                               action: installed ? #selector(uninstallHooks) : #selector(installHooks), keyEquivalent: "")
        hooks.target = self
        menu.addItem(hooks)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Stop SessionBar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func openFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let session = store.sessions.first(where: { $0.record.id == id }) else { return }
        open(session)
    }

    @objc private func showTouchBar() {
        touchBar.expand()
    }

    @objc private func toggleOpenOnAttention() {
        openOnAttention.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        if service.status == .enabled { try? service.unregister() } else { try? service.register() }
    }

    @objc private func installHooks() {
        do { try HookInstaller.install() } catch { showError(error) }
    }

    @objc private func uninstallHooks() {
        do { try HookInstaller.uninstall() } catch { showError(error) }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    @objc private func quit() {
        try? FileManager.default.createDirectory(at: SessionFiles.baseDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: SessionFiles.quitMarker.path, contents: nil)
        NSApp.terminate(nil)
    }
}
