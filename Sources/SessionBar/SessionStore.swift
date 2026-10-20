import Foundation

/// How a session looks on the Touch Bar.
enum SessionDisplay: Equatable {
    case idle        // green, steady
    case working     // green, pulsing
    case attention   // orange, blinking
    case unseen      // orange, steady: finished a turn you haven't looked at yet

    var priority: Int {
        switch self {
        case .attention: 3
        case .unseen: 2
        case .working: 1
        case .idle: 0
        }
    }
}

struct DisplaySession: Equatable {
    var record: SessionRecord
    var display: SessionDisplay
    var name: String
}

/// Polls `state.d/`, reaps sessions whose `claude` process is gone and decides what to show.
@MainActor
final class SessionStore {
    private(set) var sessions: [DisplaySession] = []
    private var records: [String: SessionRecord] = [:]
    private var fileDates: [String: Date] = [:]
    /// Per session, the `updatedAt` of the last finished turn you tapped on.
    private var seenTurns: [String: Double] = [:]
    private var transcriptCache: [String: (date: Date?, interrupted: Bool)] = [:]

    /// Returns true when what should be shown changed.
    @discardableResult
    func reload() -> Bool {
        let fm = FileManager.default
        let now = Date().timeIntervalSince1970
        let names = (try? fm.contentsOfDirectory(atPath: SessionFiles.stateDirectory.path))?
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") } ?? []

        var present = Set<String>()
        for name in names {
            let url = SessionFiles.stateDirectory.appendingPathComponent(name)
            let date = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            let id = String(name.dropLast(5))
            present.insert(id)
            if fileDates[id] != date || records[id] == nil, let record = SessionFiles.read(url) {
                records[id] = record
                fileDates[id] = date
            }
        }
        for id in records.keys where !present.contains(id) {
            records[id] = nil
            fileDates[id] = nil
        }

        // A session leaves when its process is gone (closed terminal, quit app, crash).
        for (id, record) in records where !isAlive(record, now: now) {
            try? fm.removeItem(at: SessionFiles.url(for: id))
            records[id] = nil
            fileDates[id] = nil
            seenTurns[id] = nil
        }

        let visible = records.values
            .filter(\.started)
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        let labels = displayNames(for: visible)
        let updated = visible.map { record in
            DisplaySession(record: record, display: display(for: record, now: now), name: labels[record.id] ?? record.project)
        }
        guard updated != sessions else { return false }
        sessions = updated
        return true
    }

    /// Tapping a session counts as having seen its finished turn.
    func markSeen(_ id: String) {
        guard let record = records[id] else { return }
        seenTurns[id] = record.updatedAt
        reload()
    }

    var needsAnimation: Bool {
        sessions.contains { $0.display == .working || $0.display == .attention }
    }

    var lead: SessionDisplay? {
        sessions.map(\.display).max { $0.priority < $1.priority }
    }

    private func display(for record: SessionRecord, now: Double) -> SessionDisplay {
        switch record.state {
        case .idle:
            return .idle
        case .done:
            return (seenTurns[record.id] ?? 0) >= record.updatedAt ? .idle : .unseen
        case .working, .attention:
            // Esc and a rejected permission fire no hook; recover from the transcript, and give up
            // on a state that hasn't moved for a long time.
            let cap: Double = record.state == .attention ? 7_200 : 900
            if now - record.updatedAt > cap || wasInterrupted(record) { return .idle }
            return record.state == .working ? .working : .attention
        }
    }

    private func isAlive(_ record: SessionRecord, now: Double) -> Bool {
        if record.pid > 0 { return kill(record.pid, 0) == 0 || errno == EPERM }
        return now - record.updatedAt < 3_600
    }

    private func wasInterrupted(_ record: SessionRecord) -> Bool {
        guard !record.transcript.isEmpty else { return false }
        let date = (try? FileManager.default.attributesOfItem(atPath: record.transcript))?[.modificationDate] as? Date
        if let cached = transcriptCache[record.transcript], cached.date == date { return cached.interrupted }
        let interrupted = lastLine(of: record.transcript)?.contains("interrupted by user") ?? false
        transcriptCache[record.transcript] = (date, interrupted)
        return interrupted
    }

    private func lastLine(of path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 8_192 ? size - 8_192 : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        return text.split(separator: "\n").last.map(String.init)
    }

    /// Same-named projects (two clones of one repo) get their parent folder as a prefix.
    private func displayNames(for records: [SessionRecord]) -> [String: String] {
        var folders: [String: Set<String>] = [:]
        for record in records where !record.cwd.isEmpty {
            folders[record.project, default: []].insert(record.cwd)
        }
        var names: [String: String] = [:]
        for record in records {
            var name = record.project.isEmpty ? "Claude" : record.project
            if (folders[record.project]?.count ?? 0) > 1 {
                // A worktree is told apart by its own folder name, a second clone by its parent.
                let folder = (record.cwd as NSString).lastPathComponent
                let qualifier = folder != record.project
                    ? folder
                    : ((record.cwd as NSString).deletingLastPathComponent as NSString).lastPathComponent
                if !qualifier.isEmpty { name = folder != record.project ? name + "/" + qualifier : qualifier + "/" + name }
            }
            names[record.id] = name
        }
        return names
    }
}
