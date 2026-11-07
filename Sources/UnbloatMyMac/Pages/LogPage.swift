import AppKit
import LogKitUI
import SwiftUI
import UnbloatMyMacKit

/// The Activity Log's viewer: activity.log, read again as the app or the command line tool writes it.
/// Kept for the whole session, so filters and Clear survive leaving the page.
enum ActivityLogViewer {
    static let model: LogViewerModel = {
        // Parsing runs off the main actor: LogSource.title is nonisolated.
        let parser = ActivityLogParser(sourceTitle: { $0.title })
        let model = LogViewerModel(file: LogFileSource(
            files: [.init(String(localized: "Activity Log"), url: Store.logURL)], parser: parser))
        // Debug lines are hidden until you ask for them.
        model.filter = LogKitUI.LogFilter(levels: [.info, .warning, .error, .critical])
        model.defaultFilter = model.filter
        return model
    }()
}

/// Everything UnbloatMyMac did to the Mac, line by line: every defaults write,
/// service, command, file, and app install, from the app and the command line tool.
/// LogKit's viewer filters it by level and source; the inspector shows the exact
/// command or value of the selected line.
struct LogPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let viewer = ActivityLogViewer.model
        LogViewer(model: viewer, options: LogViewerOptions(
            emptyTitle: String(localized: "No Activity Yet"),
            emptyMessage: String(localized: "Every setting, service, command, and app UnbloatMyMac changes is written here, from the app and from the command line tool."),
            inspectorTitle: String(localized: "Inspector"),
            entryInspector: { selected, _ in AnyView(LogInspector(selected: selected)) },
            shareActions: [.init(String(localized: "Export Activity Log…")) { _ in model.exportLogWithPanel() }],
            sourceColor: { _ in .secondary }
        ))
        .navigationTitle("Activity Log")
        .toolbar {
            ToolbarItem {
                Button("Clear Log…", systemImage: "trash") { model.confirmClearLog = true }
                    .help("Delete every line of the activity log")
                    .disabled(model.logEntries.isEmpty)
            }
        }
        // The View menu's Show Log Inspector (⌃⌘I) and the viewer's own button stay in step.
        .onAppear { viewer.showInspector = model.showLogInspector }
        .onChange(of: model.showLogInspector) { viewer.showInspector = model.showLogInspector }
        .onChange(of: viewer.showInspector) { model.showLogInspector = viewer.showInspector }
        // A change made from the app shows at once, without waiting for the next look at the file.
        .onChange(of: model.logEntries.count) { Task { await viewer.reload(force: true) } }
    }
}

/// The selected line in full: what happened, when, and the exact command or value.
private struct LogInspector: View {
    @Environment(AppModel.self) private var model
    let selected: [LogKitUI.LogEntry]

    /// The activity.log line behind a viewer entry: both number the lines that read, in order.
    private func original(_ entry: LogKitUI.LogEntry) -> UnbloatMyMacKit.LogEntry? {
        guard model.logEntries.indices.contains(entry.id) else { return nil }
        let line = model.logEntries[entry.id]
        return line.logKitEntry(id: entry.id, title: line.source.title).message == entry.message ? line : nil
    }

    var body: some View {
        if selected.count == 1, let entry = selected.first {
            let line = original(entry)
            Form {
                Section {
                    Label {
                        Text(line?.message ?? entry.message).textSelection(.enabled)
                    } icon: {
                        Image(systemName: (line?.level ?? .info).symbol).foregroundStyle(entry.level.color)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    LabeledContent("Level", value: line?.level.title ?? entry.level.title)
                    LabeledContent("Source", value: entry.source)
                    if let line {
                        LabeledContent("From", value: line.origin == .commandLine ? String(localized: "Command line tool") : String(localized: "UnbloatMyMac"))
                        LabeledContent("Time") {
                            Text(line.date, format: .dateTime.year().month().day().hour().minute().second())
                        }
                    } else if let time = entry.time {
                        LabeledContent("Time", value: time)
                    }
                }
                if let detail = entry.detail {
                    Section(line?.source == .tweaks ? "Tweak" : "Details") {
                        Text(detail)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
        } else if selected.count > 1 {
            ContentUnavailableView("\(selected.count) Lines Selected", systemImage: "list.bullet.rectangle",
                                   description: Text("Copy them with Command-C."))
        } else {
            Form {
                Section("This Log") {
                    LabeledContent("Lines", value: model.logEntries.count.formatted())
                    if let first = model.logEntries.first {
                        LabeledContent("Since") { Text(first.date, format: .dateTime.year().month().day()) }
                    }
                    LabeledContent("Problems", value: model.logEntries.count { $0.level >= .warning }.formatted())
                    Button("Show in Finder") { model.showLogInFinder() }
                }
                Section {
                    Text("Select a line to see the exact command, value, or file it wrote.")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("The log keeps the latest 5,000 lines. Lines are in English, so you can paste them in a bug report.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }
}

extension UnbloatMyMacKit.LogLevel {
    var title: String {
        switch self {
        case .debug: String(localized: "Debug", comment: "Log level")
        case .info: String(localized: "Info", comment: "Log level")
        case .warning: String(localized: "Warning", comment: "Log level")
        case .error: String(localized: "Error", comment: "Log level")
        }
    }

    var symbol: String {
        switch self {
        case .debug: "ant"
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .debug: .secondary
        case .info: Palette.accent
        case .warning: .orange
        case .error: .red
        }
    }

    var help: String {
        switch self {
        case .debug: String(localized: "Show or hide routine steps, like restarting the Dock")
        case .info: String(localized: "Show or hide changes that worked")
        case .warning: String(localized: "Show or hide changes that need something from you")
        case .error: String(localized: "Show or hide changes that failed")
        }
    }
}

extension LogSource {
    nonisolated var title: String {
        switch self {
        case .tweaks: String(localized: "Tweaks", comment: "Log source")
        case .settings: String(localized: "Preferences", comment: "Log source: defaults values")
        case .services: String(localized: "Services", comment: "Log source: launch agents")
        case .profile: String(localized: "Profile", comment: "Log source: configuration profile")
        case .commands: String(localized: "Commands", comment: "Log source")
        case .files: String(localized: "Files", comment: "Log source")
        case .background: String(localized: "Background Items", comment: "Log source")
        case .storage: String(localized: "Storage", comment: "Log source")
        case .apps: String(localized: "Apps", comment: "Log source")
        case .app: String(localized: "UnbloatMyMac", comment: "Log source: the app itself")
        }
    }

    var symbol: String {
        switch self {
        case .tweaks: "slider.horizontal.3"
        case .settings: "switch.2"
        case .services: "stop.circle"
        case .profile: "checkmark.shield"
        case .commands: "terminal"
        case .files: "doc"
        case .background: "gearshape.2"
        case .storage: "internaldrive"
        case .apps: "shippingbox"
        case .app: "app"
        }
    }
}
