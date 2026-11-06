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
            case .updates: UpdateSettings()
            case .backup: BackupSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, updates, backup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .appearance: String(localized: "Appearance")
        case .updates: String(localized: "Updates")
        case .backup: String(localized: "Backup")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .updates: "arrow.triangle.2.circlepath"
        case .backup: "externaldrive.badge.timemachine"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Language") {
            Picker("Language", selection: $model.language) {
                Text("System (\(AppLanguage.systemName))").tag(AppLanguage.system)
                // Every language the app is translated into, each named in itself.
                ForEach(AppLanguage.available, id: \.self) { language in
                    Text(verbatim: language.name).tag(language)
                }
            }
            if model.language != AppLanguage.atLaunch {
                HStack {
                    Text("The new language applies after a restart.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restart Now") { AppLanguage.relaunch() }
                        .disabled(model.isBusy)
                        .help(model.isBusy ? String(localized: "Wait for the changes to finish") : "")
                }
            }
        }
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
    }
}

/// Settings > Updates: Sparkle's automatic checks.
struct UpdateSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Automatic Updates") {
            Toggle(isOn: $model.checksForUpdates) {
                Text("Check for updates automatically")
                Text(updatesNote)
            }
            .disabled(!Updater.shared.isAvailable)
            LabeledContent("Version \(Self.version)") {
                Button("Check Now") { Updater.shared.checkForUpdates() }
                    .disabled(!Updater.shared.isAvailable)
            }
        }
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }

    private var updatesNote: String {
        guard Updater.shared.isAvailable else { return String(localized: "Updates are off in this build.") }
        guard let last = Updater.shared.lastCheck else { return String(localized: "Looks once a day for a new version on GitHub.") }
        return String(localized: "Looks once a day for a new version on GitHub. Last checked \(last.formatted(.relative(presentation: .named))).")
    }
}

/// Settings > Backup: the settings backup and the undo journal.
struct BackupSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section("Settings Backup") {
            LabeledContent {
                HStack(spacing: Space.sm) {
                    Button("Back Up…") { model.backUpWithPanel() }
                    Button("Restore…") { model.restoreWithPanel() }
                        .disabled(model.isBusy)
                }
            } label: {
                Text("Settings and tweaks")
                Text("Saves UnbloatMyMac’s settings, the accent, and the tweaks that are on to one file. Restoring sets them back at once and opens Review for the tweaks.")
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

/// The app's own language, independent of macOS's. Stored as the app's
/// AppleLanguages default, which macOS reads at launch. The choices come
/// from the bundle, so adding a translation adds it here.
struct AppLanguage: Hashable {
    /// A localization code ("fr", "pt-BR"), or nil to follow macOS.
    let code: String?

    static let system = AppLanguage(code: nil)
    private static let key = "AppleLanguages"

    /// The app's translations, sorted by their own names.
    static let available: [AppLanguage] = Set(Bundle.main.localizations)  // can list one twice
        .subtracting(["Base"])
        .map { AppLanguage(code: $0) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    /// "Français", "English".
    var name: String {
        guard let code else { return "" }
        let name = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    static var current: AppLanguage {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        guard let stored = (domain?[key] as? [String])?.first else { return .system }
        // "fr-CA" set elsewhere still selects "fr".
        let codes = available.compactMap(\.code)
        guard let match = Bundle.preferredLocalizations(from: codes, forPreferences: [stored]).first,
              codes.contains(match) else { return .system }
        return AppLanguage(code: match)
    }

    /// What this run of the app uses (the setting can change after launch).
    static let atLaunch = current

    /// The language macOS would pick for the app, by name ("Français").
    static var systemName: String {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[key] as? [String] ?? Locale.preferredLanguages
        let code = Bundle.preferredLocalizations(from: available.compactMap(\.code), forPreferences: global).first ?? "en"
        return AppLanguage(code: code).name
    }

    /// Test and snapshot runs never change the real setting.
    func apply() {
        guard !Store.isOverridden else { return }
        if let code {
            UserDefaults.standard.set([code], forKey: Self.key)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.key)
        }
    }

    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
