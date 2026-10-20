import AppKit

/// Runs when Claude Code calls `SessionBar --sessionbar-hook` with the hook JSON on stdin.
/// Maps the event to the session's state file and exits. Never prints, never fails the hook.
enum HookHandler {
    private static let toolLabels: [String: String] = [
        "Bash": "Running command", "Edit": "Editing", "MultiEdit": "Editing", "Write": "Writing",
        "NotebookEdit": "Editing", "Read": "Reading", "Grep": "Searching", "Glob": "Searching",
        "WebFetch": "Browsing", "WebSearch": "Searching web", "Task": "Delegating", "Agent": "Delegating",
        "TodoWrite": "Planning"
    ]
    /// Tools that stop and wait for the user.
    private static let questionTools: [String: String] = [
        "AskUserQuestion": "Question", "ExitPlanMode": "Plan ready"
    ]

    static func run() -> Int32 {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]
        let event = payload["hook_event_name"] as? String ?? ""
        let id = SessionFiles.safeID(payload["session_id"] as? String ?? "")
        let fileURL = SessionFiles.url(for: id)

        if event == "SessionEnd" {
            try? FileManager.default.removeItem(at: fileURL)
            return 0
        }

        let now = Date().timeIntervalSince1970
        let env = ProcessInfo.processInfo.environment
        var record = SessionFiles.read(fileURL) ?? SessionRecord(id: id, createdAt: now)
        let tool = payload["tool_name"] as? String ?? ""

        switch event {
        case "SessionStart":
            record.state = .idle
            record.label = ""
        case "UserPromptSubmit":
            record.state = .working
            record.label = "Thinking"
            record.started = true
        case "PreToolUse":
            if let question = questionTools[tool] {
                record.state = .attention
                record.label = question
            } else {
                record.state = .working
                record.label = toolLabels[tool] ?? "Using tool"
            }
            record.started = true
        case "PostToolUse":
            record.state = .working
            record.label = "Thinking"
            record.started = true
        case "PermissionRequest":
            record.state = .attention
            record.label = "Permission"
            record.started = true
        case "Notification":
            // Only permission prompts matter; "Claude is waiting for your input" is just a done turn.
            let message = (payload["message"] as? String ?? "").lowercased()
            let isPermission = payload["notification_type"] as? String == "permission_prompt"
                || message.contains("permission") || message.contains("approve")
            guard isPermission else { return 0 }
            record.state = .attention
            record.label = "Permission"
            record.started = true
        case "Stop":
            record.state = .done
            record.label = "Done"
        default:
            return 0
        }

        if let cwd = payload["cwd"] as? String, !cwd.isEmpty {
            record.cwd = cwd
            record.project = SessionFiles.projectName(for: cwd)
        }
        if let transcript = payload["transcript_path"] as? String, !transcript.isEmpty {
            record.transcript = transcript
        }
        if let entrypoint = env["CLAUDE_CODE_ENTRYPOINT"], !entrypoint.isEmpty {
            record.entrypoint = entrypoint
        }
        if let term = env["TERM_PROGRAM"], !term.isEmpty {
            record.termProgram = term
        }
        // Claude Code spawns the hook through `sh -c`, which execs a single command, so our
        // parent is the session's own `claude` process.
        record.pid = getppid()
        record.updatedAt = now
        SessionFiles.write(record)

        if event == "SessionStart" || event == "UserPromptSubmit" {
            launchAppIfNeeded()
        }
        return 0
    }

    private static func launchAppIfNeeded() {
        guard let bundleID = Bundle.main.bundleIdentifier,
              NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty,
              !FileManager.default.fileExists(atPath: SessionFiles.quitMarker.path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-b", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
