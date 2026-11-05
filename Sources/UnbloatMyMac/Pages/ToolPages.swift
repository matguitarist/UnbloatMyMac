import AppKit
import SwiftUI
import UnbloatMyMacKit

/// Third-party launch agents and daemons: updaters, helpers, and menu bar launchers.
struct BackgroundPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                PageHeader(symbol: "gearshape.2", title: String(localized: "Background Items"),
                           summary: String(localized: "Updaters and helpers other apps start at login and keep running. Switch one off to stop it; switch it on to bring it back.")) {
                    Button("Open Login Items Settings") { model.openSystemSettings("com.apple.LoginItems-Settings.extension") }
                    Spacer()
                    Text("\(model.launchItems.filter { !$0.isDisabled }.count) of \(model.launchItems.count) allowed")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if model.launchItems.isEmpty && model.hasLoaded {
                Section {
                    ContentUnavailableView("No Background Items", systemImage: "checkmark.circle",
                                           description: Text("No other app installed a launch agent or daemon."))
                }
            }
            Section {
                if let items = model.loginItems {
                    if items.isEmpty {
                        Text("No login items.").foregroundStyle(.secondary)
                    }
                    ForEach(items) { item in LoginItemRow(item: item) }
                } else {
                    HStack {
                        Text("Login items and app background items need your password to read.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Show Login Items…") { Task { await model.loadLoginItems() } }
                            .disabled(model.isBusy)
                    }
                }
            } header: {
                Text("Login Items and App Background Items")
            } footer: {
                Text("Turn these on or off in System Settings > General > Login Items & Extensions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(LaunchItem.Scope.allCases, id: \.self) { scope in
                let items = model.launchItems.filter { $0.scope == scope }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in LaunchItemRow(item: item) }
                    } header: {
                        Text(scope.title)
                    } footer: {
                        Text(scope.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Background Items")
    }
}

private struct LaunchItemRow: View {
    @Environment(AppModel.self) private var model
    let item: LaunchItem

    var body: some View {
        HStack(spacing: Space.md) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.sm) {
                    Text(item.label)
                    if item.isRunning {
                        Label("Running", systemImage: "circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                            .imageScale(.small)
                    }
                }
                Text(item.program.isEmpty ? item.path : item.program)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.path)
            }
            Spacer(minLength: Space.lg)
            Toggle("Allow \(item.label)", isOn: Binding(get: { !item.isDisabled },
                                                        set: { allowed in Task { await model.setLaunchItem(item, allowed: allowed) } }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(model.isBusy)
                .help(item.isDisabled ? "Allow this item to run again" : "Stop this item and keep it from starting at login")
        }
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile((item.path as NSString).expandingTildeInPath, inFileViewerRootedAtPath: "")
            }
        }
    }

    /// The icon of the app the program sits in, or a generic gear.
    private var icon: NSImage {
        let program = (item.program as NSString).expandingTildeInPath
        if let range = program.range(of: ".app") {
            let app = String(program[..<range.upperBound])
            if FileManager.default.fileExists(atPath: app) { return NSWorkspace.shared.icon(forFile: app) }
        }
        return NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) ?? NSImage()
    }
}

/// Space that can be freed. Files go to the Trash, so nothing is lost until it is emptied.
struct StoragePage: View {
    @Environment(AppModel.self) private var model
    @State private var confirm: CleanupTarget?

    var body: some View {
        Form {
            Section {
                PageHeader(symbol: "internaldrive", title: String(localized: "Storage"),
                           summary: String(localized: "Caches, leftovers, and developer files that can safely go. Files move to the Trash; empty it to free the space.")) {
                    Button(model.isScanning ? "Scanning…" : "Scan Again") { Task { await model.scanStorage() } }
                        .disabled(model.isScanning)
                    Spacer()
                    if model.reclaimableBytes > 0 {
                        Text("\(model.reclaimableBytes.bytesText) can be freed")
                            .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            Section {
                ForEach(Catalog.cleanup) { target in row(target) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Storage")
        .task { if model.sizes.isEmpty { await model.scanStorage() } }
        .confirmationDialog("Clean \(confirm?.title ?? "")?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            presenting: confirm) { target in
            Button("Clean", role: .destructive) { Task { await model.clean(target) } }
        } message: { target in
            if case .command = target.kind {
                Text(target.detail + " " + String(localized: "This cannot be undone."))
            } else {
                Text("These files move to the Trash. You can put them back until you empty it.")
            }
        }
    }

    private func row(_ target: CleanupTarget) -> some View {
        let size = model.sizes[target.id]
        return HStack(spacing: Space.md) {
            IconTile(symbol: target.symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.title)
                Text(target.detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.lg)
            Group {
                if let size {
                    if size.isEmpty {
                        Text("Nothing to clean")
                    } else if let bytes = size.bytes {
                        Text(bytes.bytesText)
                    } else {
                        size.items == 1 ? Text("1 item") : Text("\(size.items) items")
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            if let pane = target.settingsPane {
                Button("Open Settings") { model.openSystemSettings(pane) }
                    .help("macOS removes these when you turn off Apple Intelligence")
            } else {
                Button("Clean…") { confirm = target }
                    .disabled(size?.isEmpty ?? true || model.isBusy)
                    .help("Clean \(target.title)")
            }
        }
    }
}

/// Everything the app changed, newest first.
struct HistoryPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.history.isEmpty {
                ContentUnavailableView("No Changes Yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Changes you apply show here, and you can undo all of them at once."))
            } else {
                List(model.history) { entry in
                    HStack(spacing: Space.md) {
                        Image(systemName: entry.error != nil ? "exclamationmark.triangle.fill"
                                  : entry.turnedOn ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(entry.error != nil ? AnyShapeStyle(.orange) : entry.turnedOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .imageScale(.large)
                            .accessibilityLabel(entry.error != nil ? "Failed" : entry.turnedOn ? "Applied" : "Undone")
                        VStack(alignment: .leading, spacing: 2) {
                            entry.turnedOn ? Text("Applied \(entry.title)") : Text("Undid \(entry.title)")
                            if let error = entry.error {
                                Text(error).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(entry.date, format: .dateTime.day().month().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem {
                Button("Undo Everything…", systemImage: "arrow.uturn.backward.circle") { model.confirmUndoAll = true }
                    .disabled(model.applied.isEmpty && model.launchItemsDisabledByApp.isEmpty)
                    .help("Put back every setting UnbloatMyMac changed (Option-Command-Z)")
            }
        }
    }
}

private struct LoginItemRow: View {
    @Environment(AppModel.self) private var model
    let item: LoginItem

    var body: some View {
        HStack(spacing: Space.md) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(verbatim: [item.developer, item.kind.capitalized].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.lg)
            Text(item.isEnabled ? "On" : "Off")
                .font(.callout)
                .foregroundStyle(item.isEnabled ? AnyShapeStyle(Palette.accentText) : AnyShapeStyle(.secondary))
            Button("Open Settings") { model.openSystemSettings("com.apple.LoginItems-Settings.extension") }
                .help("Change this item in System Settings")
        }
    }

    private var icon: NSImage {
        if let url = URL(string: item.url), url.isFileURL, url.path.hasSuffix(".app/") || url.path.hasSuffix(".app"),
           FileManager.default.fileExists(atPath: url.path) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) ?? NSImage()
    }
}
