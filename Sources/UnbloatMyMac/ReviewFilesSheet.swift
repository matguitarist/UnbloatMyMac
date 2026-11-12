import AppKit
import SwiftUI
import UnbloatMyMacKit

/// What a review sheet lists: the target and its items.
struct ReviewFileList: Identifiable {
    let target: CleanupTarget
    let items: [ReviewItem]
    var id: String { target.id + items.map(\.path).joined(separator: ",") }
}

/// Lists old installers or project build files by folder, before anything moves to the Trash.
/// Suggested items start checked; the rest say why they are left to you.
struct ReviewFilesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let list: ReviewFileList
    @State private var chosen: Set<String>

    init(list: ReviewFileList) {
        self.list = list
        _chosen = State(initialValue: Set(list.items.filter(\.suggested).map(\.path)))
    }

    private var items: [ReviewItem] { list.items }
    private var groups: [String] {
        var seen: [String] = []
        for item in items where !seen.contains(item.group) { seen.append(item.group) }
        return seen
    }
    /// What moves: a part inside a picked folder goes with it, so it is counted once.
    private var picked: [ReviewItem] { ReviewItem.outermost(items.filter { chosen.contains($0.path) }) }
    private var chosenBytes: Int64 { picked.reduce(0) { $0 + $1.bytes } }

    private var intro: String {
        switch list.target.kind {
        case .buildArtifacts:
            String(localized: "Each folder sits beside the file of the tool that makes it, which builds it again when you need it. Projects you changed in the last week start unchecked, but a Rust project’s incremental caches and builds unused for a month are still picked.")
        default:
            String(localized: "You can download these again from where they came from. A disk image that wasn’t downloaded may be one you made, so it starts unchecked.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(list.target.title).font(.title2.weight(.semibold))
                Text(intro)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.margin)
            Form {
                ForEach(groups, id: \.self) { group in
                    let rows = items.filter { $0.group == group }
                    Section {
                        ForEach(rows) { item in row(item) }
                    } header: {
                        HStack {
                            Text(verbatim: group)
                            Spacer()
                            Text(ReviewItem.outermost(rows).reduce(0) { $0 + $1.bytes }.bytesText).monospacedDigit()
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
                       : String(localized: "Move \(picked.count) to Trash (\(chosenBytes.bytesText))")) {
                    let picked = picked
                    dismiss()
                    Task { await model.trash(picked, from: list.target) }
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

    private func row(_ item: ReviewItem) -> some View {
        Toggle(isOn: Binding(
            get: { chosen.contains(item.path) },
            set: { on in if on { chosen.insert(item.path) } else { chosen.remove(item.path) } })) {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(verbatim: item.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(item.detail) · changed \(item.modified, format: .dateTime.day().month().year())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let note = item.note {
                        Label(note, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
