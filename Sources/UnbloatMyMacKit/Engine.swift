import Foundation
import Synchronization

/// What the engine remembers between launches, in journal.json: the value of
/// every setting before the app changed it, so undo restores it exactly.
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
}

public struct EngineState: Sendable {
    public var statuses: [String: TweakStatus]
    public var history: [HistoryEntry]
    /// Tweaks the app turned on and can undo.
    public var applied: Set<String>
    public var launchItemsDisabledByApp: Set<String>
}

public struct ApplyReport: Sendable {
    /// Tweak id -> what went wrong, in words for people.
    public var failures: [String: String] = [:]
    /// A profile is waiting for approval in System Settings.
    public var profileHandedOff = false
    public var restarted: Set<Restart> = []
    public var needsLogout = false
    public var changed = 0

    public init() {}
}

/// Applies and undoes tweaks through a `SystemBackend`, keeping the journal.
/// One operation at a time; call it off the main thread, since admin prompts block.
public final class Engine: Sendable {
    public let backend: any SystemBackend
    public let tweaks: [Tweak]
    private let journalURL: URL
    private let journal: Mutex<Journal>

    public init(backend: any SystemBackend, journalURL: URL, tweaks: [Tweak] = Catalog.tweaks) {
        self.backend = backend
        self.tweaks = tweaks
        self.journalURL = journalURL
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let saved = (try? Data(contentsOf: journalURL)).flatMap { try? decoder.decode(Journal.self, from: $0) }
        journal = Mutex(saved ?? Journal())
    }

    // MARK: Reading the Mac

    public func state() -> EngineState {
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
        return EngineState(statuses: statuses, history: j.history.reversed(), applied: j.applied,
                           launchItemsDisabledByApp: Set(j.launchItems.keys))
    }

    func status(of tweak: Tweak, known: Set<String>, disabled: Set<String>,
                managed: Set<String>, pending: Set<String>) -> TweakStatus {
        let labels = tweak.agents
        if !labels.isEmpty, labels.allSatisfy({ !known.contains($0) && !disabled.contains($0) }) {
            return .unavailable("Not on this version of macOS")
        }
        var done: [Bool] = []
        var waiting = false
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
            }
        }
        if done.allSatisfy({ $0 }) { return waiting ? .waiting : .on }
        return done.contains(true) ? .partial : .off
    }

    // MARK: Changing the Mac

    /// Turns tweaks on (true) or off (false). Off restores what was there before.
    public func apply(_ changes: [String: Bool], restartApps: Bool = true) -> ApplyReport {
        var report = ApplyReport()
        var j = journal.withLock { $0 }
        let disabledBefore = backend.disabledAgents()
        let known = backend.knownAgents()
        var userScripts: [(tweak: Tweak, script: String)] = []
        var adminScripts: [(tweak: Tweak, script: String)] = []
        var restrictionsOn: Set<String> = []
        var restrictionsOff: Set<String> = []
        var profileTweaks: [Tweak] = []
        var restarts: Set<Restart> = []
        let selected = tweaks.filter { changes[$0.id] != nil }

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
                        if !backend.write(key, value) { fail(tweak, Self.refused(key)) }
                    } else {
                        // Put back the value from before. If it already equaled
                        // the tweak's value, go back to the macOS default instead.
                        let original = j.prefs[key.id]?.value
                        let restore = original.map { value.matches($0) } == true ? nil : original
                        if backend.write(key, restore) { j.prefs[key.id] = nil } else { fail(tweak, Self.refused(key)) }
                    }
                case .agent(let label):
                    let exists = known.contains(label) || disabledBefore.contains(label)
                    guard exists else { continue }
                    if on {
                        if j.agents[label] == nil { j.agents[label] = disabledBefore.contains(label) }
                        if !backend.setAgent(label, disabled: true) { fail(tweak, "macOS would not stop \(label).") }
                    } else {
                        if backend.setAgent(label, disabled: false) { j.agents[label] = nil } else {
                            fail(tweak, "macOS would not start \(label) again.")
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
                        if !backend.writeFile(path, contents) { fail(tweak, "Could not write \(path).") }
                    } else {
                        let original = j.files[path]?.contents
                        if backend.writeFile(path, original == contents ? nil : original) { j.files[path] = nil } else {
                            fail(tweak, "Could not restore \(path).")
                        }
                    }
                }
            }
            restarts.formUnion(tweak.restarts)
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
        }
        report.needsLogout = restarts.contains(.logout)
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
            case .restriction, .command: false
            }
        }
    }

    // MARK: Background items and storage

    public func launchItems() -> [LaunchItem] { backend.launchItems() }

    /// Returns an error message, or nil when it worked.
    public func setLaunchItem(_ item: LaunchItem, disabled: Bool) -> String? {
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

    public func measure(_ target: CleanupTarget) -> CleanupSize { backend.measure(target) }

    public func clean(_ target: CleanupTarget) -> String? {
        var message: String?
        do { try backend.clean(target) } catch { message = error.localizedDescription }
        journal.withLock { $0.history.append(HistoryEntry(title: "Cleaned \(target.title)", turnedOn: true, error: message)) }
        save()
        return message
    }

    // MARK: Helpers

    static func refused(_ key: PrefKey) -> String {
        if key.domain == "com.apple.universalaccess" {
            return "macOS protects this setting. Give UnbloatMyMac Full Disk Access in System Settings > Privacy & Security, then try again."
        }
        return "macOS did not accept \(key)."
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
