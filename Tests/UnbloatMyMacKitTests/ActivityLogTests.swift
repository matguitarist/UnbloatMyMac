import Foundation
import Testing
@testable import UnbloatMyMacKit

private func temp(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)")
}

@Test("Applying a tweak logs the tweak and the exact defaults command")
func applyIsLogged() throws {
    let log = ActivityLog(url: temp("activity.log"))
    let engine = Engine(backend: MockBackend(), journalURL: temp("journal.json"), log: log)
    let report = engine.apply(["dock.recents": true])
    #expect(report.failures.isEmpty)
    let entries = log.entries()
    #expect(entries.contains { $0.source == .tweaks && $0.level == .info && $0.message == "Applied dock.recents" })
    let write = try #require(entries.first { $0.source == .settings })
    #expect(write.detail == "defaults write com.apple.dock \"show-recents\" -bool false")
    #expect(write.origin == .app)
}

@Test("A setting macOS refuses is an error line")
func refusedIsError() {
    let log = ActivityLog(url: temp("activity.log"))
    let engine = Engine(backend: MockBackend(), journalURL: temp("journal.json"), log: log)
    _ = engine.apply(["perf.reduceMotion": true])
    let errors = log.entries().filter { $0.level == .error }
    #expect(errors.contains { $0.source == .settings && $0.message.hasPrefix("macOS refused to change com.apple.universalaccess") })
    #expect(errors.contains { $0.message == "Could not apply perf.reduceMotion" })
}

@Test("The command line tool's lines say so")
func commandLineOrigin() {
    let url = temp("activity.log")
    ActivityLog(url: url, origin: .commandLine).add(.info, .tweaks, "Applied dock.recents")
    let entry = ActivityLog(url: url).entries().first
    #expect(entry?.origin == .commandLine)
    #expect(entry?.line.hasSuffix("[tweaks] Applied dock.recents (command line)") == true)
}

@Test("The log keeps the newest lines past its limit, and Clear empties it")
func trimAndClear() {
    let log = ActivityLog(url: temp("activity.log"), limit: 20)
    for i in 1...200 { log.add(.info, .app, "line \(i) " + String(repeating: "x", count: 200)) }
    let entries = log.entries()
    #expect(entries.count <= 25 && entries.count >= 20)
    #expect(entries.last?.message.hasPrefix("line 200 ") == true)
    log.clear()
    #expect(log.entries().isEmpty)
}

@Test("Filters pick levels, one source, and every search word")
func filter() {
    let lines = [
        LogEntry(level: .debug, source: .app, message: "Restarted Dock"),
        LogEntry(level: .info, source: .settings, message: "Set com.apple.dock show-recents to false", detail: "defaults write com.apple.dock"),
        LogEntry(level: .error, source: .commands, message: "Command failed: denied", detail: "pmset -a powernap 0"),
    ]
    #expect(lines.filter(LogFilter().matches).count == 2)  // debug hidden by default
    #expect(lines.filter(LogFilter(levels: Set(LogLevel.allCases), source: .commands).matches).map(\.source) == [.commands])
    #expect(lines.filter(LogFilter(search: "powernap").matches).count == 1)  // finds the command too
    #expect(lines.filter(LogFilter(search: "dock false").matches).count == 1)
    #expect(lines.filter(LogFilter(search: "dock missing").matches).isEmpty)
}
