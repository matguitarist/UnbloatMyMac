import AppKit
import CoreServices
import Foundation

/// The real Mac: CFPreferences, launchctl, configuration profiles, and the Trash.
public final class MacBackend: SystemBackend {
    private let uid = getuid()
    private let supportFolder: URL

    public init(supportFolder: URL) {
        self.supportFolder = supportFolder
    }

    // MARK: Preferences

    private func app(_ domain: String) -> CFString {
        domain == "NSGlobalDomain" ? kCFPreferencesAnyApplication : domain as CFString
    }

    private func host(_ key: PrefKey) -> CFString {
        key.currentHost ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost
    }

    public func read(_ key: PrefKey) -> PrefValue? {
        CFPreferencesSynchronize(app(key.domain), kCFPreferencesCurrentUser, host(key))
        guard let raw = CFPreferencesCopyValue(key.key as CFString, app(key.domain), kCFPreferencesCurrentUser, host(key)) else {
            return nil
        }
        if CFGetTypeID(raw) == CFBooleanGetTypeID() { return .bool(CFBooleanGetValue((raw as! CFBoolean))) }
        if let number = raw as? NSNumber {
            return CFNumberIsFloatType(number) ? .double(number.doubleValue) : .int(number.intValue)
        }
        if let string = raw as? String { return .string(string) }
        return nil
    }

    public func write(_ key: PrefKey, _ value: PrefValue?) -> Bool {
        let raw: CFPropertyList? = switch value {
        case .bool(let v): v as CFBoolean
        case .int(let v): v as NSNumber
        case .double(let v): v as NSNumber
        case .string(let v): v as CFString
        case nil: nil
        }
        CFPreferencesSetValue(key.key as CFString, raw, app(key.domain), kCFPreferencesCurrentUser, host(key))
        guard CFPreferencesSynchronize(app(key.domain), kCFPreferencesCurrentUser, host(key)) else { return false }
        // Read it back: protected domains accept the write and keep the old value.
        let now = read(key)
        if let value { return value.matches(now) }
        return now == nil
    }

    // MARK: Launch agents

