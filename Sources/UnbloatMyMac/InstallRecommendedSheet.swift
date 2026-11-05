import SwiftUI
import UnbloatMyMacKit

/// The apps an Install Recommended sheet lists, as a sheet item.
struct InstallList: Identifiable {
    let apps: [RecommendedApp]
    var id: String { apps.map(\.id).joined(separator: ",") }
}

/// Lists what Install Recommended will install, each with a checkbox (all on), before anything runs.
struct InstallRecommendedSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let apps: [RecommendedApp]
    @State private var chosen: Set<String>

    init(apps: [RecommendedApp]) {
        self.apps = apps
        _chosen = State(initialValue: Set(apps.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Install Recommended Apps").font(.title2.weight(.semibold))
                Text("Homebrew installs the checked apps. Nothing installs until you click Install. You may be asked for your password.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.margin)
            Form {
                ForEach(AppGroup.allCases, id: \.self) { group in
                    let rows = apps.filter { $0.group == group }
                    if !rows.isEmpty {
                        Section(group.title) {
                            ForEach(rows) { app in row(app) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .fitsContent(max: 520)
            Divider()
            HStack {
                Button(chosen.count == apps.count ? "Uncheck All" : "Check All") {
                    chosen = chosen.count == apps.count ? [] : Set(apps.map(\.id))
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(chosen.count == 1 ? String(localized: "Install 1 App") : String(localized: "Install \(chosen.count) Apps")) {
                    let picked = apps.filter { chosen.contains($0.id) }
                    dismiss()
                    Task { await model.install(picked) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(chosen.isEmpty)
            }
            .padding(Space.margin)
        }
        .frame(width: 560)
        .noInitialFocus()
    }

    private func row(_ app: RecommendedApp) -> some View {
        Toggle(isOn: Binding(
            get: { chosen.contains(app.id) },
            set: { on in if on { chosen.insert(app.id) } else { chosen.remove(app.id) } })) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(verbatim: app.name)
                Text(app.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let command = app.brewCommand {
                    Text(verbatim: command)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .toggleStyle(.checkbox)
    }
}
