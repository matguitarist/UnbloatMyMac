import SwiftUI
import UnbloatMyMacKit

/// A symbol on a tinted rounded square, like the icons in System Settings.
struct IconTile: View {
    let symbol: String
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(Palette.onAccent)
            .frame(width: size, height: size)
            .background(Palette.accent.gradient, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The first row of a page: icon, title, summary, and actions.
struct PageHeader<Actions: View>: View {
    let symbol: String
    let title: String
    let summary: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: Space.lg) {
            IconTile(symbol: symbol, size: 48)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(.title2.weight(.semibold))
                Text(summary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.sm) { actions }
                    .padding(.top, Space.sm)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.sm)
    }
}

/// A small label under a tweak: needs a password, restarts the Dock, and so on.
struct Tag: View {
    let text: String
    let symbol: String
    var style: Color? = nil

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(style.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.6), in: Capsule())
    }
}

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
        switch status {
        case .unavailable(let reason): list.append(Tag(text: reason, symbol: "nosign"))
        case .waiting: list.append(Tag(text: "Approve in System Settings", symbol: "hourglass", style: .orange))
        case .partial: list.append(Tag(text: "Partly applied", symbol: "circle.lefthalf.filled"))
        default: break
        }
        if tweak.risk == .advanced { list.append(Tag(text: "Advanced", symbol: "exclamationmark.shield", style: .orange)) }
        if tweak.needsAdmin { list.append(Tag(text: "Password", symbol: "lock")) }
        if tweak.usesProfile { list.append(Tag(text: "Profile", symbol: "checkmark.shield")) }
        if !tweak.agents.isEmpty { list.append(Tag(text: "Stops a service", symbol: "stop.circle")) }
        let restarts = tweak.restarts.filter { $0 != .logout }.map(\.rawValue)
        if !restarts.isEmpty { list.append(Tag(text: "Restarts \(restarts.joined(separator: ", "))", symbol: "arrow.clockwise")) }
        if tweak.restarts.contains(.logout) { list.append(Tag(text: "After log out", symbol: "person.crop.circle.badge.clock")) }
        return list
    }

    private func help(_ status: TweakStatus) -> String {
        if case .unavailable(let reason) = status { return reason }
        return tweak.namesFeature ? "Turn \(tweak.title) on or off" : "Turn on to apply, off to undo"
    }
}

/// A rounded card for the Overview page.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) { content }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(.separator, lineWidth: 1))
    }
}

extension Int64 {
    var bytesText: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
