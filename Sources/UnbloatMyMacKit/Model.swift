import Foundation

/// A value stored with `defaults` (CFPreferences).
public enum PrefValue: Codable, Hashable, Sendable, CustomStringConvertible,
    ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByStringLiteral {
    case bool(Bool), int(Int), double(Double), string(String)

    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(stringLiteral value: String) { self = .string(value) }

    public var description: String {
        switch self {
        case .bool(let v): v ? "true" : "false"
        case .int(let v): String(v)
        case .double(let v): String(v)
        case .string(let v): "\"\(v)\""
        }
    }

    /// Bools and numbers compare loosely: macOS stores some bools as 0 and 1.
    public func matches(_ other: PrefValue?) -> Bool {
        guard let other else { return false }
        switch (self, other) {
        case (.bool(let a), .int(let b)), (.int(let b), .bool(let a)): return (b != 0) == a
        case (.double(let a), .int(let b)), (.int(let b), .double(let a)): return abs(a - Double(b)) < 0.0001
        case (.double(let a), .double(let b)): return abs(a - b) < 0.0001
        default: return self == other
        }
    }
}

/// One `defaults` key. `domain` is a bundle id or "NSGlobalDomain".
public struct PrefKey: Codable, Hashable, Sendable, CustomStringConvertible {
    public var domain: String
    public var key: String
    public var currentHost: Bool

    public init(_ domain: String, _ key: String, currentHost: Bool = false) {
        self.domain = domain
        self.key = key
        self.currentHost = currentHost
    }

    public var id: String { "\(domain)|\(key)|\(currentHost ? "host" : "any")" }
    public var description: String { "\(currentHost ? "-currentHost " : "")\(domain) \(key)" }
}

/// A shell command with its undo. `check` exits 0 while the change is in place.
public struct Command: Hashable, Sendable {
    public var apply: String
    public var revert: String
    public var check: String
    public var admin: Bool

    public init(apply: String, revert: String, check: String, admin: Bool) {
        self.apply = apply
        self.revert = revert
        self.check = check
        self.admin = admin
    }
}

/// One change a tweak makes. A tweak is on when all its actions are in place.
public enum Action: Hashable, Sendable {
    /// Writes a `defaults` value; undo restores the value from before.
    case pref(PrefKey, PrefValue)
    /// Disables a launch agent in the user's session (launchctl disable gui/<uid>/<label>).
    case agent(String)
    /// Sets a restriction to false in the app's configuration profile.
    case restriction(String)
    /// Runs a command; undo runs its revert command.
    case command(Command)
    /// Writes a file (path may start with ~); undo restores the file from before.
    case file(path: String, contents: String)
    /// Adds key bindings (key -> selector) to ~/Library/KeyBindings/DefaultKeyBinding.dict.
    /// Bindings from every applied tweak share the file; the original comes back when none is left.
    case keyBindings([String: String])

    /// What the action does, as the command to run it or a short technical line. English, like the Activity Log.
    public var applyLine: String {
        switch self {
        case .pref(let key, let value):
            "defaults \(key.currentHost ? "-currentHost " : "")write \(key.domain) \(key.key) \(Self.typed(value))"
        case .agent(let label): "launchctl disable gui/$UID/\(label)"
        case .restriction(let key): "Configuration profile restriction: \(key) = false"
        case .command(let command): command.admin ? "sudo sh -c '\(command.apply)'" : command.apply
        case .file(let path, _): "Write \(path)"
        case .keyBindings(let bindings):
            "Key bindings in ~/Library/KeyBindings/DefaultKeyBinding.dict: "
                + bindings.sorted { $0.key < $1.key }.map { "\($0.key) → \($0.value)" }.joined(separator: ", ")
        }
    }

    /// How undo puts it back.
    public var undoLine: String {
        switch self {
        case .pref(let key, _): "defaults \(key.currentHost ? "-currentHost " : "")write \(key.domain) \(key.key) <value from before> (or delete)"
        case .agent(let label): "launchctl enable gui/$UID/\(label)"
        case .restriction: "Remove the restriction from the profile (the profile goes when it is empty)"
        case .command(let command): command.admin ? "sudo sh -c '\(command.revert)'" : command.revert
        case .file(let path, _): "Restore \(path) from before"
        case .keyBindings: "Restore DefaultKeyBinding.dict from before when no key binding tweak is left"
        }
    }

