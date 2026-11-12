import Foundation
import LogKit
import Synchronization

/// How much a log line matters, from routine detail to a failure.
public enum LogLevel: String, Codable, CaseIterable, Sendable, Comparable {
    case debug, info, warning, error

    public static func < (a: LogLevel, b: LogLevel) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// What part of the Mac a log line is about.
public enum LogSource: String, Codable, CaseIterable, Sendable {
    case tweaks, settings, services, profile, commands, files, background, storage, apps, app
}

/// Who made the change: the app's window or the command line tool.
public enum LogOrigin: String, Codable, Sendable {
    case app, commandLine
}

/// One line of the activity log. Messages are kept in English, like
/// Console, so a copied log reads the same in a bug report.
public struct LogEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var level: LogLevel
    public var source: LogSource
    public var origin: LogOrigin
    public var message: String
    /// The exact command, value, or output, for the inspector.
    public var detail: String?

    public init(id: UUID = UUID(), date: Date = .now, level: LogLevel, source: LogSource,
                origin: LogOrigin = .app, message: String, detail: String? = nil) {
        self.id = id
        self.date = date
        self.level = level
        self.source = source
        self.origin = origin
        self.message = message
        self.detail = detail
    }

    /// One plain text line, for Copy and Export.
    public var line: String {
        let time = date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.colon).dateSeparator(.dash))
        var text = "\(time) \(level.rawValue.uppercased().padding(toLength: 7, withPad: " ", startingAt: 0)) [\(source.rawValue)] \(message)"
        if origin == .commandLine { text += " (command line)" }
        if let detail, !detail.isEmpty {
            text += "\n" + detail.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }.joined(separator: "\n")
        }
        return text
    }
}

/// Everything UnbloatMyMac did to the Mac, one JSON object per line in
/// activity.log next to the journal. The app and the command line tool
/// both append to it. Older lines are dropped past `limit`.
public final class ActivityLog: Sendable {
    public let url: URL
    public let origin: LogOrigin
    private let limit: Int
    private let lock = Mutex(())

    public init(url: URL, origin: LogOrigin = .app, limit: Int = 5000) {
        self.url = url
        self.origin = origin
        self.limit = limit
    }

    public func add(_ level: LogLevel, _ source: LogSource, _ message: String, detail: String? = nil) {
        let entry = LogEntry(level: level, source: source, origin: origin, message: message,
                             detail: detail.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 })
        guard var data = try? Self.encoder.encode(entry) else { return }
        data.append(0x0A)
        lock.withLock { _ in
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
            trimIfNeeded()
        }
    }

    /// Every line, oldest first. Lines that do not parse are skipped.
    public func entries() -> [LogEntry] {
        lock.withLock { _ in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").compactMap { try? Self.decoder.decode(LogEntry.self, from: Data($0.utf8)) }
        }
    }

    public func clear() {
        lock.withLock { _ in try? FileManager.default.removeItem(at: url) }
    }

    /// Keeps the newest `limit` lines once the file holds a quarter more.
    private func trimIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int, size > limit * 200,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n")
        guard lines.count > limit + limit / 4 else { return }
        let kept = lines.suffix(limit).joined(separator: "\n") + "\n"
        try? kept.write(to: url, atomically: true, encoding: .utf8)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    fileprivate static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Wraps a backend and writes every change it makes to the activity log.
/// Reads are not logged: the app reads every setting on each refresh.
public final class LoggingBackend: SystemBackend {
    public let base: any SystemBackend
    public let log: ActivityLog

    public init(_ base: any SystemBackend, log: ActivityLog) {
        self.base = base
        self.log = log
    }

    public func read(_ key: PrefKey) -> PrefValue? { base.read(key) }

    public func write(_ key: PrefKey, _ value: PrefValue?) -> Bool {
        let ok = base.write(key, value)
        let target = "\(key.domain) \(key.key)"
        let host = key.currentHost ? "-currentHost " : ""
        let command = value.map { "defaults \(host)write \(key.domain) \"\(key.key)\" \(Self.describe($0))" }
            ?? "defaults \(host)delete \(key.domain) \"\(key.key)\""
        if ok {
            log.add(.info, .settings, value == nil ? "Reset \(target) to the macOS default" : "Set \(target) to \(value?.description ?? "")", detail: command)
        } else {
            log.add(.error, .settings, "macOS refused to change \(target)", detail: command)
        }
        return ok
    }

