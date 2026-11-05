import Foundation
import Synchronization

// Recommended apps and command line tools, installed with Homebrew.
// UnbloatMyMac never installs Homebrew itself; it shows how.

public enum AppGroup: String, CaseIterable, Sendable, Codable {
    case windows, terminal, tools, privacy

    public var title: String {
        switch self {
        case .windows: L("Windows Habits")
        case .terminal: L("Command Line")
        case .tools: L("Mac Utilities")
        case .privacy: L("Privacy")
        }
    }

    public var summary: String {
        switch self {
        case .windows: L("Apps that bring back what you miss from Windows.")
        case .terminal: L("A nicer prompt and faster replacements for classic commands.")
        case .tools: L("Small free apps that fill gaps in macOS.")
        case .privacy: L("See and block what apps send.")
        }
    }

    public var symbol: String {
        switch self {
        case .windows: "macwindow.on.rectangle"
        case .terminal: "terminal"
        case .tools: "wrench.and.screwdriver"
        case .privacy: "hand.raised"
        }
    }
}

public struct RecommendedApp: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable { case formula, cask }

    /// The Homebrew name, like alt-tab.
    public let id: String
    public let name: String
    public let kind: Kind
    public let group: AppGroup
    public let detail: String
    /// The app bundle a cask installs, to spot copies installed without Homebrew.
    public let bundle: String?
    /// A line for ~/.zshrc that turns the tool on in new Terminal windows.
    public let shellLine: String?
    /// Part of Install Recommended.
    public let recommended: Bool
    public let homepage: String

    public init(_ id: String, _ name: String, _ kind: Kind, _ group: AppGroup, _ detail: String,
                bundle: String? = nil, shell: String? = nil, recommended: Bool = false, homepage: String) {
        self.id = id
        self.name = name
        self.kind = kind
        self.group = group
        self.detail = L(detail)
        self.bundle = bundle
        self.shellLine = shell
        self.recommended = recommended
        self.homepage = homepage
    }
}

public enum AppInstallState: Sendable, Equatable {
    case notInstalled
    case installed
    /// The app is in Applications but Homebrew did not put it there.
    case installedElsewhere
}

public struct AppsState: Sendable {
    public var homebrew: String?
    public var states: [String: AppInstallState] = [:]
    /// Tools whose line is in ~/.zshrc.
    public var inShell: Set<String> = []
    public init(homebrew: String? = nil, states: [String: AppInstallState] = [:], inShell: Set<String> = []) {
        self.homebrew = homebrew
        self.states = states
        self.inShell = inShell
    }
}