    static func typed(_ value: PrefValue) -> String {
        switch value {
        case .bool(let b): "-bool \(b)"
        case .int(let i): "-int \(i)"
        case .double(let d): "-float \(d)"
        case .string(let s): "-string \"\(s)\""
        }
    }

    public static func set(_ domain: String, _ key: String, _ value: PrefValue, currentHost: Bool = false) -> Action {
        .pref(PrefKey(domain, key, currentHost: currentHost), value)
    }
}

public enum TweakCategory: String, CaseIterable, Codable, Sendable {
    case intelligence, privacy, performance, interface, finder, dock, typing, windows

    public var title: String { L(englishTitle) }

    var englishTitle: String {
        switch self {
        case .intelligence: "Apple Intelligence"
        case .privacy: "Privacy"
        case .performance: "Performance"
        case .interface: "Annoyances"
        case .finder: "Finder"
        case .dock: "Dock & Windows"
        case .typing: "Typing"
        case .windows: "Windows Mode"
        }
    }

    public var symbol: String {
        switch self {
        case .intelligence: "apple.intelligence"
        case .privacy: "hand.raised"
        case .performance: "gauge.with.dots.needle.67percent"
        case .interface: "bell.slash"
        case .finder: "folder"
        case .dock: "dock.rectangle"
        case .typing: "keyboard"
        case .windows: "pc"
        }
    }

    public var summary: String { L(englishSummary) }

    var englishSummary: String {
        switch self {
        case .intelligence: "Turn off Writing Tools, Genmoji, Image Playground, ChatGPT, summaries, Siri, and the background services behind them."
        case .privacy: "Stop analytics, personalized ads, and the services that send usage data to Apple."
        case .performance: "Make windows, the Dock, and Finder feel instant, and stop heavy background analysis."
        case .interface: "Remove pop-ups, prompts, and behaviors that get in the way."
        case .finder: "Show what is really on your disk and keep folders tidy."
        case .dock: "A quieter, faster Dock and window manager."
        case .typing: "Stop macOS from changing what you type."
        case .windows: "Make the Mac behave like a Windows PC: scrolling, function keys, Home and End, maximize, and drives on the desktop."
        }
    }
}

public enum Risk: Int, Comparable, Codable, Sendable {
    /// Cosmetic or easy to live with.
    case safe
    /// Turns off a feature some people use.
    case moderate
    /// Stops a system service. Shown only with Settings > Show advanced tweaks.
    case advanced

    public static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }
}

/// What has to restart before a change shows.
public enum Restart: String, CaseIterable, Codable, Sendable {
    case dock = "Dock"
    case finder = "Finder"
    case systemUIServer = "SystemUIServer"
    case windowManager = "WindowManager"
    /// Takes effect after logging out, or in apps opened from now on.
    case logout = "Log Out"
}

public struct Tweak: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var category: TweakCategory
    public var section: String
    public var risk: Risk
    public var restarts: [Restart]
    /// What you lose, said plainly. Shown under the detail.
    public var caveat: String?
    public var actions: [Action]

    public init(_ id: String, _ title: String, _ detail: String, in category: TweakCategory, section: String,
                risk: Risk = .safe, restarts: [Restart] = [], caveat: String? = nil, _ actions: [Action]) {
        self.id = id
        self.title = L(title)
        self.detail = L(detail)
        self.category = category
        self.section = L(section)
        self.risk = risk
        self.restarts = restarts
        self.caveat = caveat.map(L)
        self.actions = actions
    }

    public var needsAdmin: Bool {
        actions.contains { if case .command(let c) = $0 { c.admin } else { false } }
    }

    public var usesProfile: Bool {
        actions.contains { if case .restriction = $0 { true } else { false } }
    }

    public var agents: [String] {
        actions.compactMap { if case .agent(let label) = $0 { label } else { nil } }
    }
}

