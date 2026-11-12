import Foundation

/// Finds what deleted apps left in ~/Library. The rules are here, free of the
/// file system, so tests check them; `MacBackend` feeds them real folders.
public enum LeftoverFinder {
    /// Library folders whose items are named after an app's bundle id.
    /// Containers are left out: measuring them makes macOS ask for access to other apps' data.
    /// Caches and Logs are left out: the Storage page cleans them whole.
    public static let folders = ["Application Support", "Preferences", "Saved Application State", "HTTPStorages", "WebKit"]

    /// Not touched for this long, so nothing is using it.
    public static let quietPeriod: TimeInterval = 30 * 24 * 3600

    private static let suffixes = [".plist", ".savedState", ".binarycookies"]

    /// Frameworks and tools many apps share, or that live outside Applications: never leftovers.
    public static let shared = ["org.sparkle-project.", "org.python.", "org.webkit.", "com.github.Electron",
                                "org.chromium.", "com.google.Keystone", "com.microsoft.autoupdate"]

    /// The bundle id in a file or folder name, or nil when the name is not one,
    /// or belongs to Apple. com.spotify.client.plist -> com.spotify.client.
    public static func bundleID(fromName name: String) -> String? {
        var id = name
        // Temporary files: local.app.binarycookies_tmp_32077.dat belongs to local.app, and is not worth listing.
        if name.contains(".binarycookies") && !name.hasSuffix(".binarycookies") { return nil }
        for suffix in suffixes where id.hasSuffix(suffix) { id.removeLast(suffix.count) }
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard id.unicodeScalars.allSatisfy({ allowed.contains($0) || $0 == "." }) else { return nil }
        // Reverse DNS starts with a word, like com or io, not a team id or a version.
        guard parts[0].allSatisfy(\.isLetter) else { return nil }
        let lower = id.lowercased()
        if lower.hasPrefix("com.apple.") || lower.hasPrefix("group.") { return nil }
        if shared.contains(where: { lower.hasPrefix($0.lowercased()) }) { return nil }
        return id
    }

    /// The app part of a bundle id: com.spotify.client.helper -> com.spotify.client.
    static func appKey(_ id: String) -> String { id.lowercased().split(separator: ".").prefix(3).joined(separator: ".") }

    /// The developer part: com.spotify.client -> com.spotify.
    static func developerKey(_ id: String) -> String { id.lowercased().split(separator: ".").prefix(2).joined(separator: ".") }

    /// What the installed apps are, for `owner(of:)`.
    public struct Installed: Sendable {
        var apps: Set<String> = []
        var developers: Set<String> = []

        public init(bundleIDs: some Sequence<String>) {
            for id in bundleIDs {
                apps.insert(LeftoverFinder.appKey(id))
                developers.insert(LeftoverFinder.developerKey(id))
            }
        }

        /// An installed app has this id, or one that starts with the same three parts.
        public func hasApp(for id: String) -> Bool { apps.contains(LeftoverFinder.appKey(id)) }
        public func hasDeveloper(of id: String) -> Bool { developers.contains(LeftoverFinder.developerKey(id)) }
    }

    /// A leftover, or nil when the item belongs to an installed app, is not named
    /// after an app, or changed in the last 30 days.
    /// `registered` asks LaunchServices whether an app with that id exists anywhere.
    public static func leftover(path: String, installed: Installed, registered: (String) -> Bool,
                                bytes: Int64, modified: Date, now: Date = .now, ownID: String? = Bundle.main.bundleIdentifier) -> Leftover? {
        guard let id = bundleID(fromName: (path as NSString).lastPathComponent) else { return nil }
        if let ownID, appKey(id) == appKey(ownID) { return nil }
        if installed.hasApp(for: id) || registered(id) { return nil }
        if now.timeIntervalSince(modified) < quietPeriod { return nil }
        return Leftover(path: path, bundleID: id, bytes: bytes, modified: modified,
                        sameDeveloperInstalled: installed.hasDeveloper(of: id))
    }
}

/// Cache folders of apps built on Chromium and Electron (Slack, Discord,
/// VS Code, and many more) in Application Support. They rebuild them.
public enum ChromiumCaches {
    /// An app folder with one of these is a Chromium profile.
    static let markers: Set<String> = ["Code Cache", "GPUCache"]
    /// What can go. Settings, cookies, and local storage stay.
    public static let names = ["Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "GrShaderCache", "ShaderCache"]

    /// The cache folders in `folder`. `list` returns the names inside a folder.
    public static func paths(in folder: String, list: (String) -> [String]) -> [String] {
        list(folder).sorted().flatMap { app -> [String] in
            let appFolder = (folder as NSString).appendingPathComponent(app)
            let inside = Set(list(appFolder))
            guard !inside.isDisjoint(with: markers) else { return [] }
            return names.filter(inside.contains).map { (appFolder as NSString).appendingPathComponent($0) }
        }
    }
}