extension Catalog {
    public static let apps: [RecommendedApp] = [
        // Windows habits
        .init("alt-tab", "AltTab", .cask, .windows,
              "Switch between windows, not just apps, with previews, like Alt-Tab on Windows.",
              bundle: "AltTab.app", recommended: true, homepage: "https://alt-tab-macos.netlify.app"),
        .init("rectangle", "Rectangle", .cask, .windows,
              "Snap windows to halves, thirds, and corners with keyboard shortcuts, like Windows-Arrow.",
              bundle: "Rectangle.app", recommended: true, homepage: "https://rectangleapp.com"),
        .init("maccy", "Maccy", .cask, .windows,
              "Clipboard history in the menu bar, like Windows-V.",
              bundle: "Maccy.app", recommended: true, homepage: "https://maccy.app"),
        .init("linearmouse", "LinearMouse", .cask, .windows,
              "A separate scroll direction for the mouse and the trackpad, and no mouse acceleration.",
              bundle: "LinearMouse.app", homepage: "https://linearmouse.app"),

        // Command line
        .init("oh-my-posh", "Oh My Posh", .formula, .terminal,
              "A prompt that shows the folder, Git branch, and how long a command took. Needs a Nerd Font.",
              shell: #"command -v oh-my-posh >/dev/null && eval "$(oh-my-posh init zsh)""#, recommended: true,
              homepage: "https://ohmyposh.dev"),
        .init("font-meslo-lg-nerd-font", "Meslo Nerd Font", .cask, .terminal,
              "The font with the icons Oh My Posh and eza draw. Choose it in Terminal > Settings > Profiles > Text.",
              recommended: true, homepage: "https://www.nerdfonts.com"),
        .init("eza", "eza", .formula, .terminal,
              "A clearer ls with colors, Git status, and folders first.",
              shell: "command -v eza >/dev/null && alias ls='eza --group-directories-first'", recommended: true,
              homepage: "https://eza.rocks"),
        .init("zoxide", "zoxide", .formula, .terminal,
              "A cd that remembers: type z and part of a folder name to jump there.",
              shell: #"command -v zoxide >/dev/null && eval "$(zoxide init zsh)""#, recommended: true,
              homepage: "https://github.com/ajeetdsouza/zoxide"),
        .init("fzf", "fzf", .formula, .terminal,
              "Fuzzy search for anything. Control-R finds a past command, Control-T a file.",
              shell: "command -v fzf >/dev/null && source <(fzf --zsh)", recommended: true,
              homepage: "https://github.com/junegunn/fzf"),
        .init("bat", "bat", .formula, .terminal,
              "A cat with syntax colors and line numbers.", homepage: "https://github.com/sharkdp/bat"),
        .init("ripgrep", "ripgrep", .formula, .terminal,
              "Searches text in files many times faster than grep. Run it as rg.",
              homepage: "https://github.com/BurntSushi/ripgrep"),
        .init("fd", "fd", .formula, .terminal,
              "A simple, fast find.", homepage: "https://github.com/sharkdp/fd"),
        .init("btop", "btop", .formula, .terminal,
              "CPU, memory, disks, and processes in the terminal, like Task Manager.",
              homepage: "https://github.com/aristocratos/btop"),
        .init("tlrc", "tldr", .formula, .terminal,
              "Short examples for a command instead of its whole manual. Run it as tldr.",
              homepage: "https://tldr.sh"),
        .init("ghostty", "Ghostty", .cask, .terminal,
              "A fast, native terminal app.", bundle: "Ghostty.app", homepage: "https://ghostty.org"),

        // Mac utilities
        .init("appcleaner", "AppCleaner", .cask, .tools,
              "Removes an app with the settings and caches it leaves behind.",
              bundle: "AppCleaner.app", recommended: true, homepage: "https://freemacsoft.net/appcleaner/"),
        .init("stats", "Stats", .cask, .tools,
              "CPU, memory, disk, network, and battery in the menu bar.",
              bundle: "Stats.app", recommended: true, homepage: "https://github.com/exelban/stats"),
        .init("jordanbaird-ice", "Ice", .cask, .tools,
              "Hides menu bar icons you don't need.", bundle: "Ice.app", homepage: "https://icemenubar.app"),
        .init("keka", "Keka", .cask, .tools,
              "Opens and makes 7z, RAR, and other archives.", bundle: "Keka.app", homepage: "https://www.keka.io"),
        .init("iina", "IINA", .cask, .tools,
              "Plays almost any video file.", bundle: "IINA.app", homepage: "https://iina.io"),
        .init("monitorcontrol", "MonitorControl", .cask, .tools,
              "Brightness and volume keys for external displays.",
              bundle: "MonitorControl.app", homepage: "https://github.com/MonitorControl/MonitorControl"),

        // Privacy
        .init("lulu", "LuLu", .cask, .privacy,
              "A free firewall that asks before an app connects to the internet for the first time.",
              bundle: "LuLu.app", recommended: true, homepage: "https://objective-see.org/products/lulu.html"),
    ]

    public static func app(_ id: String) -> RecommendedApp? { apps.first { $0.id == id } }
}

