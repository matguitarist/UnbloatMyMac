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

    public func run(_ scripts: [String], admin: Bool) throws {
        guard !scripts.isEmpty else { return }
        if !admin {
            for script in scripts {
                let result = shell(script)
                if result.status != 0 { throw BackendError(result.output.isEmpty ? "The command failed." : result.output) }
            }
            return
        }
        // One prompt for every admin change. The script travels as an argument, so nothing needs escaping.
        let joined = scripts.joined(separator: " && ")
        let result = execute("/usr/bin/osascript", ["-e", "on run argv", "-e",
                                                   "do shell script (item 1 of argv) with administrator privileges",
                                                   "-e", "end run", joined])
        if result.status != 0 {
            if result.output.contains("-128") { throw BackendError("You canceled the password prompt, so nothing that needs it changed.") }
            throw BackendError(result.output.isEmpty ? "The admin command failed." : result.output)
        }
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
        switch target.kind {
        case .contents(let folders):
            let urls = folders.flatMap { children(of: expand($0)) }
            return CleanupSize(bytes: urls.reduce(0) { $0 + size(of: $1) }, items: urls.count)
        case .matching(let folder, let prefix):
            let urls = children(of: expand(folder)).filter { $0.lastPathComponent.hasPrefix(prefix) }
            return CleanupSize(bytes: urls.reduce(0) { $0 + size(of: $1) }, items: urls.count)
        case .command(let count, _, _):
            let number = shell(count).output.split(separator: "\n").last.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 0
            return CleanupSize(bytes: nil, items: number)
        }
    }

    public func clean(_ target: CleanupTarget) throws {
        var urls: [URL] = []
        switch target.kind {
        case .contents(let folders): urls = folders.flatMap { children(of: expand($0)) }
        case .matching(let folder, let prefix):
            urls = children(of: expand(folder)).filter { $0.lastPathComponent.hasPrefix(prefix) }
        case .command(_, let script, let admin):
            try run([script], admin: admin)
            return
        }
        var failed = 0
        for url in urls {
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch { failed += 1 }
        }
        if failed > 0 { throw BackendError("\(failed) of \(urls.count) items are in use or protected and stayed where they were.") }
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
        CleanupTarget(id: "caches", title: "App Caches", detail: "Files apps keep to load faster. They rebuild them as needed.",
                      symbol: "archivebox", kind: .contents(["~/Library/Caches"])),
        CleanupTarget(id: "logs", title: "Logs", detail: "Diagnostic logs written by apps.",
                      symbol: "doc.text", kind: .contents(["~/Library/Logs"])),
        CleanupTarget(id: "derivedData", title: "Xcode Derived Data", detail: "Build products and indexes. Xcode rebuilds them.",
                      symbol: "hammer", kind: .contents(["~/Library/Developer/Xcode/DerivedData"])),
        CleanupTarget(id: "deviceSupport", title: "Xcode Device Support", detail: "Debug symbols for every iPhone, iPad, and Watch version you connected.",
                      symbol: "iphone", kind: .contents(["~/Library/Developer/Xcode/iOS DeviceSupport",
                                                         "~/Library/Developer/Xcode/watchOS DeviceSupport",
                                                         "~/Library/Developer/Xcode/macOS DeviceSupport"])),
        CleanupTarget(id: "simulators", title: "Unavailable Simulators", detail: "Simulators for runtimes that are no longer installed. Deleted at once.",
                      symbol: "ipad.and.iphone",
                      kind: .command(count: "[ -x /usr/bin/xcrun ] && xcode-select -p >/dev/null 2>&1 && xcrun simctl list devices unavailable 2>/dev/null | grep -c '(unavailable'; true",
                                     run: "xcrun simctl delete unavailable", admin: false)),
        CleanupTarget(id: "installers", title: "macOS Installers", detail: "Install macOS apps left in Applications.",
                      symbol: "arrow.down.app", kind: .matching(folder: "/Applications", prefix: "Install macOS")),
        CleanupTarget(id: "iosUpdates", title: "iPhone and iPad Updates", detail: "Software update files Finder downloaded for your devices.",
                      symbol: "arrow.triangle.2.circlepath",
                      kind: .contents(["~/Library/iTunes/iPhone Software Updates", "~/Library/iTunes/iPad Software Updates"])),
        CleanupTarget(id: "snapshots", title: "Time Machine Local Snapshots", detail: "Hourly snapshots kept on this disk. Deleted at once; your backups are not touched.",
                      symbol: "clock.arrow.circlepath",
                      kind: .command(count: "tmutil listlocalsnapshots / 2>/dev/null | grep -c com.apple; true",
                                     run: "tmutil deletelocalsnapshots /", admin: true)),
    ]
}
