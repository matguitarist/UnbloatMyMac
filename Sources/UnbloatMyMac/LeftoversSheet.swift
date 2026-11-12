import AppKit
import SwiftUI
import UnbloatMyMacKit

/// The leftovers a Review Leftovers sheet lists, as a sheet item.
struct LeftoverList: Identifiable {
    let items: [Leftover]
    var id: String { items.map(\.path).joined(separator: ",") }
}

/// Lists what deleted apps left in ~/Library, one section per app, before anything moves to the Trash.
/// Items from a developer who still has an app installed start unchecked.
struct LeftoversSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let items: [Leftover]
    @State private var chosen: Set<String>

    init(items: [Leftover]) {
        self.items = items
        _chosen = State(initialValue: Set(items.filter { !$0.sameDeveloperInstalled }.map(\.path)))
    }

    /// Bundle ids, biggest first.
    private var apps: [String] {
        var seen: [String] = []
        for item in items where !seen.contains(item.bundleID) { seen.append(item.bundleID) }
        return seen.sorted { bytes(of: $0) > bytes(of: $1) }
    }

    private func bytes(of app: String) -> Int64 { items.filter { $0.bundleID == app }.reduce(0) { $0 + $1.bytes } }

    private var chosenBytes: Int64 { items.filter { chosen.contains($0.path) }.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Leftovers from Deleted Apps").font(.title2.weight(.semibold))
                Text("No installed app uses these, and nothing changed them in 30 days. Checked items move to the Trash; put them back from there if an app misses them.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.margin)
            Form {
                ForEach(apps, id: \.self) { app in
                    Section {
                        ForEach(items.filter { $0.bundleID == app }) { item in row(item) }
                    } header: {
                        HStack {
                            Text(verbatim: app)
                            Spacer()
                            Text(bytes(of: app).bytesText).monospacedDigit()
                        }
                    } footer: {
                        if items.contains(where: { $0.bundleID == app && $0.sameDeveloperInstalled }) {
                            Label("Another app from this developer is installed and may still use these.", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .fitsContent(max: 520)
            Divider()
            HStack {
                Button(chosen.count == items.count ? "Uncheck All" : "Check All") {
                    chosen = chosen.count == items.count ? [] : Set(items.map(\.path))
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(chosen.isEmpty ? String(localized: "Move to Trash")
                       : String(localized: "Move \(chosen.count) to Trash (\(chosenBytes.bytesText))")) {
                    let picked = items.filter { chosen.contains($0.path) }
                    dismiss()
                    Task { await model.trash(picked) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(chosen.isEmpty)
            }
            .padding(Space.margin)
        }
        .frame(width: 600)
        .noInitialFocus()
    }

    private func row(_ item: Leftover) -> some View {
        Toggle(isOn: Binding(
            get: { chosen.contains(item.path) },
            set: { on in if on { chosen.insert(item.path) } else { chosen.remove(item.path) } })) {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(verbatim: (item.path as NSString).lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(item.place) · last changed \(item.modified, format: .dateTime.day().month().year())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Space.lg)
                Text(item.bytes.bytesText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .toggleStyle(.checkbox)
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile((item.path as NSString).expandingTildeInPath, inFileViewerRootedAtPath: "")
            }
        }
    }
}
