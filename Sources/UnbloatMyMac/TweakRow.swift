import AppKit
import SwiftUI
import UnbloatMyMacKit

/// One tweak with its switch.
struct TweakRow: View {
    @Environment(AppModel.self) private var model
    let tweak: Tweak

    var body: some View {
        let status = model.status(tweak)
        let staged = model.staged[tweak.id] != nil
        HStack(alignment: .top, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.sm) {
                    Text(tweak.title)
                    Button {
                        model.detailsTweak = tweak.id
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("What \(tweak.title) changes")
                    .accessibilityLabel("Details for \(tweak.title)")
                    .popover(isPresented: Binding(get: { model.detailsTweak == tweak.id },
                                                  set: { if !$0 { model.detailsTweak = nil } }),
                             arrowEdge: .bottom) {
                        TweakDetails(tweak: tweak)
                    }
                    if staged {
                        Text(model.switchIsOn(tweak) ? "Will turn on" : "Will turn off")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.accentText)
                    }
                }
                Text(tweak.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let caveat = tweak.caveat {
                    Label(caveat, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                tags(status)
            }
            Spacer(minLength: Space.lg)
            Toggle(tweak.title, isOn: Binding(get: { model.switchIsOn(tweak) }, set: { model.setSwitch(tweak, $0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!status.isAvailable || model.isBusy)
                .help(help(status))
        }
        .padding(.vertical, 2)
        .opacity(status.isAvailable ? 1 : 0.55)
    }

    @ViewBuilder
    private func tags(_ status: TweakStatus) -> some View {
        let tags = tagList(status)
        if !tags.isEmpty {
            HStack(spacing: Space.xs) {
                ForEach(tags, id: \.text) { tag in tag }
            }
            .padding(.top, 2)
        }
    }

    private func tagList(_ status: TweakStatus) -> [Tag] {
        var list: [Tag] = []
        if let recommended = tweak.recommendedSwitch {
            // Accent when the switch is not where it should be, so it stands out.
            list.append(Tag(text: recommended ? String(localized: "Recommended: On") : String(localized: "Recommended: Off"),
                            symbol: "hand.thumbsup", style: model.switchIsOn(tweak) == recommended ? nil : Palette.accentText))
        }
        switch status {
        case .unavailable(let reason): list.append(Tag(text: reason, symbol: "nosign"))
        case .waiting: list.append(Tag(text: String(localized: "Approve in System Settings"), symbol: "hourglass", style: .orange))
        case .partial: list.append(Tag(text: String(localized: "Partly applied"), symbol: "circle.lefthalf.filled"))
        default: break
        }
        if tweak.risk == .advanced { list.append(Tag(text: String(localized: "Advanced"), symbol: "exclamationmark.shield", style: .orange)) }
        if tweak.needsAdmin { list.append(Tag(text: String(localized: "Password"), symbol: "lock")) }
        if tweak.usesProfile { list.append(Tag(text: String(localized: "Profile"), symbol: "checkmark.shield")) }
        if !tweak.agents.isEmpty { list.append(Tag(text: String(localized: "Stops a service"), symbol: "stop.circle")) }
        let restarts = tweak.restarts.filter { $0 != .logout }.map(\.rawValue)
        if !restarts.isEmpty { list.append(Tag(text: String(localized: "Restarts \(restarts.joined(separator: ", "))"), symbol: "arrow.clockwise")) }
        if tweak.restarts.contains(.logout) { list.append(Tag(text: String(localized: "After log out"), symbol: "person.crop.circle.badge.clock")) }
        return list
    }

    private func help(_ status: TweakStatus) -> String {
        if case .unavailable(let reason) = status { return reason }
        return tweak.namesFeature ? String(localized: "Turn \(tweak.title) on or off") : String(localized: "Turn on to apply, off to undo")
    }
}

/// What a tweak changes: each command it runs and how undo puts it back.
struct TweakDetails: View {
    @Environment(AppModel.self) private var model
    let tweak: Tweak

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(tweak.title).font(.headline)
                Text(tweak.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            lines(String(localized: "What it changes"), tweak.actions.map(\.applyLine))
            lines(String(localized: "How undo puts it back"), tweak.actions.map(\.undoLine))
            Text("Before any change, the value from before is saved in the undo journal.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(verbatim: tweak.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                Button("Copy Commands") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(tweak.actions.map(\.applyLine).joined(separator: "\n"), forType: .string)
                }
            }
        }
        .padding(Space.lg)
        .frame(width: 480)
        .noInitialFocus()
    }

    private func lines(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
