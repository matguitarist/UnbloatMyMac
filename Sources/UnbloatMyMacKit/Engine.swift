import Foundation
import Synchronization

/// What the engine remembers between launches, in journal.json: the value of
/// every setting before the app changed it, so undo restores it exactly.
/// Fields added after 0.1.0 are optional, so older journals still load.
struct Journal: Codable {
    struct Original: Codable { var value: PrefValue? }
    struct OriginalFile: Codable { var contents: String? }

    var prefs: [String: Original] = [:]
    /// Label -> whether it was already disabled before the app touched it.
    var agents: [String: Bool] = [:]
    var files: [String: OriginalFile] = [:]
    /// Background items the app disabled, by id.
    var launchItems: [String: LaunchItem] = [:]
    /// Tweaks turned on through the app.
    var applied: Set<String> = []
    /// Restrictions in a profile handed to System Settings and not approved yet.
    var pendingProfile: Set<String>?
    var history: [HistoryEntry] = []
    /// The key bindings file from before the first key binding tweak.
    var keyBindingsOriginal: OriginalFile?
    /// The macOS build the last change was applied on.
    var osBuild: String?
}

public struct EngineState: Sendable {
    public var statuses: [String: TweakStatus]
    public var history: [HistoryEntry]
    /// Tweaks the app turned on and can undo.
    public var applied: Set<String>
    public var launchItemsDisabledByApp: Set<String>
    /// Tweaks the app applied that something put back, most often a macOS update.
    public var reverted: [String]
    /// True when macOS changed build since the last apply.
    public var macOSUpdated: Bool
}

/// What the login check tells the person: tweaks something put back, most often a macOS update.
public struct RevertNotice: Equatable, Sendable {
    public var tweaks: [String]
    public var macOSUpdated: Bool
    public var osBuild: String

    public init(tweaks: [String], macOSUpdated: Bool, osBuild: String) {
        self.tweaks = tweaks
        self.macOSUpdated = macOSUpdated
        self.osBuild = osBuild
    }

    /// The same key means the person was already told.
    public var key: String { osBuild + ":" + tweaks.sorted().joined(separator: ",") }
}

public struct ApplyReport: Sendable {
    /// Tweak id -> what went wrong, in words for people.
    public var failures: [String: String] = [:]
    /// A profile is waiting for approval in System Settings.
    public var profileHandedOff = false
    /// A setting failed because the app lacks Full Disk Access.
    public var needsFullDiskAccess = false
    public var restarted: Set<Restart> = []
    public var needsLogout = false
    public var changed = 0

    public init() {}
}

/// The app's own settings in a backup. Every field is optional, so a backup
/// from an older version restores what it has and leaves the rest alone.
public struct AppPreferences: Codable, Sendable, Equatable {
    public var showAdvanced: Bool?
    public var restartApps: Bool?
    /// An accent id from Theme.all.
    public var accent: String?
    /// A localization code, or "system" to follow macOS.
    public var language: String?
    public var checksForUpdates: Bool?

    public init(showAdvanced: Bool? = nil, restartApps: Bool? = nil, accent: String? = nil,
                language: String? = nil, checksForUpdates: Bool? = nil) {
        self.showAdvanced = showAdvanced
        self.restartApps = restartApps
        self.accent = accent
        self.language = language
        self.checksForUpdates = checksForUpdates
    }
}

/// A list of tweaks saved to a file, to apply on another Mac. A settings
/// backup is the same file with the app's preferences added.
public struct TweakSet: Codable, Sendable {
    public var format = 1
    public var app = "UnbloatMyMac"
    public var created = Date.now
    public var tweaks: [String]
    public var preferences: AppPreferences?

    public init(tweaks: [String], preferences: AppPreferences? = nil) {
        self.tweaks = tweaks
        self.preferences = preferences
    }

    public func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func read(_ data: Data) throws -> TweakSet {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let set = try decoder.decode(TweakSet.self, from: data)
        guard set.app == "UnbloatMyMac" else { throw BackendError(L("This file was not made by UnbloatMyMac.")) }
        return set
    }
}

/// Applies and undoes tweaks through a `SystemBackend`, keeping the journal.
/// The journal is read again before every operation, so the app and the
/// command line tool can both change the Mac. Call it off the main thread,
/// since admin prompts block.
public final class Engine: Sendable {
    public static let keyBindingsPath = "~/Library/KeyBindings/DefaultKeyBinding.dict"

