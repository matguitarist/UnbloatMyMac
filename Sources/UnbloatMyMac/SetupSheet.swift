import SwiftUI
import UnbloatMyMacKit

/// Set Up for Me: one question at a time, then a summary of the changes and apps
/// the answers lead to. Finishing stages the changes and opens Review.
struct SetupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var answers: SetupAnswers
    @State private var step = 0
    /// Apps and the Command Line Tools left unchecked in the summary.
    @State private var skipped: Set<String> = []

    private let questions = SetupQuestion.allCases
    static let toolsID = "commandLineTools"

    init(answers: SetupAnswers, step: Int = 0) {
        _answers = State(initialValue: answers)
        _step = State(initialValue: step)
    }

    private var onSummary: Bool { step >= questions.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if onSummary { summary } else { question(questions[step]) }
            Divider()
            footer.padding(Space.margin)
        }
        .frame(width: 560)
        .noInitialFocus()
    }

    // MARK: Questions

    private func question(_ question: SetupQuestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(symbol: question.symbol, caption: String(localized: "Question \(step + 1) of \(questions.count)"),
                   title: question.title, detail: question.detail)
            Form {
                Picker(question.title, selection: Binding(get: { answers[question] }, set: { answers[question] = $0 })) {
                    ForEach(question.options, id: \.value) { option in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                            Text(option.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, Space.xs)
                        .tag(option.value)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            .formStyle(.grouped)
            .fitsContent(max: 320)
        }
        .id(question)
    }

    private func header(symbol: String, caption: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Space.lg) {
            IconTile(symbol: symbol, size: 48)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(caption).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Text(title).font(.title2.weight(.semibold))
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.margin)
    }

    // MARK: Summary

    private var pending: [Tweak] { model.setupChanges(answers) }
    private var apps: [RecommendedApp] { model.setupApps(answers) }
    private var offersTools: Bool { answers.wantsCommandLineTools && !model.commandLineToolsInstalled }

    private var summary: some View {
        let pending = pending
        return VStack(alignment: .leading, spacing: 0) {
            header(symbol: "person.crop.circle.badge.checkmark", caption: String(localized: "Your Setup"),
                   title: pending.isEmpty ? String(localized: "Your Mac Is Already Set Up") : String(localized: "Here’s What Fits You"),
                   detail: String(localized: "Nothing changes yet. You review every change next, and each one can be undone."))
            Form {
                if !pending.isEmpty {
                    Section("Changes") {
                        ForEach(TweakCategory.allCases, id: \.self) { category in
                            let rows = pending.filter { $0.category == category }
                            if !rows.isEmpty {
                                LabeledContent {
                                    Text(rows.count == 1 ? String(localized: "1 change") : String(localized: "\(rows.count) changes"))
                                        .monospacedDigit()
                                } label: {
                                    Label {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(category.title)
                                            Text(rows.map(\.title).formatted(.list(type: .and)))
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    } icon: {
                                        Image(systemName: category.symbol).foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }
                if offersTools || !apps.isEmpty {
                    Section {
                        if offersTools {
                            check(Self.toolsID, title: String(localized: "Command Line Tools for Xcode"),
                                  detail: String(localized: "git, clang, and make, which Homebrew and most code need. Apple’s installer opens."))
                        }
                        ForEach(apps) { app in check(app.id, title: app.name, detail: app.detail) }
                    } header: {
                        Text("Apps")
                    } footer: {
                        if !apps.isEmpty && model.apps.homebrew == nil {
                            Text("These apps install with Homebrew. Install it from Recommended Apps first.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .fitsContent(max: 420)
        }
    }

    private func check(_ id: String, title: String, detail: String) -> some View {
        Toggle(isOn: Binding(get: { !skipped.contains(id) },
                             set: { on in if on { skipped.remove(id) } else { skipped.insert(id) } })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(id != Self.toolsID && model.apps.homebrew == nil)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            if onSummary {
                Button(finishTitle) { finish() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(pending.isEmpty && chosenApps.isEmpty && !chosenTools)
            } else {
                Button("Continue") { step += 1 }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var chosenApps: [RecommendedApp] {
        model.apps.homebrew == nil ? [] : apps.filter { !skipped.contains($0.id) }
    }

    private var chosenTools: Bool { offersTools && !skipped.contains(Self.toolsID) }

    private var finishTitle: String {
        let count = pending.count
        if count == 0 { return String(localized: "Install") }
        return count == 1 ? String(localized: "Review 1 Change") : String(localized: "Review \(count) Changes")
    }

    private func finish() {
        model.finishSetup(answers, apps: chosenApps, commandLineTools: chosenTools)
        dismiss()
    }
}

extension AppModel {
    /// The answers from last time, so the questions open where the person left them.
    var savedSetupAnswers: SetupAnswers {
        guard !Store.isOverridden, let data = UserDefaults.standard.data(forKey: "setup.answers"),
              let answers = try? JSONDecoder().decode(SetupAnswers.self, from: data) else { return SetupAnswers() }
        return answers
    }

    /// The tweaks the answers stage that this Mac can use and does not have yet.
    func setupChanges(_ answers: SetupAnswers) -> [Tweak] {
        answers.tweakIDs.compactMap(Catalog.tweak).filter { status($0).isAvailable && !status($0).isOn }
    }

    /// The apps the answers lead to that Homebrew can install and are not installed yet.
    func setupApps(_ answers: SetupAnswers) -> [RecommendedApp] {
        answers.appIDs().compactMap(Catalog.app).filter { $0.installsWithHomebrew && appState($0) == .notInstalled }
    }

    func openSetup() {
        commandLineToolsInstalled = engine.backend.check(CommandLineTools.check)
        showSetup = true
    }

    /// Opens Set Up for Me the first time the app opens, before anything was changed. Never on a pretend Mac.
    func offerSetupOnFirstLaunch() {
        guard !Store.isOverridden, !UserDefaults.standard.bool(forKey: "setup.offered") else { return }
        UserDefaults.standard.set(true, forKey: "setup.offered")
        if applied.isEmpty && staged.isEmpty { openSetup() }
    }

    /// Stages the answers' changes, starts the installs, and asks for Review once the sheet closes.
    func finishSetup(_ answers: SetupAnswers, apps: [RecommendedApp], commandLineTools: Bool) {
        if !Store.isOverridden, let data = try? JSONEncoder().encode(answers) {
            UserDefaults.standard.set(data, forKey: "setup.answers")
        }
        let changes = setupChanges(answers)
        for tweak in changes { setApplied(tweak, true) }
        log?.add(.info, .app, "Set Up for Me staged \(changes.count) changes",
                 detail: answers.answers.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue): \($0.value)" }.joined(separator: "\n"))
        reviewAfterSetup = !changes.isEmpty
        if commandLineTools {
            let backend = engine.backend
            Task {
                do {
                    try await Task.detached { try backend.run([CommandLineTools.install], admin: false) }.value
                    log?.add(.info, .apps, "Opened Apple’s installer for the Command Line Tools", detail: CommandLineTools.install)
                } catch {
                    notice = error.localizedDescription
                }
            }
        }
        if !apps.isEmpty {
            sidebar = changes.isEmpty ? .apps : sidebar
            Task { await install(apps) }
        }
    }
}