/// Homebrew and the shell file, behind a protocol so tests use a pretend one.
public protocol PackageManager: Sendable {
    /// The brew binary, or nil when Homebrew is not installed.
    func homebrew() -> String?
    /// Installed formula and cask names.
    func installed() -> Set<String>
    func bundleExists(_ name: String) -> Bool
    func install(_ app: RecommendedApp) throws
    func uninstall(_ app: RecommendedApp) throws
    func readShellFile() -> String
    func writeShellFile(_ text: String) -> Bool
}

/// The block UnbloatMyMac keeps in ~/.zshrc. Every line ends with a marker
/// naming its tool, so each one can be removed alone and nothing else is touched.
public enum ShellBlock {
    public static let begin = "# >>> UnbloatMyMac >>>"
    public static let end = "# <<< UnbloatMyMac <<<"

    static func tag(_ id: String) -> String { "  # unbloatmymac:\(id)" }

    public static func enabled(in text: String) -> Set<String> {
        Set(lines(in: text).compactMap { line in
            line.range(of: "# unbloatmymac:").map { String(line[$0.upperBound...]).trimmingCharacters(in: .whitespaces) }
        })
    }

    /// The text with the tool's line added or removed.
    public static func setting(_ app: RecommendedApp, on: Bool, in text: String) -> String {
        guard let shell = app.shellLine else { return text }
        var block = lines(in: text).filter { !$0.hasSuffix(tag(app.id)) }
        if on { block.append(shell + tag(app.id)) }
        let outside = removingBlock(text)
        if block.isEmpty { return outside }
        let body = ([begin] + block + [end]).joined(separator: "\n")
        let base = outside.isEmpty || outside.hasSuffix("\n") ? outside : outside + "\n"
        return base + (base.isEmpty ? "" : "\n") + body + "\n"
    }

    private static func lines(in text: String) -> [String] {
        guard let start = text.range(of: begin), let stop = text.range(of: end, range: start.upperBound..<text.endIndex) else { return [] }
        return text[start.upperBound..<stop.lowerBound].split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private static func removingBlock(_ text: String) -> String {
        guard let start = text.range(of: begin), let stop = text.range(of: end, range: start.upperBound..<text.endIndex) else { return text }
        var after = stop.upperBound
        if after < text.endIndex, text[after] == "\n" { after = text.index(after: after) }
        var before = String(text[..<start.lowerBound])
        // Drop the blank line the block was added after.
        if before.hasSuffix("\n\n") { before.removeLast() }
        return before + text[after...]
    }
}

/// Installs and removes recommended apps, and their shell lines.
public final class AppInstaller: Sendable {
    public let packages: PackageManager

    public init(packages: PackageManager) {
        self.packages = packages
    }

    public func state() -> AppsState {
        guard let brew = packages.homebrew() else {
            return AppsState(states: states(installed: []), inShell: ShellBlock.enabled(in: packages.readShellFile()))
        }
        return AppsState(homebrew: brew, states: states(installed: packages.installed()),
                         inShell: ShellBlock.enabled(in: packages.readShellFile()))
    }

    private func states(installed: Set<String>) -> [String: AppInstallState] {
        var result: [String: AppInstallState] = [:]
        for app in Catalog.apps {
            if installed.contains(app.id) { result[app.id] = .installed }
            else if let bundle = app.bundle, packages.bundleExists(bundle) { result[app.id] = .installedElsewhere }
            else { result[app.id] = .notInstalled }
        }
        return result
    }

    /// Installs, then adds the shell line when the tool has one and `shell` is true.
    public func install(_ app: RecommendedApp, shell: Bool = true) throws {
        guard packages.homebrew() != nil else { throw BackendError(L("Install Homebrew first.")) }
        try packages.install(app)
        if shell, app.shellLine != nil { try setShell(app, on: true) }
    }

    /// Uninstalls with Homebrew and takes the shell line out.
    public func uninstall(_ app: RecommendedApp) throws {
        if app.shellLine != nil { try setShell(app, on: false) }
        try packages.uninstall(app)
    }

