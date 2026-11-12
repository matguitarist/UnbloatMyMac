import Foundation

/// One file or folder a reviewed Storage target lists: an old installer, or what a build left in a project.
public struct ReviewItem: Identifiable, Hashable, Sendable {
    public var path: String
    /// The section it is listed in: a folder, or a project.
    public var group: String
    public var name: String
    public var detail: String
    public var bytes: Int64
    public var modified: Date
    /// Checked when the sheet opens. The rest are listed and left to you.
    public var suggested: Bool
    /// Why it is not suggested, when it is not.
    public var note: String?

    public init(path: String, group: String, name: String, detail: String, bytes: Int64, modified: Date,
                suggested: Bool, note: String? = nil) {
        self.path = path
        self.group = group
        self.name = name
        self.detail = detail
        self.bytes = bytes
        self.modified = modified
        self.suggested = suggested
        self.note = note
    }

    public var id: String { path }

    /// What the Storage row shows: the suggested items, and how many others are listed.
    public static func size(of items: [ReviewItem]) -> CleanupSize {
        let suggested = items.filter(\.suggested)
        return CleanupSize(bytes: suggested.reduce(0) { $0 + $1.bytes }, items: suggested.count, kept: items.count - suggested.count)
    }
}

/// Disk images and installer packages left in Downloads or on the Desktop after the app was installed.
public enum InstallerFinder {
    public static let folders = ["~/Downloads", "~/Desktop"]
    static let extensions: Set<String> = ["dmg", "pkg", "mpkg"]
    /// Smaller ones are not worth a row.
    public static let minimumBytes: Int64 = 20_000_000
    /// Something downloaded in the last day may still be in use.
    public static let quietPeriod: TimeInterval = 24 * 3600

    /// An installer to list, or nil. One that says where it was downloaded from can be downloaded again,
    /// so it is suggested; one that doesn't may be a disk image you made, so it is left to you.
    public static func item(path: String, folder: String, bytes: Int64, modified: Date, downloaded: Bool,
                            mounted: Set<String>, now: Date = .now) -> ReviewItem? {
        let name = (path as NSString).lastPathComponent
        guard extensions.contains((name as NSString).pathExtension.lowercased()), !name.hasPrefix("."),
              bytes >= minimumBytes, now.timeIntervalSince(modified) >= quietPeriod else { return nil }
        if mounted.contains(ProtectedPaths.clean(path)) { return nil }
        let kind = (name as NSString).pathExtension.lowercased() == "dmg" ? L("Disk image") : L("Installer package")
        return ReviewItem(path: path, group: folder, name: name, detail: kind, bytes: bytes, modified: modified,
                          suggested: downloaded,
                          note: downloaded ? nil : L("Not downloaded from the web, so it may be a disk image you made. Look before you pick it."))
    }

    /// The disk images open now, from `hdiutil info`.
    public static func mounted(fromHdiutil output: String) -> Set<String> {
        Set(output.split(separator: "\n").compactMap { line -> String? in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "image-path" else { return nil }
            return ProtectedPaths.clean(parts[1].trimmingCharacters(in: .whitespaces))
        })
    }
}

/// What builds left in your projects. A folder is listed only when the file of the tool that makes it
/// sits beside it, so a folder that merely has the same name is never touched.
public enum BuildArtifactFinder {
    /// Folders searched for projects, when they exist.
    public static let roots = ["~/Developer", "~/Projects", "~/Code", "~/code", "~/src", "~/GitHub", "~/Repos", "~/repos"]
    /// How deep to look for projects below a root.
    public static let maxDepth = 5
    /// A project changed in the last week is likely still being worked on.
    public static let quietPeriod: TimeInterval = 7 * 24 * 3600

    public struct Rule: Sendable {
        public var folder: String
        /// One of these files must be beside the folder.
        public var markers: [String]
        public var tool: String
    }

    public static let rules: [Rule] = [
        Rule(folder: "node_modules", markers: ["package.json"], tool: "npm, Yarn, pnpm, or Bun"),
        Rule(folder: "target", markers: ["Cargo.toml"], tool: "Cargo"),
        Rule(folder: ".build", markers: ["Package.swift"], tool: "Swift Package Manager"),
        Rule(folder: "build", markers: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"], tool: "Gradle"),
        Rule(folder: ".gradle", markers: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"], tool: "Gradle"),
        Rule(folder: ".next", markers: ["next.config.js", "next.config.mjs", "next.config.ts"], tool: "Next.js"),
        Rule(folder: ".nuxt", markers: ["nuxt.config.js", "nuxt.config.ts"], tool: "Nuxt"),
        Rule(folder: ".svelte-kit", markers: ["svelte.config.js", "svelte.config.ts"], tool: "SvelteKit"),
        Rule(folder: ".dart_tool", markers: ["pubspec.yaml"], tool: "Dart and Flutter"),
        Rule(folder: "DerivedData", markers: [], tool: "Xcode"),
    ]

    /// Folders never searched inside: hidden ones, Library, and what tools fill.
    static let skipped: Set<String> = Set(rules.map(\.folder)).union(["Library", "Pods", "vendor", "venv", ".venv", "Carthage"])

    /// The rule a folder matches, given the names beside it. DerivedData counts only next to an Xcode project.
    public static func rule(for folder: String, siblings: Set<String>) -> Rule? {
        guard let rule = rules.first(where: { $0.folder == folder }) else { return nil }
        if rule.folder == "DerivedData" {
            return siblings.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") } ? rule : nil
        }
        return rule.markers.contains(where: siblings.contains) ? rule : nil
    }

    /// Every artifact under `root`. `list` gives the names in a folder, or nil when it is not one.
    public static func find(in root: String, list: (String) -> [String]?) -> [(path: String, project: String, rule: Rule)] {
        var found: [(String, String, Rule)] = []
        func walk(_ folder: String, depth: Int) {
            guard depth <= maxDepth, let names = list(folder) else { return }
            let siblings = Set(names)
            for name in names.sorted() {
                let path = (folder as NSString).appendingPathComponent(name)
                if let rule = rule(for: name, siblings: siblings) {
                    if list(path) != nil { found.append((path, folder, rule)) }
                    continue
                }
                if name.hasPrefix(".") || skipped.contains(name) { continue }
                walk(path, depth: depth + 1)
            }
        }
        walk(root, depth: 0)
        return found
    }

    /// A row for an artifact. Suggested unless its project changed in the last week.
    public static func item(path: String, project: String, rule: Rule, bytes: Int64, projectChanged: Date,
                            home: String = NSHomeDirectory(), now: Date = .now) -> ReviewItem {
        let recent = now.timeIntervalSince(projectChanged) < quietPeriod
        let group = project.hasPrefix(home + "/") ? "~" + project.dropFirst(home.count) : project
        return ReviewItem(path: path, group: group, name: rule.folder,
                          detail: String(format: L("%@ makes it again on the next build."), rule.tool),
                          bytes: bytes, modified: projectChanged, suggested: !recent,
                          note: recent ? L("This project changed in the last week. Your next build would be slower.") : nil)
    }
}
