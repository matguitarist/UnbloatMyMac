import SwiftUI
import UnbloatMyMacKit

/// One category of tweaks, grouped in sections.
struct TweakPage: View {
    @Environment(AppModel.self) private var model
    let category: TweakCategory

    var body: some View {
        let tweaks = model.visibleTweaks(in: category)
        let hidden = model.tweaks(in: category).count - tweaks.count
        Form {
            Section {
                PageHeader(symbol: category.symbol, title: category.title, summary: category.summary) {
                    Button("Unbloat All") { model.stageAll(in: category, applied: true) }
                        .help("Turn on every tweak on this page. Nothing changes until you review and apply.")
                    Button("Restore Defaults") { model.stageAll(in: category, applied: false) }
                        .help("Undo every tweak on this page")
                    if category == .windows, let preset = Catalog.presets.first(where: { $0.id == "windows" }) {
                        Button("Add Full Windows Preset") { model.stage(preset) }
                            .help("Also adds the Finder, typing, and window tweaks that make the Mac feel like Windows")
                    }
                    Spacer()
                    Text("\(model.appliedCount(in: category)) of \(model.availableCount(in: category)) applied")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if category == .security {
                Section {
                    ForEach(Catalog.securityChecks) { check in SecurityCheckRow(check: check) }
                } header: {
                    Text("Status")
                } footer: {
                    Text("UnbloatMyMac only reports these. Change them in System Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(sections(of: tweaks), id: \.self) { section in
                Section(section) {
                    ForEach(tweaks.filter { $0.section == section }) { tweak in
                        TweakRow(tweak: tweak)
                    }
                }
            }
            if hidden > 0 {
                Section {
                    HStack {
                        Label(hidden == 1 ? "1 advanced tweak stops a system service and is hidden." : "\(hidden) advanced tweaks stop system services and are hidden.",
                              systemImage: "exclamationmark.shield")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Show Advanced Tweaks") { model.showAdvanced = true }
                    }
                }
            }
            if category == .intelligence {
                Section {
                    Label("Features marked Profile are turned off by a configuration profile. After you apply, approve it in System Settings > General > Device Management. Removing the profile turns them back on.",
                          systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(category.title)
    }

    private func sections(of tweaks: [Tweak]) -> [String] {
        var seen: [String] = []
        for tweak in tweaks where !seen.contains(tweak.section) { seen.append(tweak.section) }
        return seen
    }
}

/// One security setting the app reports on: protected, or what to do.
private struct SecurityCheckRow: View {
    @Environment(AppModel.self) private var model
    let check: SecurityCheck

    var body: some View {
        let passed = model.securityStatus[check.id]
        HStack(spacing: Space.md) {
            Group {
                switch passed {
                case true?: Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                case false?: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                case nil: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                }
            }
            .imageScale(.large)
            .frame(width: 24)
            .accessibilityLabel(passed == true ? "On" : passed == false ? "Needs attention" : "Unknown")
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                Text(passed == false ? check.problem : check.good)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: Space.lg)
            if passed == false, let pane = check.settingsPane {
                Button("Open Settings") { model.openSystemSettings(pane) }
                    .help("Change \(check.title) in System Settings")
            }
        }
    }
}
