import Foundation

/// Places UnbloatMyMac never moves to the Trash, whatever asks: what nothing could bring back
/// (keychains, iCloud Drive, mail, messages, photo libraries, keys) and the folders that hold
/// everything else (your home, Library, Documents). Checked at the last moment, on the path and
/// on where its links lead, so a bug elsewhere or a folder swapped for a link cannot reach them.
public enum ProtectedPaths {
    /// In ~/Library: these and everything inside them.
    static let library = [
        "Keychains", "Mobile Documents", "CloudStorage", "Mail", "Messages", "Safari", "Calendars", "Reminders",
        "Passes", "Photos", "Autosave Information", "Accounts", "HomeKit", "IdentityServices", "Shortcuts",
        "Spelling", "KeyboardServices", "Daemon Containers",
        "Application Support/MobileSync", "Application Support/AddressBook", "Application Support/CallHistoryDB",
        "Application Support/CloudDocs", "Application Support/FileProvider", "Application Support/FaceTime",
        "Caches/CloudKit", "Caches/com.apple.bird", "Caches/com.apple.cloudd",
    ]

    /// In your home: these and everything inside them.
    static let inHome = [".ssh", ".gnupg", ".aws", ".password-store", ".Trash", ".kube", ".git-credentials", ".netrc"]

    /// These folders themselves stay; what is inside them may go.
    static let homeFolders = ["", "Library", "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music",
                              "Public", "Applications", "Developer", ".config", ".cache", ".local"]

    /// Outside your home: these and everything inside them.
    static let system = ["/System", "/usr", "/bin", "/sbin", "/private/etc", "/private/var/db", "/Library/Keychains"]

    /// Outside your home: these folders themselves.
    static let systemFolders = ["/", "/Applications", "/Library", "/Users", "/Users/Shared", "/Volumes", "/opt", "/private",
                                "/private/var", "/private/tmp", "/tmp", "/var", "/etc"]

    /// Whole photo, music, and video collections, wherever they are.
    static let libraryExtensions: Set<String> = ["photoslibrary", "photolibrary", "migratedphotolibrary", "musiclibrary",
                                                 "tvlibrary", "imovielibrary", "fcpbundle", "aplibrary"]

    /// Why this path must stay, or nil when it may move to the Trash. English, for the Activity Log.
    public static func reason(for path: String, home homePath: String = NSHomeDirectory()) -> String? {
        let path = clean(path)
        let home = clean(homePath)
        func within(_ base: String) -> Bool { path == base || path.hasPrefix(base + "/") }

        for folder in homeFolders where path == clean(home + "/" + folder) { return "it is a folder that holds your files" }
        if systemFolders.contains(path) { return "it is a system folder" }
        // Library's own folders (Caches, Preferences…) stay; only what is inside them may go.
        if (path as NSString).deletingLastPathComponent == home + "/Library" { return "it is one of Library's own folders" }
        for item in library where within(home + "/Library/" + item) { return "it holds data nothing could bring back" }
        for item in inHome where within(home + "/" + item) { return "it holds keys or credentials" }
        for item in system where within(item) { return "macOS needs it" }
        // Apple's group containers hold notes, reminders, and more on macOS 26 and later.
        let groups = home + "/Library/Group Containers/"
        if path.hasPrefix(groups), path.dropFirst(groups.count).split(separator: "/").first?.contains("com.apple") == true {
            return "it holds data nothing could bring back"
        }
        if path.split(separator: "/").contains(where: { libraryExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) {
            return "it is a photo, music, or video library"
        }
        return nil
    }

    /// Absolute, without "." or "..", and without a trailing slash.
    static func clean(_ path: String) -> String {
        let standard = ((path as NSString).expandingTildeInPath as NSString).standardizingPath
        return standard.count > 1 && standard.hasSuffix("/") ? String(standard.dropLast()) : standard
    }
}
