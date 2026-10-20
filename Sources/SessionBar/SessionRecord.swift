import Foundation

/// What a hook last reported for one Claude Code session.
enum SessionState: String, Codable {
    case idle        // opened, nothing running
    case working     // thinking or running a tool
    case attention   // waiting on you: permission prompt or a question
    case done        // finished a turn
}

/// One file per session in `~/.claude/sessionbar/state.d/<session_id>.json`.
/// Written by the hook (`SessionBar --sessionbar-hook`), read by the app.
struct SessionRecord: Codable, Equatable {
    var id: String
    var state: SessionState = .idle
    var label: String = ""
    var project: String = ""
    var cwd: String = ""
    var entrypoint: String = ""     // CLAUDE_CODE_ENTRYPOINT: "cli", "claude-desktop", …
    var termProgram: String = ""    // TERM_PROGRAM of a CLI session, used to focus its terminal
    var transcript: String = ""
    var pid: Int32 = 0              // the session's `claude` process; drives liveness
    var started: Bool = false       // false until real activity (hides desktop warm-up sessions)
    var createdAt: Double = 0       // keeps Touch Bar order stable
    var updatedAt: Double = 0

    var isDesktop: Bool { entrypoint == "claude-desktop" }
}

enum SessionFiles {
    static let baseDirectory = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/sessionbar", isDirectory: true)
    static let stateDirectory = baseDirectory.appendingPathComponent("state.d", isDirectory: true)
    /// Written by the Quit menu item so hooks don't relaunch the app; removed on next launch.
    static let quitMarker = baseDirectory.appendingPathComponent("quit-intent")

    static func safeID(_ raw: String) -> String {
        let allowed = raw.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" || $0 == "."
        }
        let id = String(String.UnicodeScalarView(allowed)).prefix(64)
        return id.isEmpty ? "unknown" : String(id)
    }

    static func url(for id: String) -> URL {
        stateDirectory.appendingPathComponent(id + ".json")
    }

    static func read(_ url: URL) -> SessionRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SessionRecord.self, from: data)
    }

    static func write(_ record: SessionRecord) {
        let fm = FileManager.default
        try? fm.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(record) else { return }
        let target = url(for: record.id)
        let tmp = stateDirectory.appendingPathComponent(".\(record.id).\(getpid()).tmp")
        // rename(2) is atomic, so the app never reads a half-written file.
        guard (try? data.write(to: tmp)) != nil, rename(tmp.path, target.path) == 0 else {
            try? fm.removeItem(at: tmp)
            return
        }
    }

    /// Readable name for a working directory. Worktrees under `<repo>/.claude/worktrees/<name>`
    /// are shown as the repo they belong to.
    static func projectName(for cwd: String) -> String {
        let parts = cwd.split(separator: "/").map(String.init)
        if let index = parts.firstIndex(of: ".claude"), index > 0,
           index + 1 < parts.count, parts[index + 1] == "worktrees" {
            return parts[index - 1]
        }
        return parts.last ?? ""
    }
}