    public let backend: any SystemBackend
    public let tweaks: [Tweak]
    /// Where changes are written down for the Activity Log, when there is one.
    public let log: ActivityLog?
    private let journalURL: URL
    private let journal: Mutex<Journal>

    public init(backend: any SystemBackend, journalURL: URL, tweaks: [Tweak] = Catalog.tweaks, log: ActivityLog? = nil) {
        self.log = log
        self.backend = log.map { LoggingBackend(backend, log: $0) } ?? backend
        self.tweaks = tweaks
        self.journalURL = journalURL
        journal = Mutex(Journal())
        load()
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: journalURL),
              let saved = try? decoder.decode(Journal.self, from: data) else { return }
        journal.withLock { $0 = saved }
    }

    // MARK: Reading the Mac

    public func state() -> EngineState {
        load()
        let known = backend.knownAgents()
        let disabled = backend.disabledAgents()
        let managed = backend.managedRestrictions()
        var j = journal.withLock { $0 }
        // The person approved the profile: nothing is waiting any more.
        if let pending = j.pendingProfile, pending.isSubset(of: managed) {
            j.pendingProfile = nil
            journal.withLock { $0.pendingProfile = nil }
            save()
        }
        var statuses: [String: TweakStatus] = [:]
        for tweak in tweaks {
            statuses[tweak.id] = status(of: tweak, known: known, disabled: disabled,
                                        managed: managed, pending: j.pendingProfile ?? [])
        }
        let reverted = tweaks.filter { tweak in
            j.applied.contains(tweak.id) && (statuses[tweak.id] == .off || statuses[tweak.id] == .partial)
        }.map(\.id)
        let build = backend.osBuild()
        return EngineState(statuses: statuses, history: j.history.reversed(), applied: j.applied,
                           launchItemsDisabledByApp: Set(j.launchItems.keys), reverted: reverted,
                           macOSUpdated: j.osBuild != nil && j.osBuild != build)
    }

    func status(of tweak: Tweak, known: Set<String>, disabled: Set<String>,
                managed: Set<String>, pending: Set<String>) -> TweakStatus {
        let labels = tweak.agents
        if !labels.isEmpty, labels.allSatisfy({ !known.contains($0) && !disabled.contains($0) }) {
            return .unavailable(L("Not on this version of macOS"))
        }
        var done: [Bool] = []
        var waiting = false
        var bindingsFile: String?
        for action in tweak.actions {
            switch action {
            case .pref(let key, let value):
                done.append(value.matches(backend.read(key)))
            case .agent(let label):
                // A label missing from this macOS does not count against the tweak.
                if known.contains(label) || disabled.contains(label) { done.append(disabled.contains(label)) }
            case .restriction(let key):
                if managed.contains(key) {
                    done.append(true)
                } else if pending.contains(key) {
                    waiting = true
                    done.append(true)
                } else {
                    done.append(false)
                }
            case .command(let command):
                done.append(backend.check(command.check))
            case .file(let path, let contents):
                done.append(backend.readFile(path) == contents)
            case .keyBindings(let bindings):
                if bindingsFile == nil { bindingsFile = backend.readFile(Self.keyBindingsPath) ?? "" }
                done.append(bindings.allSatisfy { bindingsFile!.contains(KeyBindings.line($0.key, $0.value)) })
            }
        }
        if done.allSatisfy({ $0 }) { return waiting ? .waiting : .on }
        return done.contains(true) ? .partial : .off
    }

    // MARK: Changing the Mac

    /// Turns tweaks on (true) or off (false). Off restores what was there before.
    public func apply(_ changes: [String: Bool], restartApps: Bool = true) -> ApplyReport {
        load()
        var report = ApplyReport()
        var j = journal.withLock { $0 }
        let disabledBefore = backend.disabledAgents()
        let known = backend.knownAgents()
        var userScripts: [(tweak: Tweak, script: String)] = []
        var adminScripts: [(tweak: Tweak, script: String)] = []
        var restrictionsOn: Set<String> = []
        var restrictionsOff: Set<String> = []
        var profileTweaks: [Tweak] = []
        var bindingTweaks: [Tweak] = []
        var restarts: Set<Restart> = []
        let selected = tweaks.filter { changes[$0.id] != nil }
        if !selected.isEmpty {
            log?.add(.debug, .tweaks, "Applying \(selected.count) change\(selected.count == 1 ? "" : "s")",
                     detail: selected.map { "\(changes[$0.id] == true ? "on " : "off") \($0.id)" }.joined(separator: "\n"))
        }

        func fail(_ tweak: Tweak, _ message: String) {
            if report.failures[tweak.id] == nil { report.failures[tweak.id] = message }
        }

        for tweak in selected {
            let on = changes[tweak.id] ?? false
            for action in tweak.actions {
                switch action {
                case .pref(let key, let value):
                    if on {
                        if j.prefs[key.id] == nil { j.prefs[key.id] = .init(value: backend.read(key)) }
                        if !backend.write(key, value) {
                            fail(tweak, Self.refused(key))
                            if Self.isProtected(key) { report.needsFullDiskAccess = true }
                        }
                    } else {
                        // Put back the value from before. If it already equaled
                        // the tweak's value, go back to the macOS default instead.
                        let original = j.prefs[key.id]?.value
                        let restore = original.map { value.matches($0) } == true ? nil : original
                        if backend.write(key, restore) { j.prefs[key.id] = nil } else {
                            fail(tweak, Self.refused(key))
                            if Self.isProtected(key) { report.needsFullDiskAccess = true }
                        }
                    }
                case .agent(let label):
                    let exists = known.contains(label) || disabledBefore.contains(label)
                    guard exists else { continue }
                    if on {
                        if j.agents[label] == nil { j.agents[label] = disabledBefore.contains(label) }
                        if !backend.setAgent(label, disabled: true) { fail(tweak, String(format: L("macOS would not stop %@."), label)) }
                    } else {
                        if backend.setAgent(label, disabled: false) { j.agents[label] = nil } else {
                            fail(tweak, String(format: L("macOS would not start %@ again."), label))
                        }
                    }
                case .restriction(let key):
                    if on { restrictionsOn.insert(key) } else { restrictionsOff.insert(key) }
                    if !profileTweaks.contains(tweak) { profileTweaks.append(tweak) }
                case .command(let command):
                    let script = on ? command.apply : command.revert
                    if command.admin { adminScripts.append((tweak, script)) } else { userScripts.append((tweak, script)) }
                case .file(let path, let contents):
                    if on {
                        if j.files[path] == nil { j.files[path] = .init(contents: backend.readFile(path)) }
                        if !backend.writeFile(path, contents) { fail(tweak, String(format: L("Could not write %@."), path)) }
                    } else {
                        let original = j.files[path]?.contents
                        if backend.writeFile(path, original == contents ? nil : original) { j.files[path] = nil } else {
                            fail(tweak, String(format: L("Could not restore %@."), path))
                        }
                    }
                case .keyBindings:
                    if !bindingTweaks.contains(tweak) { bindingTweaks.append(tweak) }
                }
            }
            restarts.formUnion(tweak.restarts)
        }

        // Key bindings from every tweak that stays on share one file.
        if !bindingTweaks.isEmpty {
            let path = Self.keyBindingsPath
            let active = tweaks.filter { tweak in
                guard tweak.actions.contains(where: { if case .keyBindings = $0 { true } else { false } }) else { return false }
                return changes[tweak.id] ?? j.applied.contains(tweak.id)
            }
            let ok: Bool
            if active.isEmpty {
                ok = backend.writeFile(path, j.keyBindingsOriginal?.contents)
                if ok { j.keyBindingsOriginal = nil }
            } else {
                if j.keyBindingsOriginal == nil { j.keyBindingsOriginal = .init(contents: backend.readFile(path)) }
                var merged: [String: String] = [:]
                for tweak in active {
                    for case .keyBindings(let bindings) in tweak.actions { merged.merge(bindings) { a, _ in a } }
                }
                ok = backend.writeFile(path, KeyBindings.file(merged))
            }
            if !ok { for tweak in bindingTweaks { fail(tweak, String(format: L("Could not write %@."), path)) } }
        }

        for (tweak, script) in userScripts {
            do { try backend.run([script], admin: false) } catch { fail(tweak, error.localizedDescription) }
        }
        if !adminScripts.isEmpty {
            do { try backend.run(adminScripts.map(\.script), admin: true) } catch {
                for (tweak, _) in adminScripts { fail(tweak, error.localizedDescription) }
            }
        }
        if !profileTweaks.isEmpty {
            let managed = backend.managedRestrictions()
            let desired = (j.pendingProfile ?? managed).union(restrictionsOn).subtracting(restrictionsOff)
            if desired == managed {
                j.pendingProfile = nil
            } else {
                do {
                    try backend.installProfile(desired)
                    j.pendingProfile = desired.isEmpty ? nil : desired
                    report.profileHandedOff = !desired.isEmpty
                } catch {
                    for tweak in profileTweaks { fail(tweak, error.localizedDescription) }
                }
            }
        }

        for tweak in selected {
            let on = changes[tweak.id] ?? false
            let error = report.failures[tweak.id]
            if error == nil { report.changed += 1 }
            if on, error == nil { j.applied.insert(tweak.id) }
            if !on { j.applied.remove(tweak.id) }
            j.history.append(HistoryEntry(title: tweak.title, turnedOn: on, error: error))
            if let error {
                log?.add(.error, .tweaks, "\(on ? "Could not apply" : "Could not undo") \(tweak.id)", detail: error)
            } else {
                log?.add(.info, .tweaks, "\(on ? "Applied" : "Undid") \(tweak.id)", detail: tweak.title)
            }
        }
        if !selected.isEmpty { j.osBuild = backend.osBuild() }
        report.needsLogout = restarts.contains(.logout)
        if report.profileHandedOff { log?.add(.warning, .profile, "Waiting for approval in System Settings > General > Device Management") }
        if report.needsFullDiskAccess { log?.add(.warning, .settings, "Some settings need Full Disk Access for UnbloatMyMac") }
        if report.needsLogout { log?.add(.warning, .tweaks, "Some changes take effect after logging out") }
        if restartApps {
            let now = restarts.subtracting([.logout])
            backend.restart(now)
            report.restarted = now
        }
        let final = j
        journal.withLock { $0 = final }
        save()
        return report
    }

    /// Undoes every tweak the app turned on and every background item it stopped.
    public func undoEverything() -> ApplyReport {
        log?.add(.info, .tweaks, "Undo Everything")
        let current = state()
        var changes: [String: Bool] = [:]
        for tweak in tweaks where current.applied.contains(tweak.id) || (current.statuses[tweak.id]?.isOn == true && touched(tweak)) {
            changes[tweak.id] = false
        }
        var report = apply(changes)
        let items = journal.withLock { Array($0.launchItems.values) }
        for item in items {
            if let error = setLaunchItem(item, disabled: false) { report.failures[item.id] = error }
        }
        return report
    }

    private func touched(_ tweak: Tweak) -> Bool {
        let j = journal.withLock { $0 }
        return tweak.actions.contains { action in
            switch action {
            case .pref(let key, _): j.prefs[key.id] != nil
            case .agent(let label): j.agents[label] != nil
            case .file(let path, _): j.files[path] != nil
            case .keyBindings: j.keyBindingsOriginal != nil
            case .restriction, .command: false
            }
        }
    }

    /// Accepts the current state: tweaks something else put back stop counting as applied.
    public func forgetReverted() {
        let ids = state().reverted
        journal.withLock { j in for id in ids { j.applied.remove(id) } ; j.osBuild = backend.osBuild() }
        save()
    }

    /// Tweaks put back since the notice with `lastKey`, or nil when there is nothing new to say.
    public func revertNotice(lastKey: String?) -> RevertNotice? {
        let current = state()
        guard !current.reverted.isEmpty else { return nil }
        let notice = RevertNotice(tweaks: current.reverted, macOSUpdated: current.macOSUpdated, osBuild: backend.osBuild())
        return notice.key == lastKey ? nil : notice
    }

    // MARK: Export and import

    /// The tweaks that are on now, as a file. With preferences, it is a settings backup.
    public func exportSet(preferences: AppPreferences? = nil) throws -> Data {
        let current = state()
        return try TweakSet(tweaks: tweaks.filter { current.statuses[$0.id]?.isOn == true }.map(\.id),
                            preferences: preferences).data()
    }

    /// The changes that would apply a saved set: ids this app knows and that are not on yet.
    public func changes(for set: TweakSet) -> [String: Bool] {
        let current = state()
        var changes: [String: Bool] = [:]
        for id in set.tweaks {
            guard let status = current.statuses[id], status.isAvailable, !status.isOn else { continue }
            changes[id] = true
        }
        return changes
    }

    // MARK: Background items, login items, and storage

    public func launchItems() -> [LaunchItem] { backend.launchItems() }

    /// Returns an error message, or nil when it worked.
    public func setLaunchItem(_ item: LaunchItem, disabled: Bool) -> String? {
        load()
        var message: String?
        do { try backend.setLaunchItem(item, disabled: disabled) } catch { message = error.localizedDescription }
        journal.withLock { j in
            if message == nil {
                if disabled { j.launchItems[item.id] = item } else { j.launchItems[item.id] = nil }
            }
            j.history.append(HistoryEntry(title: item.label, turnedOn: disabled, error: message))
        }
        save()
        return message
    }

    public func loginItems() throws -> [LoginItem] { try backend.loginItems() }

    public func measure(_ target: CleanupTarget) -> CleanupSize { backend.measure(target) }

    /// Which security checks pass, by id.
    public func securityStatus() -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: Catalog.securityChecks.map { ($0.id, backend.check($0.check)) })
    }

    public func leftovers() -> [Leftover] { backend.leftovers() }

    /// Moves the leftovers to the Trash and notes it in History. Returns the error, if any.
    public func trash(_ leftovers: [Leftover]) -> String? {
        guard !leftovers.isEmpty else { return nil }
        load()
        var message: String?
        do { try backend.trash(leftovers) } catch { message = error.localizedDescription }
        let apps = Set(leftovers.map(\.bundleID)).count
        journal.withLock { $0.history.append(HistoryEntry(title: String(format: L("Cleaned leftovers of %lld deleted apps"), apps),
                                                          turnedOn: true, error: message)) }
        save()
        return message
    }

    public func deviceSupport() -> [DeviceSupportVersion] { backend.deviceSupport() }

    public func reviewItems(_ target: CleanupTarget) -> [ReviewItem] { backend.reviewItems(target) }

    /// Moves reviewed items to the Trash and notes it in History. Returns the error, if any.
    public func trash(_ items: [ReviewItem], from target: CleanupTarget) -> String? {
        guard !items.isEmpty else { return nil }
        load()
        var message: String?
        do { try backend.trash(items, from: target) } catch { message = error.localizedDescription }
        journal.withLock { $0.history.append(HistoryEntry(title: String(format: L("Cleaned %@"), target.title), turnedOn: true, error: message)) }
        save()
        return message
    }

    /// Moves Xcode device support versions to the Trash and notes it in History. Returns the error, if any.
    public func trash(deviceSupport versions: [DeviceSupportVersion]) -> String? {
        guard !versions.isEmpty else { return nil }
        load()
        var message: String?
        do { try backend.trash(deviceSupport: versions) } catch { message = error.localizedDescription }
        journal.withLock { $0.history.append(HistoryEntry(title: String(format: L("Cleaned %lld Xcode device support versions"), versions.count),
                                                          turnedOn: true, error: message)) }
        save()
        return message
    }

    public func openApps(holding target: CleanupTarget) -> [OpenApp] { backend.openApps(holding: target) }

    /// Cleans a target. Apps in `quitting` are asked to quit first, so their caches can go too.
    public func clean(_ target: CleanupTarget, quitting apps: [OpenApp] = []) -> String? {
        load()
        var message: String?
        let stillOpen = apps.isEmpty ? [] : backend.quit(apps)
        do { try backend.clean(target) } catch { message = error.localizedDescription }
        if !stillOpen.isEmpty {
            let names = stillOpen.map(\.name).joined(separator: ", ")
            message = [message, String(format: L("%@ did not quit, so its caches stayed."), names)].compactMap { $0 }.joined(separator: "\n")
        }
        journal.withLock { $0.history.append(HistoryEntry(title: String(format: L("Cleaned %@"), target.title), turnedOn: true, error: message)) }
        save()
        return message
    }

    // MARK: Helpers

    static func isProtected(_ key: PrefKey) -> Bool {
        ["com.apple.universalaccess", "com.apple.Safari"].contains(key.domain)
    }

    static func refused(_ key: PrefKey) -> String {
        if isProtected(key) {
            return L("macOS protects this setting. Give UnbloatMyMac Full Disk Access in System Settings > Privacy & Security, then try again.")
        }
        return String(format: L("macOS did not accept %@."), key.description)
    }

    private func save() {
        let data = journal.withLock { j in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try? encoder.encode(j)
        }
        guard let data else { return }
        try? FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: journalURL, options: .atomic)
    }
}

/// The text of ~/Library/KeyBindings/DefaultKeyBinding.dict.
public enum KeyBindings {
    static func line(_ key: String, _ selector: String) -> String { "    \"\(key)\" = \"\(selector)\";" }

    static func file(_ bindings: [String: String]) -> String {
        "{\n" + bindings.keys.sorted().map { line($0, bindings[$0]!) }.joined(separator: "\n") + "\n}\n"
    }
}

/// Localized text for the library. The app's Tweaks.strings tables hold the
/// translations; tests and the command line tool fall back to English.
public func L(_ english: String) -> String {
    Bundle.main.localizedString(forKey: english, value: english, table: "Tweaks")
}
