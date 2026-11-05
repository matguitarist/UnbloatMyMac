import Foundation
import Synchronization

/// Everything the engine does to the Mac goes through this, so tests and
/// snapshots run on `MockBackend` and never change the real system.
public protocol SystemBackend: Sendable {
    func read(_ key: PrefKey) -> PrefValue?
    /// Writes a value, or deletes the key for nil. Returns false when macOS refused it.
    func write(_ key: PrefKey, _ value: PrefValue?) -> Bool

    /// Launch agent labels that exist in the user's session.
    func knownAgents() -> Set<String>
    /// Labels disabled with launchctl disable in the user's session.
    func disabledAgents() -> Set<String>
    func setAgent(_ label: String, disabled: Bool) -> Bool

    /// Restriction keys a configuration profile has set to false.
    func managedRestrictions() -> Set<String>
    /// Hands a profile with these restrictions to macOS for approval.
    /// An empty set removes the profile (asks for the admin password).
    func installProfile(_ restrictions: Set<String>) throws

    /// Runs a check command; true on exit 0.
    func check(_ script: String) -> Bool
    /// Runs scripts in order. With `admin`, all of them run under one password prompt.
    func run(_ scripts: [String], admin: Bool) throws

    func readFile(_ path: String) -> String?
    func writeFile(_ path: String, _ contents: String?) -> Bool

    func restart(_ processes: Set<Restart>)

    func launchItems() -> [LaunchItem]
    func setLaunchItem(_ item: LaunchItem, disabled: Bool) throws

    func measure(_ target: CleanupTarget) -> CleanupSize
    func clean(_ target: CleanupTarget) throws
}

public struct BackendError: LocalizedError, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// An in-memory Mac for tests, snapshots, and the self-test.
public final class MockBackend: SystemBackend {
    struct State {
        var prefs: [String: PrefValue] = [:]
        var known: Set<String> = []
        var disabled: Set<String> = []
        var managed: Set<String> = []
        var pendingProfile: Set<String>?
        var passed: Set<String> = []
        var files: [String: String] = [:]
        var items: [LaunchItem] = []
        var sizes: [String: CleanupSize] = [:]
        var restarted: Set<Restart> = []
        var adminPrompts = 0
        var refuse: Set<String> = []
    }

    private let state = Mutex(State())

    public init(seeded: Bool = false) {
        state.withLock { s in
            s.known = Set(Catalog.tweaks.flatMap(\.agents))
            s.known.remove("com.apple.callintelligenced") // shows how a missing agent looks
            s.refuse = ["com.apple.universalaccess"]
            s.items = [
                LaunchItem(label: "com.google.keystone.agent", path: "~/Library/LaunchAgents/com.google.keystone.agent.plist",
                           program: "~/Library/Application Support/Google/GoogleUpdater/Current/GoogleUpdater.app",
                           scope: .userAgent, isDisabled: false, isRunning: true),
                LaunchItem(label: "com.spotify.webhelper", path: "~/Library/LaunchAgents/com.spotify.webhelper.plist",
                           program: "/Applications/Spotify.app/Contents/MacOS/SpotifyWebHelper",
                           scope: .userAgent, isDisabled: true, isRunning: false),
                LaunchItem(label: "com.adobe.ccxprocess", path: "/Library/LaunchAgents/com.adobe.ccxprocess.plist",
                           program: "/Applications/Utilities/Adobe Creative Cloud Experience/CCXProcess/CCXProcess.app",
                           scope: .globalAgent, isDisabled: false, isRunning: true),
                LaunchItem(label: "com.microsoft.update.agent", path: "/Library/LaunchAgents/com.microsoft.update.agent.plist",
                           program: "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app",
                           scope: .globalAgent, isDisabled: false, isRunning: false),
                LaunchItem(label: "com.docker.vmnetd", path: "/Library/LaunchDaemons/com.docker.vmnetd.plist",
                           program: "/Library/PrivilegedHelperTools/com.docker.vmnetd",
                           scope: .daemon, isDisabled: false, isRunning: true),
            ]
            s.sizes = [
                "caches": CleanupSize(bytes: 3_870_000_000, items: 214),
                "logs": CleanupSize(bytes: 182_000_000, items: 41),
                "derivedData": CleanupSize(bytes: 12_400_000_000, items: 9),
                "deviceSupport": CleanupSize(bytes: 8_100_000_000, items: 3),
                "simulators": CleanupSize(bytes: nil, items: 4),
                "installers": CleanupSize(bytes: 0, items: 0),
                "iosUpdates": CleanupSize(bytes: 6_900_000_000, items: 1),
                "snapshots": CleanupSize(bytes: nil, items: 2),
            ]
            if seeded {
                s.prefs[PrefKey("NSGlobalDomain", "AppleShowAllExtensions").id] = true
                s.prefs[PrefKey("com.apple.dock", "show-recents").id] = false
                s.prefs[PrefKey("com.apple.WindowManager", "EnableStandardClickToShowDesktop").id] = false
                s.disabled = ["com.apple.Siri.agent"]
                s.prefs[PrefKey("com.apple.assistant.support", "Assistant Enabled").id] = false
                s.prefs[PrefKey("com.apple.Siri", "StatusMenuVisible").id] = false
                s.prefs[PrefKey("com.apple.Siri", "VoiceTriggerUserEnabled").id] = false
                s.managed = ["allowGenmoji", "allowImagePlayground"]
            }
        }
    }

