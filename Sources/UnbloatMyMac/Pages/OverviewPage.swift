import SwiftUI
import UnbloatMyMacKit

/// The start page: what is applied, the presets, and every category.
struct OverviewPage: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: Space.lg, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                if !model.reverted.isEmpty {
                    RevertedBanner()
                        .gridProbe("reverted", area: "overview")
                }
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
                Spacer(minLength: Space.lg)
                Button("Set Up for Me…", systemImage: "person.crop.circle.badge.questionmark") { model.openSetup() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isBusy)
                    .help("Answer a few questions and get the changes and apps that fit how you use your Mac (Option-Command-S)")
            }
            HStack(spacing: Space.lg) {
                Stat(value: "\(applied)", total: String(localized: "of \(tweaks.count)"), title: String(localized: "Tweaks applied"), symbol: "checkmark.circle")
                Stat(value: "\(aiOff)", total: String(localized: "of \(ai.count)"), title: String(localized: "Apple Intelligence tweaks"), symbol: "apple.intelligence")
                Stat(value: "\(running)", total: String(localized: "running"), title: String(localized: "Third-party background items"), symbol: "gearshape.2")
            }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
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
        .help(Text("Open \(category.title)"))
    }
}

/// Shown when tweaks the app applied were put back, most often by a macOS update.
private struct RevertedBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let count = model.reverted.count
        Card {
            HStack(alignment: .top, spacing: Space.md) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title2)
                    .foregroundStyle(Palette.accentText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(model.macOSUpdated ? "macOS Was Updated" : "Some Tweaks Were Put Back").font(.headline)
                    Text("\(count) tweaks you applied are back to how macOS had them. Apply them again?")
                        .foregroundStyle(.secondary)
                    HStack(spacing: Space.sm) {
                        Button("Review and Apply Again") { model.stageReverted() }
                            .buttonStyle(.borderedProminent)
                        Button("Keep as Is") { Task { await model.forgetReverted() } }
                    }
                    .padding(.top, Space.xs)
                }
            }
        }
    }
}
