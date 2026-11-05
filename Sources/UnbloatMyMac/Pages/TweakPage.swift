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
                        Label("\(hidden) advanced \(hidden == 1 ? "tweak stops a system service and is" : "tweaks stop system services and are") hidden.",
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
