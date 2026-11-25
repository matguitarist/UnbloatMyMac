import AppKit
import SwiftUI

// Shared by my Mac apps (sync-mac-tools): change it everywhere or nowhere.
// Views that belong to one app go in their own files.

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

/// A small capsule label under a row or beside a title: a version, a source, a state.
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

/// A rounded card.
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

extension UInt64 {
    var bytesText: String { ByteCountFormatter.string(fromByteCount: Int64(clamping: self), countStyle: .file) }
}
