import Foundation
import LogKit
import Testing
@testable import UnbloatMyMacKit

@Test("activity.log reads into LogKit entries, with the command as detail and the command line tool named")
func activityLogForTheViewer() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "activity-\(UUID().uuidString).log")
    defer { try? FileManager.default.removeItem(at: url) }
    ActivityLog(url: url).add(.info, .settings, "Set com.apple.dock show-recents to false",
                              detail: "defaults write com.apple.dock \"show-recents\" -bool false")
    ActivityLog(url: url, origin: .commandLine).add(.error, .tweaks, "Could not apply perf.reduceMotion")
    let text = try String(contentsOf: url, encoding: .utf8) + "not json\n"
    let document = ActivityLogParser(sourceTitle: { $0 == .settings ? "Preferences" : "Tweaks" }).parse(text)
    #expect(document.entries.count == 2, "a line that isn't JSON is skipped")
    let write = document.entries[0]
    #expect(write.level == .info && write.source == "Preferences" && write.detail?.hasPrefix("defaults write") == true)
    let failure = document.entries[1]
    #expect(failure.level == .error && failure.message == "Could not apply perf.reduceMotion (command line)" && failure.detail == nil)
    #expect(document.entries.map(\.id) == [0, 1])
}

@Test("Today's lines show the time; earlier ones the day too")
func activityLogTimes() {
    let today = Date(timeIntervalSince1970: 1_793_800_000)
    let short = ActivityLogParser.time(today.addingTimeInterval(-60), today: today)
    #expect(short.count == 8 && short.filter { $0 == ":" }.count == 2)
    let earlier = ActivityLogParser.time(today.addingTimeInterval(-3 * 86_400), today: today)
    #expect(earlier != short && earlier.count > 8)
}

@Test("Every level maps to the viewer's")
func activityLogLevels() {
    #expect(UnbloatMyMacKit.LogLevel.allCases.map(\.logKitLevel) == [.debug, .info, .warning, .error])
}