    public func knownAgents() -> Set<String> {
        var labels: Set<String> = []
        let printed = shell("launchctl print gui/\(uid)").output
        var inServices = false
        for line in printed.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("\tservices = {") { inServices = true; continue }
            if inServices {
                if line.hasPrefix("\t}") { break }
                if let label = line.split(whereSeparator: \.isWhitespace).last { labels.insert(String(label)) }
            }
        }
        let system = "/System/Library/LaunchAgents"
        for file in (try? FileManager.default.contentsOfDirectory(atPath: system)) ?? [] where file.hasSuffix(".plist") {
            labels.insert(String(file.dropLast(6)))
        }
        return labels
    }

    public func disabledAgents() -> Set<String> { disabled(in: "gui/\(uid)") }

    private func disabled(in domain: String) -> Set<String> {
        var labels: Set<String> = []
        for line in shell("launchctl print-disabled \(domain)").output.split(separator: "\n") {
            let parts = line.components(separatedBy: "\" => ")
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let state = parts[1].trimmingCharacters(in: .whitespaces)
            if state == "disabled" || state == "true" { labels.insert(label) }
        }
        return labels
    }

    public func setAgent(_ label: String, disabled: Bool) -> Bool {
        let target = "gui/\(uid)/\(label)"
        if disabled {
            guard shell("launchctl disable \(target)").status == 0 else { return false }
            _ = shell("launchctl bootout \(target)")
            return true
        }
        guard shell("launchctl enable \(target)").status == 0 else { return false }
        let plist = "/System/Library/LaunchAgents/\(label).plist"
        if FileManager.default.fileExists(atPath: plist) { _ = shell("launchctl bootstrap gui/\(uid) '\(plist)'") }
        return true
    }

    // MARK: Profile

    public func managedRestrictions() -> Set<String> {
        let paths = ["/Library/Managed Preferences/com.apple.applicationaccess.plist",
                     "/Library/Managed Preferences/\(NSUserName())/com.apple.applicationaccess.plist"]
        var keys: Set<String> = []
        for path in paths {
            guard let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else { continue }
            for (key, value) in dict where (value as? Bool) == false { keys.insert(key) }
        }
        return keys
    }

    public func installProfile(_ restrictions: Set<String>) throws {
        if restrictions.isEmpty {
            try run(["profiles remove -identifier \(Catalog.profileIdentifier)"], admin: true)
            return
        }
        try FileManager.default.createDirectory(at: supportFolder, withIntermediateDirectories: true)
        let file = supportFolder.appending(path: "UnbloatMyMac Apple Intelligence.mobileconfig")
        try Profile.data(restrictions: restrictions).write(to: file, options: .atomic)
        // macOS adds the profile to System Settings > Device Management, where the person approves it.
        _ = shell("open '\(file.path)'")
        _ = shell("open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension'")
    }

    // MARK: Commands and files

    public func check(_ script: String) -> Bool { shell(script).status == 0 }

    public func osBuild() -> String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public func loginItems() throws -> [LoginItem] {
        let output = try runAdmin("sfltool dumpbtm")
        return LoginItemParser.parse(output, uid: Int(uid))
    }

    /// Runs one script as root under the password prompt and returns what it printed.
    private func runAdmin(_ script: String) throws -> String {
        let result = execute("/usr/bin/osascript", ["-e", "on run argv", "-e",
                                                   "do shell script (item 1 of argv) with administrator privileges",
                                                   "-e", "end run", script])
        if result.status != 0 {
            if result.output.contains("-128") { throw BackendError(L("You canceled the password prompt, so nothing that needs it changed.")) }
            throw BackendError(result.output.isEmpty ? L("The admin command failed.") : result.output)
        }
        return result.output
    }

    public func run(_ scripts: [String], admin: Bool) throws {
        guard !scripts.isEmpty else { return }
        if !admin {
            for script in scripts {
                let result = shell(script)
                if result.status != 0 { throw BackendError(result.output.isEmpty ? L("The command failed.") : result.output) }
            }
            return
        }
        // One prompt for every admin change. The script travels as an argument, so nothing needs escaping.
        _ = try runAdmin(scripts.joined(separator: " && "))
    }

    private func expand(_ path: String) -> String { (path as NSString).expandingTildeInPath }

    public func readFile(_ path: String) -> String? { try? String(contentsOfFile: expand(path), encoding: .utf8) }

    public func writeFile(_ path: String, _ contents: String?) -> Bool {
        let full = expand(path)
        guard let contents else {
            if !FileManager.default.fileExists(atPath: full) { return true }
            return (try? FileManager.default.removeItem(atPath: full)) != nil
        }
        try? FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        return (try? contents.write(toFile: full, atomically: true, encoding: .utf8)) != nil
    }

    public func restart(_ processes: Set<Restart>) {
        for process in processes where process != .logout {
            _ = execute("/usr/bin/killall", [process.rawValue])
        }
    }

    // MARK: Background items

    public func launchItems() -> [LaunchItem] {
        let home = NSHomeDirectory()
        let folders: [(String, LaunchItem.Scope)] = [
            ("\(home)/Library/LaunchAgents", .userAgent),
            ("/Library/LaunchAgents", .globalAgent),
            ("/Library/LaunchDaemons", .daemon),
        ]
        let userDisabled = disabledAgents()
        let systemDisabled = disabled(in: "system")
        let running = runningLabels()
        var items: [LaunchItem] = []
        for (folder, scope) in folders {
            for file in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] where file.hasSuffix(".plist") {
                let path = "\(folder)/\(file)"
                guard let plist = NSDictionary(contentsOfFile: path) as? [String: Any] else { continue }
                let label = plist["Label"] as? String ?? String(file.dropLast(6))
                if label.hasPrefix("com.apple.") { continue }
                let program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first ?? ""
                let off = (scope == .daemon ? systemDisabled : userDisabled).contains(label) || (plist["Disabled"] as? Bool ?? false)
                items.append(LaunchItem(label: label, path: path.replacingOccurrences(of: home, with: "~"),
                                        program: program.replacingOccurrences(of: home, with: "~"), scope: scope,
                                        isDisabled: off, isRunning: running.contains(label)))
            }
        }
        return items.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private func runningLabels() -> Set<String> {
        var labels: Set<String> = []
        for line in shell("launchctl list").output.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: "\t")
            if parts.count == 3, parts[0] != "-" { labels.insert(String(parts[2])) }
        }
        return labels
    }

    public func setLaunchItem(_ item: LaunchItem, disabled: Bool) throws {
        let path = expand(item.path)
        if item.scope == .daemon {
            let script = disabled
                ? "launchctl disable system/\(item.label); launchctl bootout system/\(item.label) 2>/dev/null; true"
                : "launchctl enable system/\(item.label) && (launchctl bootstrap system '\(path)' 2>/dev/null; true)"
            try run([script], admin: true)
            return
        }
        let target = "gui/\(uid)/\(item.label)"
        if disabled {
            let result = shell("launchctl disable \(target)")
            if result.status != 0 { throw BackendError(result.output) }
            _ = shell("launchctl bootout \(target)")
        } else {
            let result = shell("launchctl enable \(target)")
            if result.status != 0 { throw BackendError(result.output) }
            _ = shell("launchctl bootstrap gui/\(uid) '\(path)'")
        }
    }

    // MARK: Storage

    public func measure(_ target: CleanupTarget) -> CleanupSize {
        if case .command(let count, _, _) = target.kind {
            let number = shell(count).output.split(separator: "\n").last.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 0
            return CleanupSize(bytes: nil, items: number)
        }
        if target.kind == .leftovers {
            let found = leftovers()
            return CleanupSize(bytes: found.reduce(0) { $0 + $1.bytes }, items: found.count)
        }
        if target.kind == .deviceSupport { return DeviceSupportFinder.size(of: deviceSupport()) }
        if target.listsReviewItems { return ReviewItem.size(of: reviewItems(target)) }
        let urls = items(of: target)
        return CleanupSize(bytes: urls.reduce(0) { $0 + size(of: $1) }, items: urls.count)
    }

    public func clean(_ target: CleanupTarget) throws {
        switch target.kind {
        case .command(_, let script, let admin):
            try run([script], admin: admin)
        case .leftovers, .deviceSupport, .installers, .buildArtifacts:
            throw BackendError(L("Review leftovers one by one."))
        default:
            // Caches of open apps stay: moving them under a running app breaks it or frees nothing.
            let open = runningApps()
            try trash(items(of: target).filter { OpenApp.owner(of: ownerName(of: $0, in: target), among: open) == nil })
        }
    }

    // MARK: Open apps

    public func openApps(holding target: CleanupTarget) -> [OpenApp] {
        let open = runningApps()
        guard !open.isEmpty else { return [] }
        var found: [OpenApp] = []
        for url in items(of: target) {
            if let app = OpenApp.owner(of: ownerName(of: url, in: target), among: open), !found.contains(app) { found.append(app) }
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func quit(_ apps: [OpenApp]) -> [OpenApp] {
        let running = apps.compactMap { NSRunningApplication(processIdentifier: $0.pid) }
        for app in running { app.terminate() }
        // Apps may ask to save documents first; wait up to ten seconds.
        for _ in 0..<40 where running.contains(where: { !$0.isTerminated }) { Thread.sleep(forTimeInterval: 0.25) }
        let open = Set(running.filter { !$0.isTerminated }.map(\.processIdentifier))
        return apps.filter { open.contains($0.pid) }
    }

    /// Regular apps that are open now, with every name their cache folders may use.
    private func runningApps() -> [OpenApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy != .prohibited, let id = app.bundleIdentifier,
                  app.processIdentifier != getpid() else { return nil }
            let bundle = app.bundleURL.flatMap(Bundle.init(url:))
            let other = [bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
                         app.executableURL?.lastPathComponent].compactMap { $0 }
            return OpenApp(name: app.localizedName ?? id, bundleID: id, pid: app.processIdentifier, otherNames: other)
        }
    }

    /// The folder name that says which app an item belongs to: the app folder for web app caches, the item itself otherwise.
    private func ownerName(of url: URL, in target: CleanupTarget) -> String {
        if case .chromiumCaches = target.kind { return url.deletingLastPathComponent().lastPathComponent }
        return url.lastPathComponent
    }

    /// What a folder target moves to the Trash, without the items it keeps.
    private func items(of target: CleanupTarget) -> [URL] {
        allItems(of: target).filter { !target.keeps($0.lastPathComponent) }
    }

    private func allItems(of target: CleanupTarget) -> [URL] {
        switch target.kind {
        case .contents(let folders): folders.flatMap { children(of: expand($0)) }
        case .matching(let folder, let prefixes):
            children(of: expand(folder)).filter { url in prefixes.contains { url.lastPathComponent.hasPrefix($0) } }
        case .chromiumCaches(let folder):
            ChromiumCaches.paths(in: expand(folder)) { path in
                (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            }.map { URL(fileURLWithPath: $0) }
        case .command, .leftovers, .deviceSupport, .installers, .buildArtifacts: []
        }
    }

    /// Every move to the Trash goes through here. Each item is checked once more right before it moves:
    /// gone already is fine, and a protected place stays, on its own path and where its links lead.
    private func trash(_ urls: [URL]) throws {
        var failed: [String] = []
        var refused: [String] = []
        for url in urls {
            guard (try? url.checkResourceIsReachable()) == true || FileManager.default.fileExists(atPath: url.path) else { continue }
            let resolved = url.deletingLastPathComponent().resolvingSymlinksInPath().appending(path: url.lastPathComponent)
            if ProtectedPaths.reason(for: url.path) != nil || ProtectedPaths.reason(for: resolved.path) != nil {
                refused.append(url.lastPathComponent)
                continue
            }
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch { failed.append(url.lastPathComponent) }
        }
        if !refused.isEmpty {
            throw BackendError(String(format: L("%@ is protected, so it stayed where it was."), refused.prefix(5).joined(separator: ", ")))
        }
        if !failed.isEmpty {
            throw BackendError(String(format: L("%lld of %lld items are in use or protected and stayed where they were."), failed.count, urls.count)
                               + " " + failed.prefix(5).joined(separator: ", ") + (failed.count > 5 ? "…" : ""))
        }
    }

    // MARK: Xcode device support

    public func deviceSupport() -> [DeviceSupportVersion] {
        DeviceSupportFinder.folders.flatMap { folder in
            children(of: expand(folder)).compactMap { url -> DeviceSupportVersion? in
                guard let parsed = DeviceSupportFinder.parse(url.lastPathComponent) else { return nil }
                let (bytes, modified) = sizeAndNewest(of: url)
                return DeviceSupportVersion(path: url.path, platform: DeviceSupportFinder.platform(ofFolder: folder),
                                            device: parsed.device, version: parsed.version, build: parsed.build,
                                            bytes: bytes, modified: modified)
            }
        }
    }

    public func trash(deviceSupport versions: [DeviceSupportVersion]) throws {
        // Only versions directly inside Xcode's DeviceSupport folders.
        let allowed = DeviceSupportFinder.folders.map { expand($0) + "/" }
        let urls = versions.map { URL(fileURLWithPath: expand($0.path)).standardizedFileURL }
        guard urls.allSatisfy({ url in allowed.contains { url.path.hasPrefix($0) && !url.path.dropFirst($0.count).contains("/") } }) else {
            throw BackendError(L("Only folders in Xcode’s DeviceSupport folders can be moved to the Trash."))
        }
        try trash(urls)
    }

    // MARK: Installers and build artifacts

    public func reviewItems(_ target: CleanupTarget) -> [ReviewItem] {
        switch target.kind {
        case .installers:
            let mounted = InstallerFinder.mounted(fromHdiutil: execute("/usr/bin/hdiutil", ["info"]).output)
            return InstallerFinder.folders.flatMap { folder in
                installerCandidates(in: expand(folder)).compactMap { installer($0, folder: folder, mounted: mounted) }
            }.sorted { $0.bytes > $1.bytes }
        case .buildArtifacts:
            return BuildArtifactFinder.roots.map(expand).filter(isDirectory).flatMap { root in
                BuildArtifactFinder.find(in: root, list: listFolder).flatMap { found -> [ReviewItem] in
                    let changed = lastChange(ofProject: found.project)
                    guard found.rule.folder == "target" else {
                        return [BuildArtifactFinder.item(path: found.path, project: found.project, rule: found.rule,
                                                         bytes: size(of: URL(fileURLWithPath: found.path)), projectChanged: changed)]
                    }
                    // Rust: each build folder and incremental cache too, measured once; the whole folder is their sum.
                    let parts = BuildArtifactFinder.cargoParts(in: found.path, list: listFolder).map { part -> ReviewItem in
                        let (bytes, newest) = sizeAndNewest(of: URL(fileURLWithPath: part.path))
                        return BuildArtifactFinder.cargoItem(path: part.path, part: part.part, project: found.project,
                                                             bytes: bytes, lastBuilt: newest)
                    }
                    let builds = parts.filter { !$0.path.hasSuffix("/incremental") }
                    let whole = BuildArtifactFinder.item(path: found.path, project: found.project, rule: found.rule,
                                                         bytes: builds.reduce(0) { $0 + $1.bytes }, projectChanged: changed)
                    return [whole] + parts
                }
            }.sorted { ($0.group, -$0.bytes) < ($1.group, -$1.bytes) }
        default:
            return []
        }
    }

    public func trash(_ items: [ReviewItem], from target: CleanupTarget) throws {
        // Each item must still be what it was listed as: an installer that is not open, or a folder with its tool's file beside it.
        let mounted = InstallerFinder.mounted(fromHdiutil: execute("/usr/bin/hdiutil", ["info"]).output)
        let roots = BuildArtifactFinder.roots.map { expand($0) + "/" }
        let urls = ReviewItem.outermost(items).map { URL(fileURLWithPath: expand($0.path)).standardizedFileURL }
        let valid = urls.allSatisfy { url in
            let parent = url.deletingLastPathComponent().path
            switch target.kind {
            case .installers:
                return InstallerFinder.folders.contains { parent == expand($0) || url.deletingLastPathComponent().deletingLastPathComponent().path == expand($0) }
                    && installer(url, folder: "", mounted: mounted) != nil
            case .buildArtifacts:
                return roots.contains { url.path.hasPrefix($0) }
                    && (BuildArtifactFinder.rule(for: url.lastPathComponent, siblings: Set(listFolder(parent) ?? [])) != nil
                        || BuildArtifactFinder.cargoTarget(of: url.path, list: listFolder) != nil)
            default:
                return false
            }
        }
        guard valid else { throw BackendError(L("Some items changed since they were listed. Scan again, then review them.")) }
        try trash(urls)
    }

    /// Files in an installer folder and in the folders directly inside it, not inside apps or bundles.
    private func installerCandidates(in folder: String) -> [URL] {
        children(of: folder).flatMap { url -> [URL] in
            let name = url.lastPathComponent
            if name.hasPrefix(".") { return [] }
            if isDirectory(url.path), !["app", "pkg", "mpkg"].contains(url.pathExtension.lowercased()) {
                return children(of: url.path).filter { !$0.lastPathComponent.hasPrefix(".") }
            }
            return [url]
        }
    }

    private func installer(_ url: URL, folder: String, mounted: Set<String>) -> ReviewItem? {
        let (bytes, modified) = sizeAndNewest(of: url)
        let downloaded = hasAttribute(url, "com.apple.metadata:kMDItemWhereFroms") || hasAttribute(url, "com.apple.quarantine")
        return InstallerFinder.item(path: url.path, folder: folder, bytes: bytes, modified: modified,
                                    downloaded: downloaded, mounted: mounted)
    }

    private func hasAttribute(_ url: URL, _ name: String) -> Bool {
        getxattr(url.path, name, nil, 0, 0, 0) >= 0
    }

    private func isDirectory(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }

    /// The names in a real folder (not a link), or nil.
    private func listFolder(_ path: String) -> [String]? {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else { return nil }
        return try? FileManager.default.contentsOfDirectory(atPath: path)
    }

    /// The last change to a project's own files, leaving out what builds wrote. Git's index counts too.
    private func lastChange(ofProject project: String) -> Date {
        let built = Set(BuildArtifactFinder.rules.map(\.folder))
        var newest = Date.distantPast
        for url in children(of: project) where !built.contains(url.lastPathComponent) {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            newest = max(newest, date)
        }
        for git in [".git/index", ".git/HEAD"] {
            let date = (try? URL(fileURLWithPath: project + "/" + git).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            newest = max(newest, date ?? .distantPast)
        }
        return newest
    }

    // MARK: Leftovers

    public func leftovers() -> [Leftover] {
        let installed = LeftoverFinder.Installed(bundleIDs: installedBundleIDs())
        let library = NSHomeDirectory() + "/Library/"
        var found: [Leftover] = []
        for folder in LeftoverFinder.folders {
            for url in children(of: library + folder) {
                // Cheap checks first: most items belong to an installed app.
                guard let id = LeftoverFinder.bundleID(fromName: url.lastPathComponent), !installed.hasApp(for: id),
                      !Self.isRegistered(id) else { continue }
                let (bytes, modified) = sizeAndNewest(of: url)
                if let leftover = LeftoverFinder.leftover(path: url.path, installed: installed, registered: Self.isRegistered,
                                                          bytes: bytes, modified: modified) {
                    found.append(leftover)
                }
            }
        }
        return found.sorted { $0.bytes > $1.bytes }
    }

    public func trash(_ leftovers: [Leftover]) throws {
        // Only paths in the Library folders the finder looks at, never anything else.
        let library = NSHomeDirectory() + "/Library/"
        let allowed = LeftoverFinder.folders.map { library + $0 + "/" }
        let urls = leftovers.map { URL(fileURLWithPath: expand($0.path)).standardizedFileURL }
        guard urls.allSatisfy({ url in allowed.contains { url.path.hasPrefix($0) && !url.path.dropFirst($0.count).contains("/") } }) else {
            throw BackendError(L("Only leftovers in your Library folder can be moved to the Trash."))
        }
        try trash(urls)
    }

    /// Bundle ids of the apps in the Applications folders, two levels deep.
    private func installedBundleIDs() -> [String] {
        let home = NSHomeDirectory()
        var ids: [String] = []
        func scan(_ folder: String, depth: Int) {
            for url in children(of: folder) {
                if url.pathExtension == "app" {
                    if let id = Bundle(url: url)?.bundleIdentifier { ids.append(id) }
                } else if depth > 0, (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    scan(url.path, depth: depth - 1)
                }
            }
        }
        for folder in ["/Applications", home + "/Applications", "/System/Applications", "/Library/Application Support"] {
            scan(folder, depth: 2)
        }
        return ids
    }

    /// LaunchServices knows an app with this id, wherever it is.
    private static func isRegistered(_ id: String) -> Bool {
        guard let urls = LSCopyApplicationURLsForBundleIdentifier(id as CFString, nil)?.takeRetainedValue() as? [URL] else { return false }
        return !urls.isEmpty
    }

    /// The space an item takes and the last time anything in it changed.
    private func sizeAndNewest(of url: URL) -> (Int64, Date) {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .contentModificationDateKey]
        func values(_ url: URL) -> (Int64, Date) {
            let v = try? url.resourceValues(forKeys: Set(keys))
            return (Int64(v?.totalFileAllocatedSize ?? 0), v?.contentModificationDate ?? .distantPast)
        }
        var (total, newest) = values(url)
        if let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [],
                                                       errorHandler: { _, _ in true }) {
            for case let file as URL in walker {
                let (bytes, date) = values(file)
                total += bytes
                newest = max(newest, date)
            }
        }
        return (total, newest)
    }

    private func children(of folder: String) -> [URL] {
        let url = URL(fileURLWithPath: folder)
        return (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
    }

    private func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                                         options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = Int64((try? url.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        for case let file as URL in walker {
            total += Int64((try? file.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: Processes

    private func shell(_ script: String) -> (status: Int32, output: String) {
        execute("/bin/sh", ["-c", script])
    }

    private func execute(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (1, error.localizedDescription) }
        // Read before waiting: a full pipe would block the process forever.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// The configuration profile that switches Apple Intelligence features off.
public enum Profile {
    public static func data(restrictions: Set<String>) throws -> Data {
        var payload: [String: Any] = [
            "PayloadType": "com.apple.applicationaccess",
            "PayloadIdentifier": "\(Catalog.profileIdentifier).restrictions",
            "PayloadUUID": "6E1F4A52-3B7C-4D2E-9A51-A1B2C3D4E5F6",
            "PayloadVersion": 1,
            "PayloadDisplayName": "Apple Intelligence Restrictions",
        ]
        for key in restrictions.sorted() { payload[key] = false }
        let profile: [String: Any] = [
            "PayloadContent": [payload],
            "PayloadDisplayName": "UnbloatMyMac: Apple Intelligence",
            "PayloadDescription": "Turns off the Apple Intelligence features you chose in UnbloatMyMac. Remove it to turn them back on.",
            "PayloadIdentifier": Catalog.profileIdentifier,
            "PayloadOrganization": "UnbloatMyMac",
            "PayloadType": "Configuration",
            "PayloadUUID": "0B8E2C6D-7F14-4A9B-8C3E-5D2A1F0E9B47",
            "PayloadVersion": 1,
            "PayloadScope": "System",
            "PayloadRemovalDisallowed": false,
        ]
        return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
    }
}

public extension Catalog {
    static let cleanup: [CleanupTarget] = [
        // Apps and System
        CleanupTarget(id: "caches", title: "App Caches", detail: "Files apps keep to load faster. They rebuild them as needed.",
                      symbol: "archivebox", kind: .contents(["~/Library/Caches"]),
                      // macOS protects Apple's caches and recreates them at once.
                      keeps: ["com.apple.", "CloudKit", "familycircled"]),
        CleanupTarget(id: "chromiumCaches", title: "Web App Caches",
                      detail: "Caches that Slack, Discord, VS Code, and other apps built on Chrome keep in Application Support. They rebuild them.",
                      symbol: "globe", kind: .chromiumCaches("~/Library/Application Support")),
        CleanupTarget(id: "logs", title: "Logs", detail: "Diagnostic logs written by apps.",
                      symbol: "doc.text", kind: .contents(["~/Library/Logs"])),
        CleanupTarget(id: "savedState", title: "Saved Window States",
                      detail: "What apps saved to reopen their windows where you left them. Apps open with fresh windows next time.",
                      symbol: "macwindow.on.rectangle", kind: .contents(["~/Library/Saved Application State"])),
        CleanupTarget(id: "leftovers", title: "Leftovers from Deleted Apps",
                      detail: "Settings and data of apps that are no longer installed and that nothing touched in 30 days. Review them one by one.",
                      symbol: "shippingbox", kind: .leftovers),
        CleanupTarget(id: "installers", title: "macOS Installers", detail: "Install macOS apps left in Applications.",
                      symbol: "arrow.down.app", kind: .matching(folder: "/Applications", prefixes: ["Install macOS"])),
        CleanupTarget(id: "oldInstallers", title: "Old Installers",
                      detail: "Disk images and installer packages over 20 MB left in Downloads or on the Desktop after you installed the app. Ones you made yourself are listed but not picked.",
                      symbol: "externaldrive.badge.minus", kind: .installers),
        CleanupTarget(id: "iosUpdates", title: "iPhone and iPad Updates", detail: "Software update files Finder downloaded for your devices.",
                      symbol: "arrow.triangle.2.circlepath",
                      kind: .contents(["~/Library/iTunes/iPhone Software Updates", "~/Library/iTunes/iPad Software Updates"])),
        CleanupTarget(id: "aiModels", title: "Apple Intelligence Models",
                      detail: "Language, image, and photo models in /System/Library/AssetsV2. System Integrity Protection keeps any app from deleting them; turning off Apple Intelligence in System Settings makes macOS remove them.",
                      symbol: "apple.intelligence",
                      kind: .contents(Catalog.modelFolders), settingsPane: "com.apple.Siri-Settings.extension"),
        CleanupTarget(id: "snapshots", title: "Time Machine Local Snapshots", detail: "Hourly snapshots kept on this disk. Deleted at once; your backups are not touched.",
                      symbol: "clock.arrow.circlepath",
                      kind: .command(count: "tmutil listlocalsnapshots / 2>/dev/null | grep -c com.apple; true",
                                     run: "tmutil deletelocalsnapshots /", admin: true)),
        // Developer Files
        CleanupTarget(id: "derivedData", title: "Xcode Derived Data", detail: "Build products and indexes. Xcode rebuilds them.",
                      symbol: "hammer", kind: .contents(["~/Library/Developer/Xcode/DerivedData"]), group: .developer),
        CleanupTarget(id: "deviceSupport", title: "Xcode Device Support",
                      detail: "Debug symbols Xcode copies from each iPhone, iPad, and Watch version you connect. The newest for each device stays unless you pick it.",
                      symbol: "iphone", kind: .deviceSupport, group: .developer),
        CleanupTarget(id: "buildArtifacts", title: "Project Build Files",
                      detail: "node_modules, target, .build, and other folders builds leave in your projects in Developer, Projects, Code, or src. Projects you changed in the last week are listed but not picked.",
                      symbol: "folder.badge.gearshape", kind: .buildArtifacts, group: .developer),
        CleanupTarget(id: "simulatorCaches", title: "Simulator Caches", detail: "Caches the iOS Simulator rebuilds when it starts.",
                      symbol: "ipad.and.iphone", kind: .contents(["~/Library/Developer/CoreSimulator/Caches"]), group: .developer),
        CleanupTarget(id: "simulators", title: "Unavailable Simulators", detail: "Simulators for runtimes that are no longer installed. Deleted at once.",
                      symbol: "xmark.rectangle.portrait",
                      kind: .command(count: "[ -x /usr/bin/xcrun ] && xcode-select -p >/dev/null 2>&1 && xcrun simctl list devices unavailable 2>/dev/null | grep -c '(unavailable'; true",
                                     run: "xcrun simctl delete unavailable", admin: false), group: .developer),
        CleanupTarget(id: "devCaches", title: "Package Manager Caches",
                      detail: "Downloads that npm, Bun, pnpm, Yarn, uv, pip, Cargo, Go, Gradle, NuGet, and pre-commit keep outside Library. They download them again when a project needs them. Homebrew’s and CocoaPods’ are in App Caches.",
                      symbol: "shippingbox.and.arrow.backward",
                      kind: .contents(Catalog.packageCaches), group: .developer),
        // Privacy Traces
        CleanupTarget(id: "downloadHistory", title: "Download History",
                      detail: "macOS keeps a record of every file you downloaded, with the website it came from. Cleared at once; the files you downloaded stay.",
                      symbol: "arrow.down.circle",
                      kind: .command(count: "sqlite3 \"$HOME/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2\" 'SELECT COUNT(*) FROM LSQuarantineEvent' 2>/dev/null; true",
                                     run: "sqlite3 \"$HOME/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2\" 'DELETE FROM LSQuarantineEvent; VACUUM;'",
                                     admin: false), group: .privacy),
        CleanupTarget(id: "recentItems", title: "Recent Items",
                      detail: "The lists behind Apple menu > Recent Items and each app’s Open Recent menu. Favorites in the Finder sidebar stay. Open apps may keep their list until you log out.",
                      symbol: "clock", kind: .matching(folder: "~/Library/Application Support/com.apple.sharedfilelist",
                                                      prefixes: ["com.apple.LSSharedFileList.Recent",
                                                                 "com.apple.LSSharedFileList.ApplicationRecentDocuments"]),
                      group: .privacy),
    ]

    /// Caches package managers keep in your home folder, outside ~/Library/Caches.
    static let packageCaches = ["~/.npm/_cacache", "~/.bun/install/cache", "~/Library/pnpm/store",
                                "~/.cargo/registry/cache", "~/go/pkg/mod/cache/download", "~/.gradle/caches",
                                "~/.yarn/berry/cache", "~/.cache/uv", "~/.cache/pip", "~/.nuget/packages", "~/.cache/pre-commit"]
}

public extension Catalog {
    /// Where macOS keeps Apple Intelligence models. Protected by SIP: measured, never deleted.
    static let modelFolders: [String] = [
        "com_apple_MobileAsset_UAF_FM_GenerativeModels", "com_apple_MobileAsset_UAF_FM_Visual",
        "com_apple_MobileAsset_UAF_FM_CodeLM", "com_apple_MobileAsset_UAF_FM_Overrides",
        "com_apple_MobileAsset_UAF_Photos_MagicCleanup", "com_apple_MobileAsset_UAF_Photos_SpatialPhotosRelive",
        "com_apple_MobileAsset_UAF_Handwriting_Synthesis", "com_apple_MobileAsset_UAF_IF_Planner",
        "com_apple_MobileAsset_UAF_Shortcuts_Generator", "com_apple_MobileAsset_UAF_Siri_AnswerSynthesis",
    ].map { "/System/Library/AssetsV2/" + $0 }
}

/// Reads the output of `sfltool dumpbtm`.
public enum LoginItemParser {
    public static func parse(_ text: String, uid: Int) -> [LoginItem] {
        var items: [LoginItem] = []
        var inUser = false
        var fields: [String: String] = [:]

        func flush() {
            defer { fields = [:] }
            guard inUser, let name = fields["Name"], let type = fields["Type"] else { return }
            let kind = type.components(separatedBy: " (").first ?? type
            // Developer records group items; they are not items themselves.
            guard kind != "developer", kind != "unknown" else { return }
            let disposition = fields["Disposition"] ?? ""
            items.append(LoginItem(name: name, developer: fields["Developer Name"] ?? "", kind: kind,
                                   isEnabled: disposition.contains("enabled") && !disposition.contains("disabled"),
                                   url: fields["URL"] ?? "", identifier: fields["Identifier"] ?? name))
        }

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Records for UID") {
                flush()
                let number = line.dropFirst("Records for UID".count).trimmingCharacters(in: .whitespaces)
                    .split(separator: " ").first.flatMap { Int($0) }
                inUser = number == uid
                continue
            }
            if line.hasPrefix("#"), line.hasSuffix(":") { flush(); continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if fields[key] == nil { fields[key] = value }
        }
        flush()
        // The same app can be listed once per parent; keep one row each.
        var seen: Set<String> = []
        return items.filter { seen.insert($0.id).inserted }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