    public func setShell(_ app: RecommendedApp, on: Bool) throws {
        let text = packages.readShellFile()
        let new = ShellBlock.setting(app, on: on, in: text)
        if new != text, !packages.writeShellFile(new) { throw BackendError(L("Could not change ~/.zshrc.")) }
    }
}

/// The real Homebrew.
public final class Homebrew: PackageManager {
    public init() {}

    public func homebrew() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func installed() -> Set<String> {
        guard let brew = homebrew() else { return [] }
        let formulae = brewRun(brew, ["list", "--formula", "-1"]).output
        let casks = brewRun(brew, ["list", "--cask", "-1"]).output
        return Set((formulae + "\n" + casks).split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) })
    }

    public func bundleExists(_ name: String) -> Bool {
        ["/Applications", ("~/Applications" as NSString).expandingTildeInPath]
            .contains { FileManager.default.fileExists(atPath: "\($0)/\(name)") }
    }

    public func install(_ app: RecommendedApp) throws {
        try perform(["install"] + (app.kind == .cask ? ["--cask"] : []) + [app.id])
    }

    public func uninstall(_ app: RecommendedApp) throws {
        try perform(["uninstall"] + (app.kind == .cask ? ["--cask"] : []) + [app.id])
    }

    private func perform(_ arguments: [String]) throws {
        guard let brew = homebrew() else { throw BackendError(L("Install Homebrew first.")) }
        let result = brewRun(brew, arguments)
        guard result.status == 0 else {
            let lines = result.output.split(separator: "\n").filter { $0.contains("Error") || $0.contains("error") }
            throw BackendError(lines.last.map(String.init) ?? L("Homebrew could not finish."))
        }
    }

    /// ~/.zshrc, following a symlink so a dotfiles link stays a link.
    private var shellURL: URL {
        URL(fileURLWithPath: ("~/.zshrc" as NSString).expandingTildeInPath).resolvingSymlinksInPath()
    }

    public func readShellFile() -> String { (try? String(contentsOf: shellURL, encoding: .utf8)) ?? "" }

    public func writeShellFile(_ text: String) -> Bool {
        (try? text.write(to: shellURL, atomically: true, encoding: .utf8)) != nil
    }

    private func brewRun(_ brew: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        let bin = (brew as NSString).deletingLastPathComponent
        env["PATH"] = "\(bin):/usr/bin:/bin:/usr/sbin:/sbin"
        env["NONINTERACTIVE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return (1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

/// A pretend Homebrew for tests, snapshots, and the self-test.
public final class MockPackageManager: PackageManager {
    struct State {
        var hasBrew = true
        var installed: Set<String> = []
        var bundles: Set<String> = []
        var shell = "export PATH=\"$HOME/bin:$PATH\"\n"
        var failing: Set<String> = []
    }

    private let state = Mutex(State())

    public init(seeded: Bool = false, homebrew: Bool = true) {
        state.withLock { s in
            s.hasBrew = homebrew
            if seeded {
                s.installed = ["rectangle", "bat"]
                s.bundles = ["IINA.app"]
            }
        }
    }

    public func homebrew() -> String? { state.withLock { $0.hasBrew ? "/opt/homebrew/bin/brew" : nil } }
    public func installed() -> Set<String> { state.withLock { $0.installed } }
    public func bundleExists(_ name: String) -> Bool { state.withLock { $0.bundles.contains(name) } }

    public func install(_ app: RecommendedApp) throws {
        try state.withLock { s in
            if s.failing.contains(app.id) { throw BackendError("Error: \(app.id): download failed") }
            s.installed.insert(app.id)
        }
    }

    public func uninstall(_ app: RecommendedApp) throws {
        _ = state.withLock { $0.installed.remove(app.id) }
    }

    public func readShellFile() -> String { state.withLock { $0.shell } }
    public func writeShellFile(_ text: String) -> Bool { state.withLock { $0.shell = text }; return true }

    /// Test hook: the next install of this id fails.
    public func fail(_ id: String) { _ = state.withLock { $0.failing.insert(id) } }
}