public struct Preset: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var symbol: String
    public var summary: String
    public var tweakIDs: [String]

    public init(id: String, title: String, symbol: String, summary: String, tweakIDs: [String]) {
        self.id = id
        self.title = L(title)
        self.symbol = symbol
        self.summary = L(summary)
        self.tweakIDs = tweakIDs
    }
}

public enum TweakStatus: Hashable, Sendable {
    case on
    case off
    /// Some of the tweak's changes are in place.
    case partial
    /// The profile was handed to macOS and waits for approval in System Settings.
    case waiting
    /// Cannot be used on this Mac, with the reason.
    case unavailable(String)

    /// The switch shows on.
    public var isOn: Bool { self == .on || self == .waiting }
    public var isAvailable: Bool { if case .unavailable = self { false } else { true } }
}

/// A third-party launch agent or daemon (Background Items).
public struct LaunchItem: Identifiable, Hashable, Sendable, Codable {
    public enum Scope: String, CaseIterable, Sendable, Codable {
        case userAgent, globalAgent, daemon

        public var title: String {
            switch self {
            case .userAgent: L("Your Agents")
            case .globalAgent: L("Agents for All Users")
            case .daemon: L("System Daemons")
            }
        }

        public var detail: String {
            switch self {
            case .userAgent: "~/Library/LaunchAgents"
            case .globalAgent: "/Library/LaunchAgents"
            case .daemon: "/Library/LaunchDaemons · " + L("needs your password")
            }
        }
    }

    public var label: String
    public var path: String
    public var program: String
    public var scope: Scope
    public var isDisabled: Bool
    public var isRunning: Bool

    public init(label: String, path: String, program: String, scope: Scope, isDisabled: Bool, isRunning: Bool) {
        self.label = label
        self.path = path
        self.program = program
        self.scope = scope
        self.isDisabled = isDisabled
        self.isRunning = isRunning
    }

    public var id: String { "\(scope.rawValue):\(label)" }

    /// The vendor, guessed from a reverse-DNS label: com.google.keystone -> google.
    public var vendor: String {
        let parts = label.split(separator: ".")
        return parts.count >= 2 ? String(parts[1]) : label
    }
}

/// Space that can be freed (Storage page).
public struct CleanupTarget: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Moves everything inside these folders to the Trash.
        case contents([String])
        /// Moves items in `folder` whose names start with `prefix` to the Trash.
        case matching(folder: String, prefix: String)
        /// Runs a command; `count` prints a number of items.
        case command(count: String, run: String, admin: Bool)
    }

    public var id: String
    public var title: String
    public var detail: String
    public var symbol: String
    public var kind: Kind
    /// Shown with an Open Settings button instead of Clean.
    public var settingsPane: String?

    public init(id: String, title: String, detail: String, symbol: String, kind: Kind, settingsPane: String? = nil) {
        self.id = id
        self.title = L(title)
        self.detail = L(detail)
        self.symbol = symbol
        self.kind = kind
        self.settingsPane = settingsPane
    }
}

public struct CleanupSize: Hashable, Sendable {
    public var bytes: Int64?
    public var items: Int

    public init(bytes: Int64?, items: Int) {
        self.bytes = bytes
        self.items = items
    }

    public var isEmpty: Bool { items == 0 && (bytes ?? 0) == 0 }
}

public struct HistoryEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var title: String
    public var turnedOn: Bool
    public var error: String?

    public init(id: UUID = UUID(), date: Date = .now, title: String, turnedOn: Bool, error: String? = nil) {
        self.id = id
        self.date = date
        self.title = title
        self.turnedOn = turnedOn
        self.error = error
    }
}

/// A login item or app background item from the Background Task Manager.
public struct LoginItem: Identifiable, Hashable, Sendable {
    public var name: String
    public var developer: String
    public var kind: String
    public var isEnabled: Bool
    public var url: String
    public var identifier: String

    public init(name: String, developer: String, kind: String, isEnabled: Bool, url: String, identifier: String) {
        self.name = name
        self.developer = developer
        self.kind = kind
        self.isEnabled = isEnabled
        self.url = url
        self.identifier = identifier
    }

    public var id: String { identifier + url }
}
