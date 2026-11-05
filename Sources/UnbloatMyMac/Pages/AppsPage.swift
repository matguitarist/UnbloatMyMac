import AppKit
import SwiftUI
import UnbloatMyMacKit

/// Free apps and command line tools worth having, installed with Homebrew.
struct AppsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                PageHeader(symbol: "shippingbox", title: String(localized: "Recommended Apps"),
                           summary: String(localized: "Free, open apps and tools that fill gaps in macOS, installed with Homebrew. Nothing installs until you click.")) {
                    let missing = model.missingRecommended
                    Button(missing.isEmpty ? String(localized: "Recommended Apps Installed")
                                           : String(localized: "Install \(missing.count) Recommended…")) {
                        model.reviewInstallRecommended()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.apps.homebrew == nil || missing.isEmpty || !model.appsWorking.isEmpty)
                    .help(missing.map(\.name).joined(separator: ", "))
                    Spacer()
                    Text("\(installedCount) of \(Catalog.appsHere.count) installed")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if model.appsLoaded && model.apps.homebrew == nil {
                Section {
                    HStack(alignment: .top, spacing: Space.md) {
                        IconTile(symbol: "mug")
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text("Homebrew is not installed")
                            Text("Homebrew is the free package manager most Mac developers use. UnbloatMyMac installs apps with it. Its installer runs in Terminal and asks for your password.")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: Space.sm) {
                                Button("Copy Install Command and Open Terminal") { model.copyHomebrewCommand() }
                                Link("About Homebrew", destination: URL(string: "https://brew.sh")!)
                            }
                            .padding(.top, Space.xs)
                        }
                    }
                }
            }
            ForEach(AppGroup.allCases, id: \.self) { group in
                Section {
                    ForEach(Catalog.appsHere.filter { $0.group == group }) { app in AppRow(app: app) }
                } header: {
                    Text(group.title)
                } footer: {
                    Text(group.summary).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Recommended Apps")
        .task { if !model.appsLoaded { await model.refreshApps() } }
    }

    private var installedCount: Int {
        Catalog.appsHere.filter { model.appState($0) != .notInstalled }.count
    }
}

private struct AppRow: View {
    @Environment(AppModel.self) private var model
    let app: RecommendedApp

    var body: some View {
        let state = model.appState(app)
        let working = model.appsWorking.contains(app.id)
        HStack(alignment: .top, spacing: Space.md) {
            icon
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.sm) {
                    Text(verbatim: app.name)
                    if app.isRecommended() {
                        Tag(text: String(localized: "Recommended"), symbol: "star")
                    }
                }
                Text(app.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let other = app.replacedBy.flatMap(Catalog.app), RecommendedApp.isAppleSilicon {
                    Label("\(other.name) does this too", systemImage: "square.grid.2x2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if app.shellLine != nil, state == .installed {
                    Toggle("Turn on in new Terminal windows", isOn: Binding(
                        get: { model.apps.inShell.contains(app.id) },
                        set: { on in Task { await model.setShell(app, on: on) } }))
                        .toggleStyle(.checkbox)
                        .font(.callout)
                        .help("Adds one line to ~/.zshrc, inside a block UnbloatMyMac marks. Turn off to take it out.")
                }
            }
            Spacer(minLength: Space.lg)
            trailing(state, working)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Link("Open Website", destination: URL(string: app.homepage)!)
            if let command = app.brewCommand {
                Button("Copy Homebrew Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
            }
        }
    }

    @ViewBuilder
    private func trailing(_ state: AppInstallState, _ working: Bool) -> some View {
        if working {
            ProgressView().controlSize(.small)
                .help(state == .installed ? "Removing…" : "Installing…")
        } else {
            switch state {
            case .notInstalled:
                if let command = app.brewCommand {
                    Button("Install") { Task { await model.install([app]) } }
                        .disabled(model.apps.homebrew == nil)
                        .help(Text(verbatim: command))
                } else {
                    Link(destination: URL(string: app.homepage)!) {
                        Label("Download", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.bordered)
                    .help("Not in Homebrew. Opens \(app.homepage) to download it.")
                }
            case .installed:
                HStack(spacing: Space.sm) {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(Palette.accentText)
                    Menu {
                        if let bundle = app.bundle {
                            Button("Open") { open(bundle) }
                        }
                        Button("Uninstall", role: .destructive) { Task { await model.uninstall(app) } }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("More for \(app.name)")
                }
            case .installedElsewhere:
                Label("Installed", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help(app.installsWithHomebrew
                          ? "Installed without Homebrew. Update and remove it the way you installed it."
                          : "Installed. It updates itself; move it to the Trash to remove it.")
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let bundle = app.bundle, let path = bundlePath(bundle) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
        } else {
            IconTile(symbol: app.group == .allInOne ? app.group.symbol : app.kind == .formula ? "terminal" : app.group == .terminal ? "textformat" : app.group.symbol)
        }
    }

    private func bundlePath(_ bundle: String) -> String? {
        guard !Store.isOverridden else { return nil }
        return ["/Applications", ("~/Applications" as NSString).expandingTildeInPath]
            .map { "\($0)/\(bundle)" }
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    private func open(_ bundle: String) {
        if let path = bundlePath(bundle) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
    }
}
