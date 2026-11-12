import AppKit
import SwiftUI
import UnbloatMyMacKit

/// The versions a Review Device Support sheet lists, as a sheet item.
struct DeviceSupportList: Identifiable {
    let versions: [DeviceSupportVersion]
    var id: String { versions.map(\.path).joined(separator: ",") }
}

/// Lists Xcode's device support versions by device, newest first. Older ones start checked;
/// the newest of each device is kept unless the person checks it too.
struct DeviceSupportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let versions: [DeviceSupportVersion]
    private let newest: Set<String>
    @State private var chosen: Set<String>

    init(versions: [DeviceSupportVersion]) {
        self.versions = versions
        let newest = DeviceSupportFinder.newest(versions)
        self.newest = newest
        _chosen = State(initialValue: Set(versions.map(\.path)).subtracting(newest))
    }

    private var oldCount: Int { versions.count - newest.count }
    private var chosenBytes: Int64 { versions.filter { chosen.contains($0.path) }.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Xcode Device Support").font(.title2.weight(.semibold))
                Text(oldCount == 0 ? String(localized: "No old versions found. Only the newest version of each device is here.")
                     : oldCount == 1 ? String(localized: "1 old version found. The newest version of each device stays unless you check it.")
                     : String(localized: "\(oldCount) old versions found. The newest version of each device stays unless you check it."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.margin)
            Form {
                ForEach(DeviceSupportFinder.grouped(versions), id: \.group) { group in
                    Section {
                        ForEach(group.versions) { version in row(version) }
                    } header: {
                        Text(verbatim: group.group)
                    } footer: {
                        if group.versions.contains(where: { newest.contains($0.path) && chosen.contains($0.path) }) {
                            Label("Xcode copies the newest version again, which takes several minutes, the next time you connect this device.",
                                  systemImage: "exclamationmark.triangle")
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
                Button(chosen.count == versions.count ? "Uncheck All" : "Check All") {
                    chosen = chosen.count == versions.count ? [] : Set(versions.map(\.path))
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(chosen.isEmpty ? String(localized: "Move to Trash")
                       : String(localized: "Move \(chosen.count) to Trash (\(chosenBytes.bytesText))")) {
                    let picked = versions.filter { chosen.contains($0.path) }
                    dismiss()
                    Task { await model.trash(deviceSupport: picked) }
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

    private func row(_ version: DeviceSupportVersion) -> some View {
        Toggle(isOn: Binding(
            get: { chosen.contains(version.path) },
            set: { on in if on { chosen.insert(version.path) } else { chosen.remove(version.path) } })) {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.sm) {
                        Text(verbatim: "\(version.platform) \(version.title)")
                        if newest.contains(version.path) {
                            Tag(text: String(localized: "Newest"), symbol: "checkmark.shield", style: Palette.accentText)
                        }
                    }
                    Text("Copied \(version.modified, format: .dateTime.day().month().year())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Space.lg)
                Text(version.bytes.bytesText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .toggleStyle(.checkbox)
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile((version.path as NSString).expandingTildeInPath, inFileViewerRootedAtPath: "")
            }
        }
    }
}