    // Test hooks.
    public var restarted: Set<Restart> { state.withLock { $0.restarted } }
    public var adminPrompts: Int { state.withLock { $0.adminPrompts } }
    public var pendingProfile: Set<String>? { state.withLock { $0.pendingProfile } }
    /// What System Settings does when the person approves the profile.
    public func approveProfile() {
        state.withLock { s in
            if let pending = s.pendingProfile { s.managed = pending }
            s.pendingProfile = nil
        }
    }

    public func read(_ key: PrefKey) -> PrefValue? { state.withLock { $0.prefs[key.id] } }

    public func write(_ key: PrefKey, _ value: PrefValue?) -> Bool {
        state.withLock { s in
            if s.refuse.contains(key.domain) { return false }
            s.prefs[key.id] = value
            return true
        }
    }

    public func knownAgents() -> Set<String> { state.withLock { $0.known } }
    public func disabledAgents() -> Set<String> { state.withLock { $0.disabled } }

    public func setAgent(_ label: String, disabled: Bool) -> Bool {
        state.withLock { s in
            guard s.known.contains(label) else { return false }
            if disabled { s.disabled.insert(label) } else { s.disabled.remove(label) }
            return true
        }
    }

    public func managedRestrictions() -> Set<String> { state.withLock { $0.managed } }

    public func installProfile(_ restrictions: Set<String>) throws {
        state.withLock { s in
            if restrictions.isEmpty {
                s.adminPrompts += 1
                s.managed = []
                s.pendingProfile = nil
            } else {
                s.pendingProfile = restrictions
            }
        }
    }

    public func check(_ script: String) -> Bool { state.withLock { $0.passed.contains(script) } }

    /// A command's check passes after its apply ran. The catalog's commands
    /// are matched by their apply and revert text.
    public func run(_ scripts: [String], admin: Bool) throws {
        state.withLock { s in
            if admin { s.adminPrompts += 1 }
            for script in scripts {
                for case .command(let command) in Catalog.tweaks.flatMap(\.actions) {
                    if command.apply == script { s.passed.insert(command.check) }
                    if command.revert == script { s.passed.remove(command.check) }
                }
            }
        }
    }

    public func readFile(_ path: String) -> String? { state.withLock { $0.files[path] } }

    public func writeFile(_ path: String, _ contents: String?) -> Bool {
        state.withLock { $0.files[path] = contents }
        return true
    }

    public func restart(_ processes: Set<Restart>) { state.withLock { $0.restarted.formUnion(processes) } }

    public func launchItems() -> [LaunchItem] { state.withLock { $0.items } }

    public func setLaunchItem(_ item: LaunchItem, disabled: Bool) throws {
        state.withLock { s in
            if item.scope == .daemon { s.adminPrompts += 1 }
            guard let index = s.items.firstIndex(where: { $0.id == item.id }) else { return }
            s.items[index].isDisabled = disabled
            s.items[index].isRunning = !disabled && s.items[index].isRunning
        }
    }

    public func measure(_ target: CleanupTarget) -> CleanupSize {
        state.withLock { $0.sizes[target.id] ?? CleanupSize(bytes: 0, items: 0) }
    }

    public func clean(_ target: CleanupTarget) throws {
        state.withLock { $0.sizes[target.id] = CleanupSize(bytes: 0, items: 0) }
    }
}
