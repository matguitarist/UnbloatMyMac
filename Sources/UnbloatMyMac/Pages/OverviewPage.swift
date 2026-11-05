import SwiftUI
import UnbloatMyMacKit

/// The start page: what is applied, the presets, and every category.
struct OverviewPage: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: Space.lg, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                hero
                    .gridProbe("hero", area: "overview")
                VStack(alignment: .leading, spacing: Space.md) {
                    sectionTitle("Presets", "Add a set of tweaks to your changes. You review everything before it applies.")
                    LazyVGrid(columns: columns, spacing: Space.lg) {
                        ForEach(Catalog.presets) { preset in PresetCard(preset: preset) }
                    }
                }
                .gridProbe("presets", area: "overview")
                VStack(alignment: .leading, spacing: Space.md) {
                    sectionTitle("Categories", "Pick tweaks one by one.")
                    LazyVGrid(columns: columns, spacing: Space.lg) {
                        ForEach(TweakCategory.allCases, id: \.self) { category in CategoryCard(category: category) }
                    }
                }
                .gridProbe("categories", area: "overview")
                if !model.applied.isEmpty || !model.launchItemsDisabledByApp.isEmpty {
                    HStack {
                        Label("Every change is saved with the value from before, so you can undo it.", systemImage: "arrow.uturn.backward.circle")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Undo Everything…") { model.confirmUndoAll = true }
                    }
                    .gridProbe("undo", area: "overview")
                }
            }
            .padding(Space.margin)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity)
            .gridArea("overview")
        }
        .navigationTitle("Overview")
    }

    private var hero: some View {
        let tweaks = model.engine.tweaks.filter { model.status($0).isAvailable }
        let applied = tweaks.filter { model.status($0).isOn }.count
        let ai = model.tweaks(in: .intelligence).filter { model.status($0).isAvailable }
        let aiOff = ai.filter { model.status($0).isOn }.count
        let running = model.launchItems.filter { !$0.isDisabled }.count
        return VStack(alignment: .leading, spacing: Space.lg) {
            HStack(alignment: .center, spacing: Space.lg) {
                IconTile(symbol: "wand.and.sparkles", size: 56)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Unbloat Your Mac").font(.largeTitle.weight(.bold))
                    Text("Turn off what you don’t use. Every change is optional, shown before it applies, and can be undone.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Space.lg) {
                Stat(value: "\(applied)", total: "of \(tweaks.count)", title: "Tweaks applied", symbol: "checkmark.circle")
                Stat(value: "\(aiOff)", total: "of \(ai.count)", title: "Apple Intelligence tweaks", symbol: "apple.intelligence")
                Stat(value: "\(running)", total: "running", title: "Third-party background items", symbol: "gearshape.2")
            }
        }
    }

    private func sectionTitle(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.semibold))
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct Stat: View {
    let value: String
    let total: String
    let title: String
    let symbol: String

    var body: some View {
        Card {
            Label(title, systemImage: symbol)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(value).font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                Text(total).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PresetCard: View {
    @Environment(AppModel.self) private var model
    let preset: Preset

    var body: some View {
        let progress = model.presetProgress(preset)
        let complete = progress.applied == progress.total
        Card {
            HStack(spacing: Space.md) {
                IconTile(symbol: preset.symbol)
                Text(preset.title).font(.headline)
            }
            Text(preset.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.sm)
            HStack {
                Text(complete ? "All \(progress.total) applied" : "\(progress.applied) of \(progress.total) applied")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button(complete ? "Applied" : "Add to Changes") { model.stage(preset) }
                    .disabled(complete || model.isBusy)
                    .help("Stage this preset’s tweaks. Review them before anything changes.")
            }
        }
    }
}

private struct CategoryCard: View {
    @Environment(AppModel.self) private var model
    let category: TweakCategory

    var body: some View {
        let total = model.availableCount(in: category)
        let applied = model.appliedCount(in: category)
        Button {
            model.sidebar = .category(category)
        } label: {
            Card {
                HStack(spacing: Space.md) {
                    IconTile(symbol: category.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title).font(.headline).foregroundStyle(.primary)
                        Text("\(applied) of \(total) applied").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                ProgressView(value: Double(applied), total: Double(max(total, 1)))
                    .tint(Palette.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(category.title)")
    }
}
