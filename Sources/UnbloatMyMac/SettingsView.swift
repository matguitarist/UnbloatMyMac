import AppKit
import SwiftUI

/// The Settings window (Command-Comma). One tab per topic, at most about
/// six. Each tab is a grouped Form that sizes to its content, so the
/// window grows to fit and shows no scroll bar it does not need.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .appearance: AppearanceSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Tweaks") {
            Toggle(isOn: $model.showAdvanced) {
                Text("Show advanced tweaks")
                Text("Tweaks that stop system services. Some features stop working until you undo them.")
            }
            Toggle(isOn: $model.restartApps) {
                Text("Restart the Dock, Finder, and menu bar after applying")
                Text("Changes show at once. Turn off to see them after you log out.")
            }
        }
        Section("Undo History") {
            LabeledContent("Saved in") {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Store.url]) }
            }
            Text("The value of every setting before UnbloatMyMac changed it is kept here, so Undo Everything can put it back.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
