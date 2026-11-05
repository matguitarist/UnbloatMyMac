import SwiftUI
import UnbloatMyMacKit

/// Shows every staged change and what will happen, then applies them.
struct ReviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var report: ApplyReport?
    @State private var applying = false

    var body: some View {
        VStack(spacing: 0) {
            if let report {
                result(report)
            } else {
                review
            }
        }
        .frame(width: 560)
        .noInitialFocus()
    }

    // MARK: Before

    private var review: some View {
        let tweaks = model.stagedTweaks
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.xs) {
                (tweaks.count == 1 ? Text("Review 1 Change") : Text("Review \(tweaks.count) Changes")).font(.title2.weight(.semibold))
                Text("Nothing has changed yet. Each change can be undone later.").foregroundStyle(.secondary)
            }
            .padding(Space.margin)
            Form {
                ForEach(TweakCategory.allCases, id: \.self) { category in
                    let rows = tweaks.filter { $0.category == category }
                    if !rows.isEmpty {
                        Section(category.title) {
                            ForEach(rows) { tweak in
                                LabeledContent(tweak.title) {
                                    Text(model.switchIsOn(tweak) ? "Turns on" : "Turns off")
                                        .foregroundStyle(Palette.accentText)
                                }
                            }
                        }
                    }
                }
                let notes = self.notes(tweaks)
                if !notes.isEmpty {
                    Section("What Happens") {
                        ForEach(notes, id: \.0) { note in
                            Label(note.0, systemImage: note.1)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .fitsContent(max: 520)
            Divider()
            HStack {
                if applying {
                    ProgressView().controlSize(.small)
                    Text("Applying…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(applying)
                Button("Apply Changes") {
                    applying = true
                    Task {
                        report = await model.applyStaged()
                        applying = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(applying || tweaks.isEmpty)
            }
            .padding(Space.margin)
        }
    }

    private func notes(_ tweaks: [Tweak]) -> [(String, String)] {
        var notes: [(String, String)] = []
        if tweaks.contains(where: \.needsAdmin) {
            notes.append((String(localized: "macOS asks for your password once."), "lock"))
        }
        if tweaks.contains(where: \.usesProfile) {
            notes.append((String(localized: "System Settings opens with a profile. Approve it in General > Device Management to finish the Apple Intelligence changes."), "checkmark.shield"))
        }
        let restarts = Set(tweaks.flatMap(\.restarts)).subtracting([.logout]).map(\.rawValue).sorted()
        if !restarts.isEmpty {
            let names = restarts.joined(separator: ", ")
            notes.append((model.restartApps ? String(localized: "\(names) restart, so the screen may flicker.")
                          : String(localized: "Restart \(names) to see some changes."), "arrow.clockwise"))
        }
        if tweaks.contains(where: { $0.restarts.contains(.logout) }) {
            notes.append((String(localized: "Some changes show in apps you open from now on, and everywhere after you log out."), "person.crop.circle.badge.clock"))
        }
        return notes
    }

    // MARK: After

    private func result(_ report: ApplyReport) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(spacing: Space.md) {
                Image(systemName: report.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(report.failures.isEmpty ? AnyShapeStyle(.tint) : AnyShapeStyle(.orange))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.failures.isEmpty ? "Done" : "Some Changes Didn’t Apply").font(.title2.weight(.semibold))
                    (report.changed == 1 ? Text("1 change applied.") : Text("\(report.changed) changes applied.")).foregroundStyle(.secondary)
                }
            }
            if !report.failures.isEmpty {
                VStack(alignment: .leading, spacing: Space.sm) {
                    ForEach(report.failures.sorted(by: { $0.key < $1.key }), id: \.key) { id, message in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Catalog.tweak(id)?.title ?? id).font(.headline)
                            Text(message).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if report.profileHandedOff {
                Label("Approve “UnbloatMyMac: Apple Intelligence” in System Settings > General > Device Management.", systemImage: "checkmark.shield")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if report.needsFullDiskAccess {
                Label("Some settings are protected. Give UnbloatMyMac Full Disk Access, then apply them again.", systemImage: "lock.shield")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if report.needsLogout {
                Label("Log out and back in to finish every change.", systemImage: "person.crop.circle.badge.clock")
            }
            HStack {
                if report.profileHandedOff {
                    Button("Open Device Management") { model.openSystemSettings("com.apple.Profiles-Settings.extension") }
                }
                if report.needsFullDiskAccess {
                    Button("Open Full Disk Access Settings") {
                        model.openSystemSettings("com.apple.preference.security?Privacy_AllFiles")
                    }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Space.margin)
    }
}
