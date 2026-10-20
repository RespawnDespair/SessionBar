import Foundation

/// Merges SessionBar's hooks into `~/.claude/settings.json` without touching other hooks.
enum HookInstaller {
    static let flag = "--sessionbar-hook"
    private static let settingsURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/settings.json")
    private static let backupURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/settings.json.bak-sessionbar")

    /// Events that take a tool matcher get `"*"`.
    private static let events: [(name: String, matched: Bool)] = [
        ("SessionStart", false), ("SessionEnd", false), ("UserPromptSubmit", false),
        ("PreToolUse", true), ("PostToolUse", true), ("PermissionRequest", true),
        ("Notification", false), ("Stop", false)
    ]

    static var command: String {
        let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
        return "'\(executable.replacingOccurrences(of: "'", with: "'\\''"))' \(flag)"
    }

    static func isInstalled() -> Bool {
        guard let hooks = loadSettings()["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            (hooks[event.name] as? [[String: Any]] ?? []).contains { entry in
                (entry["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String) == command }
            }
        }
    }

    static func install() throws {
        var settings = loadSettings()
        backUpOnce()
        var hooks = stripOurs(settings["hooks"] as? [String: Any] ?? [:])
        for event in events {
            var entry: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": 5]]]
            if event.matched { entry["matcher"] = "*" }
            var list = hooks[event.name] as? [[String: Any]] ?? []
            list.append(entry)
            hooks[event.name] = list
        }
        settings["hooks"] = hooks
        try save(settings)
    }

    static func uninstall() throws {
        var settings = loadSettings()
        let hooks = stripOurs(settings["hooks"] as? [String: Any] ?? [:])
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try save(settings)
    }

    private static func stripOurs(_ hooks: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { result[event] = value; continue }
            let kept = entries.compactMap { entry -> [String: Any]? in
                var entry = entry
                let commands = (entry["hooks"] as? [[String: Any]] ?? []).filter {
                    !(($0["command"] as? String ?? "").contains(flag))
                }
                guard !commands.isEmpty else { return nil }
                entry["hooks"] = commands
                return entry
            }
            if !kept.isEmpty { result[event] = kept }
        }
        return result
    }

    private static func loadSettings() -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func backUpOnce() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsURL.path), !fm.fileExists(atPath: backupURL.path) else { return }
        try? fm.copyItem(at: settingsURL, to: backupURL)
    }

    private static func save(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        try data.write(to: settingsURL, options: .atomic)
    }
}
