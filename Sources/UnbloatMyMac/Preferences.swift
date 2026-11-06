import Foundation
import UnbloatMyMacKit

/// The app's own settings, read and written without a window, for the
/// command line tool. On a pretend Mac (APP_STORE) they live in a JSON file
/// next to the journal, so tests never touch the real defaults.
enum PreferenceStore {
    static let showAdvancedKey = "showAdvanced"
    static let restartAppsKey = "restartApps"
    static let accentKey = "appearance.accent"
    static let languageKey = "AppleLanguages"
    /// Sparkle's own key for automatic checks.
    static let updatesKey = "SUEnableAutomaticChecks"

    private static var fileURL: URL {
        Store.url.deletingPathExtension().appendingPathExtension("preferences.json")
    }

    static func read() -> AppPreferences {
        if Store.isOverridden {
            guard let data = try? Data(contentsOf: fileURL),
                  let saved = try? JSONDecoder().decode(AppPreferences.self, from: data) else {
                return AppPreferences(showAdvanced: false, restartApps: true, accent: ThemeStore.defaultID, language: "system")
            }
            return saved
        }
        let defaults = UserDefaults.standard
        let domain = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        return AppPreferences(
            showAdvanced: defaults.bool(forKey: showAdvancedKey),
            restartApps: defaults.object(forKey: restartAppsKey) as? Bool ?? true,
            accent: defaults.string(forKey: accentKey) ?? ThemeStore.defaultID,
            language: (domain[languageKey] as? [String])?.first ?? "system",
            checksForUpdates: defaults.object(forKey: updatesKey) as? Bool)
    }

    /// Writes what `preferences` has and keeps the rest.
    static func write(_ preferences: AppPreferences) {
        if Store.isOverridden {
            var merged = read()
            if let v = preferences.showAdvanced { merged.showAdvanced = v }
            if let v = preferences.restartApps { merged.restartApps = v }
            if let v = preferences.accent { merged.accent = v }
            if let v = preferences.language { merged.language = v }
            if let v = preferences.checksForUpdates { merged.checksForUpdates = v }
            try? JSONEncoder().encode(merged).write(to: fileURL, options: .atomic)
            return
        }
        let defaults = UserDefaults.standard
        if let v = preferences.showAdvanced { defaults.set(v, forKey: showAdvancedKey) }
        if let v = preferences.restartApps { defaults.set(v, forKey: restartAppsKey) }
        if let v = preferences.accent, Theme.all.contains(where: { $0.id == v }) { defaults.set(v, forKey: accentKey) }
        if let v = preferences.checksForUpdates { defaults.set(v, forKey: updatesKey) }
        if let v = preferences.language {
            if v == "system" { defaults.removeObject(forKey: languageKey) } else { defaults.set([v], forKey: languageKey) }
        }
    }

    /// One line per setting, for the command line: "accent  mint".
    static func lines(_ preferences: AppPreferences) -> [(String, String)] {
        var lines: [(String, String)] = []
        if let v = preferences.showAdvanced { lines.append(("show-advanced", v ? "on" : "off")) }
        if let v = preferences.restartApps { lines.append(("restart-apps", v ? "on" : "off")) }
        if let v = preferences.accent { lines.append(("accent", v)) }
        if let v = preferences.language { lines.append(("language", v)) }
        if let v = preferences.checksForUpdates { lines.append(("update-checks", v ? "on" : "off")) }
        return lines
    }
}
