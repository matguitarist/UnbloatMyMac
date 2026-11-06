import AppKit
import SwiftUI
import UnbloatMyMacKit

/// Everything UnbloatMyMac did to the Mac, line by line: every defaults write,
/// service, command, file, and app install, from the app and the command line tool.
/// Level chips and a source menu filter it; the inspector shows the exact
/// command or value of the selected line.
struct LogPage: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<LogEntry.ID> = []

    var body: some View {
        @Bindable var model = model
        let shown = model.logEntries.filter(model.logFilter.matches).reversed() as ReversedCollection<[LogEntry]>
        VStack(spacing: 0) {
            filterBar
            Divider()
            if model.logEntries.isEmpty {
                ContentUnavailableView("No Activity Yet", systemImage: SidebarItem.log.symbol,
                                       description: Text("Every setting, service, command, and app UnbloatMyMac changes is written here, from the app and from the command line tool."))
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: model.logFilter.search)
            } else {
                table(Array(shown))
            }
        }
        .navigationTitle("Activity Log")
        .navigationSubtitle(subtitle(shown.count))
        .searchable(text: $model.logFilter.search, placement: .toolbar, prompt: "Search log")
        .inspector(isPresented: $model.showLogInspector) {
            LogInspector(entry: model.logEntries.first { selection.contains($0.id) }, count: selection.count)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Copy", systemImage: "doc.on.doc") { model.copyLog(copied(shown)) }
                    .help("Copy the selected lines, or every shown line, as text (Command-C)")
                    .disabled(shown.isEmpty)
                Button("Export Log…", systemImage: "square.and.arrow.up") { model.exportLogWithPanel() }
                    .help("Save the activity log as a text file (Option-Command-E)")
                    .disabled(model.logEntries.isEmpty)
                Button("Clear Log…", systemImage: "trash") { model.confirmClearLog = true }
                    .help("Delete every line of the activity log")
                    .disabled(model.logEntries.isEmpty)
            }
            ToolbarItem {
                Button("Inspector", systemImage: "sidebar.trailing") { model.showLogInspector.toggle() }
                    .help("Show or hide the details of the selected line (Control-Command-I)")
            }
        }
    }

    /// Selected lines, oldest first, or everything shown when nothing is selected.
    private func copied(_ shown: ReversedCollection<[LogEntry]>) -> [LogEntry] {
        let lines = selection.isEmpty ? Array(shown) : shown.filter { selection.contains($0.id) }
        return lines.reversed()
    }

    private func subtitle(_ shown: Int) -> String {
        shown == model.logEntries.count
            ? String(localized: "\(model.logEntries.count) lines")
            : String(localized: "\(shown) of \(model.logEntries.count) lines")
    }

    private var filterBar: some View {
        // A narrow window (sidebar and inspector open) drops the level names, then turns
        // the source menu into a filter button, so the bar never pushes the page sideways.
        ViewThatFits(in: .horizontal) {
            filterRow(compactChips: false, sourceButton: false)
            filterRow(compactChips: true, sourceButton: false)
            filterRow(compactChips: true, sourceButton: true)
        }
        .controlSize(.small)
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.sm)
        .gridProbe("log.filters", area: "log")
        .gridArea("log", inset: 0)
    }

    private func filterRow(compactChips: Bool, sourceButton: Bool) -> some View {
        HStack(spacing: Space.sm) {
            levelChips(compact: compactChips)
            Spacer(minLength: Space.sm)
            if sourceButton {
                Menu {
                    sourcePicker.pickerStyle(.inline)
                } label: {
                    Label(model.logFilter.source?.title ?? String(localized: "All Sources"),
                          systemImage: model.logFilter.source == nil
                              ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Show the lines about one part of the Mac")
            } else {
                sourcePicker
                    .pickerStyle(.menu)
                    .frame(minWidth: 112, maxWidth: 200)
                    .help("Show the lines about one part of the Mac")
            }
        }
    }

    private var sourcePicker: some View {
        @Bindable var model = model
        return Picker("Source", selection: $model.logFilter.source) {
            Text("All Sources").tag(LogSource?.none)
            Divider()
            ForEach(LogSource.allCases, id: \.self) { source in
                Label(source.title, systemImage: source.symbol).tag(LogSource?.some(source))
            }
        }
        .labelsHidden()
    }

    private func levelChips(compact: Bool) -> some View {
        HStack(spacing: Space.sm) {
            ForEach(LogLevel.allCases, id: \.self) { level in
                let count = model.logEntries.count { $0.level == level }
                Toggle(isOn: Binding(
                    get: { model.logFilter.levels.contains(level) },
                    set: { on in if on { model.logFilter.levels.insert(level) } else { model.logFilter.levels.remove(level) } }
                )) {
                    // Plain icons: a colored one vanishes on the accent fill of a chip that is on.
                    if compact {
                        Label("\(count)", systemImage: level.symbol)
                            .monospacedDigit()
                            .accessibilityLabel("\(level.title) \(count)")
                    } else {
                        Label("\(level.title) \(count)", systemImage: level.symbol)
                            .monospacedDigit()
                    }
                }
                .toggleStyle(.button)
                .fixedSize()
                .help(level.help)
            }
        }
    }

    private func table(_ entries: [LogEntry]) -> some View {
        Table(entries, selection: $selection) {
            TableColumn("Time") { entry in
                Text(entry.date, format: Calendar.current.isDateInToday(entry.date)
                     ? .dateTime.hour().minute().second()
                     : .dateTime.month(.abbreviated).day().hour().minute())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help(entry.date.formatted(date: .complete, time: .standard))
            }
            .width(min: 64, ideal: 76, max: 130)
            TableColumn("Level") { entry in
                Label {
                    Text(entry.level.title)
                } icon: {
                    Image(systemName: entry.level.symbol).foregroundStyle(entry.level.color)
                }
            }
            .width(min: 80, ideal: 124, max: 150)
            TableColumn("Source") { entry in
                Text(entry.source.title).foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 100, max: 160)
            TableColumn("Message") { entry in
                HStack(spacing: Space.xs) {
                    Text(entry.message)
                        .font(.callout.monospaced())
                        .foregroundStyle(entry.level == .debug ? .secondary : .primary)
                        .lineLimit(1)
                    if entry.origin == .commandLine {
                        Image(systemName: "terminal")
                            .foregroundStyle(.secondary)
                            .help("From the command line tool")
                            .accessibilityLabel("From the command line tool")
                    }
                }
                .help(entry.message)
            }
            .width(min: 140, ideal: 480)
        }
        .contextMenu(forSelectionType: LogEntry.ID.self) { ids in
            Button("Copy") { model.copyLog(entries.filter { ids.contains($0.id) }.reversed()) }
            if let id = ids.first, ids.count == 1, let detail = entries.first(where: { $0.id == id })?.detail {
                Button("Copy Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(detail, forType: .string)
                }
            }
        } primaryAction: { _ in
            model.showLogInspector = true
        }
        .onCopyCommand { [NSItemProvider(object: model.logText(copied(entries.reversed())) as NSString)] }
    }
}

/// The selected line in full: what happened, when, and the exact command or value.
private struct LogInspector: View {
    @Environment(AppModel.self) private var model
    let entry: LogEntry?
    let count: Int

    var body: some View {
        if let entry, count == 1 {
            Form {
                Section {
                    Label {
                        Text(entry.message).textSelection(.enabled)
                    } icon: {
                        Image(systemName: entry.level.symbol).foregroundStyle(entry.level.color)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    LabeledContent("Level", value: entry.level.title)
                    LabeledContent("Source", value: entry.source.title)
                    LabeledContent("From", value: entry.origin == .commandLine ? String(localized: "Command line tool") : String(localized: "UnbloatMyMac"))
                    LabeledContent("Time") {
                        Text(entry.date, format: .dateTime.year().month().day().hour().minute().second())
                    }
                }
                if let detail = entry.detail {
                    Section(entry.source == .tweaks ? "Tweak" : "Details") {
                        Text(detail)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
        } else if count > 1 {
            ContentUnavailableView("\(count) Lines Selected", systemImage: "list.bullet.rectangle",
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

extension LogLevel {
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
    var title: String {
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