    public func knownAgents() -> Set<String> { base.knownAgents() }
    public func disabledAgents() -> Set<String> { base.disabledAgents() }

    public func setAgent(_ label: String, disabled: Bool) -> Bool {
        let ok = base.setAgent(label, disabled: disabled)
        let verb = disabled ? "disable" : "enable"
        log.add(ok ? .info : .error, .services,
                ok ? (disabled ? "Stopped \(label)" : "Started \(label) again") : "macOS would not \(disabled ? "stop" : "start") \(label)",
                detail: "launchctl \(verb) gui/<uid>/\(label)")
        return ok
    }

    public func managedRestrictions() -> Set<String> { base.managedRestrictions() }

    public func installProfile(_ restrictions: Set<String>) throws {
        let detail = restrictions.sorted().joined(separator: "\n")
        do {
            try base.installProfile(restrictions)
            log.add(.info, .profile, restrictions.isEmpty ? "Removed the Apple Intelligence profile"
                    : "Handed the Apple Intelligence profile to System Settings for approval", detail: detail)
        } catch {
            log.add(.error, .profile, "Could not install the Apple Intelligence profile: \(error.localizedDescription)", detail: detail)
            throw error
        }
    }

    public func check(_ script: String) -> Bool { base.check(script) }

    public func run(_ scripts: [String], admin: Bool) throws {
        let detail = scripts.joined(separator: "\n")
        let what = scripts.count == 1 ? "a command" : "\(scripts.count) commands"
        do {
            try base.run(scripts, admin: admin)
            log.add(.info, .commands, admin ? "Ran \(what) as administrator" : "Ran \(what)", detail: detail)
        } catch {
            log.add(.error, .commands, "\(admin ? "Administrator command" : "Command") failed: \(error.localizedDescription)", detail: detail)
            throw error
        }
    }

    public func readFile(_ path: String) -> String? { base.readFile(path) }

    public func writeFile(_ path: String, _ contents: String?) -> Bool {
        let ok = base.writeFile(path, contents)
        if ok {
            log.add(.info, .files, contents == nil ? "Removed \(path)" : "Wrote \(path)", detail: contents)
        } else {
            log.add(.error, .files, "Could not write \(path)", detail: contents)
        }
        return ok
    }

    public func restart(_ processes: Set<Restart>) {
        guard !processes.isEmpty else { return }
        base.restart(processes)
        log.add(.debug, .app, "Restarted \(processes.map(\.rawValue).sorted().joined(separator: ", "))")
    }

    public func launchItems() -> [LaunchItem] { base.launchItems() }

    public func setLaunchItem(_ item: LaunchItem, disabled: Bool) throws {
        do {
            try base.setLaunchItem(item, disabled: disabled)
            log.add(.info, .background, disabled ? "Stopped background item \(item.label)" : "Allowed background item \(item.label)", detail: item.path)
        } catch {
            log.add(.error, .background, "Could not change \(item.label): \(error.localizedDescription)", detail: item.path)
            throw error
        }
    }

    public func measure(_ target: CleanupTarget) -> CleanupSize { base.measure(target) }

    public func clean(_ target: CleanupTarget) throws {
        do {
            try base.clean(target)
            log.add(.info, .storage, "Cleaned \(target.id)")
        } catch {
            log.add(.error, .storage, "Could not clean \(target.id): \(error.localizedDescription)")
            throw error
        }
    }

    public func openApps(holding target: CleanupTarget) -> [OpenApp] { base.openApps(holding: target) }

    public func quit(_ apps: [OpenApp]) -> [OpenApp] {
        let open = base.quit(apps)
        let quit = apps.filter { app in !open.contains { $0.pid == app.pid } }
        if !quit.isEmpty { log.add(.info, .storage, "Quit \(quit.map(\.name).joined(separator: ", ")) to clean their caches") }
        if !open.isEmpty { log.add(.warning, .storage, "Still open after asking to quit: \(open.map(\.name).joined(separator: ", "))") }
        return open
    }

    public func leftovers() -> [Leftover] {
        let found = base.leftovers()
        log.add(.debug, .storage, "Found \(found.count) leftovers from deleted apps", detail: found.map(\.path).joined(separator: "\n"))
        return found
    }

    public func trash(_ leftovers: [Leftover]) throws {
        do {
            try base.trash(leftovers)
            log.add(.info, .storage, "Moved \(leftovers.count) leftovers to the Trash", detail: leftovers.map(\.path).joined(separator: "\n"))
        } catch {
            log.add(.error, .storage, "Could not move leftovers to the Trash: \(error.localizedDescription)",
                    detail: leftovers.map(\.path).joined(separator: "\n"))
            throw error
        }
    }

    public func osBuild() -> String { base.osBuild() }

    public func loginItems() throws -> [LoginItem] {
        do {
            let items = try base.loginItems()
            log.add(.debug, .background, "Read \(items.count) login items")
            return items
        } catch {
            log.add(.warning, .background, "Could not read login items: \(error.localizedDescription)")
            throw error
        }
    }

    static func describe(_ value: PrefValue) -> String {
        switch value {
        case .bool(let b): "-bool \(b)"
        case .int(let i): "-int \(i)"
        case .double(let d): "-float \(d)"
        case .string(let s): "-string \"\(s)\""
        }
    }
}

/// What the Activity Log page shows: some levels, one source or all, and a search.
public struct LogFilter: Equatable, Sendable {
    public var levels: Set<LogLevel>
    public var source: LogSource?
    public var search: String

    /// Debug lines are hidden until you ask for them.
    public init(levels: Set<LogLevel> = [.info, .warning, .error], source: LogSource? = nil, search: String = "") {
        self.levels = levels
        self.source = source
        self.search = search
    }

    public func matches(_ entry: LogEntry) -> Bool {
        guard levels.contains(entry.level) else { return false }
        if let source, entry.source != source { return false }
        let words = search.split(separator: " ")
        guard !words.isEmpty else { return true }
        let text = entry.message + " " + (entry.detail ?? "") + " " + entry.source.rawValue
        return words.allSatisfy { text.localizedStandardContains($0) }
    }
}

// MARK: LogKit

/// activity.log for LogKit's viewer: one entry per JSON line, with its command or value as the entry's detail.
/// A line from the command line tool ends in "(command line)", as in Copy and Export.
public struct ActivityLogParser: LogKit.LogParser {
    private let sourceTitle: @Sendable (LogSource) -> String
    private let now: @Sendable () -> Date

    /// - Parameter sourceTitle: the name the viewer shows for a source ("Preferences" for `.settings`).
    public init(sourceTitle: @escaping @Sendable (LogSource) -> String = { $0.rawValue },
                now: @escaping @Sendable () -> Date = { .now }) {
        self.sourceTitle = sourceTitle
        self.now = now
    }

    public func parse(_ text: String) -> LogKit.LogDocument {
        let today = now()
        var entries: [LogKit.LogEntry] = []
        LogKit.LogLines.forEach(in: text) { line in
            guard !line.isEmpty, let entry = try? ActivityLog.decoder.decode(LogEntry.self, from: Data(line.utf8)) else { return }
            entries.append(entry.logKitEntry(id: entries.count, title: sourceTitle(entry.source), today: today))
        }
        return LogKit.LogDocument(entries: entries)
    }

    /// "14:05:09" today, "Nov 5, 14:05" on an earlier day (as the Activity Log showed them).
    static func time(_ date: Date, today: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: today)
            ? date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
            : date.formatted(.dateTime.month(.abbreviated).day().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

extension LogEntry {
    /// The same line as LogKit shows it.
    public func logKitEntry(id: Int, title: String, today: Date = .now) -> LogKit.LogEntry {
        LogKit.LogEntry(id: id, time: ActivityLogParser.time(date, today: today), level: level.logKitLevel, source: title,
                        message: origin == .commandLine ? message + " (command line)" : message, detail: detail)
    }
}

extension LogLevel {
    public var logKitLevel: LogKit.LogLevel {
        switch self {
        case .debug: .debug
        case .info: .info
        case .warning: .warning
        case .error: .error
        }
    }
}
