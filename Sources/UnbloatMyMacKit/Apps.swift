import Foundation
import Synchronization

// Recommended apps and command line tools, installed with Homebrew.
// UnbloatMyMac never installs Homebrew itself; it shows how.

public enum AppGroup: String, CaseIterable, Sendable, Codable {
    case allInOne, updates, cleaners, windows, terminal, tools, ai, privacy

    public var title: String {
        switch self {
        case .allInOne: L("All in One")
        case .updates: L("App Updates")
        case .cleaners: L("Cleaners")
        case .windows: L("Windows Habits")
        case .terminal: L("Command Line")
        case .tools: L("Mac Utilities")
        case .ai: L("Local AI")
        case .privacy: L("Privacy")
        }
    }

    public var summary: String {
        switch self {
        case .allInOne: L("One menu bar app instead of many small ones.")
        case .cleaners: L("Find what fills your disk and remove apps with everything they leave behind. Storage here clears caches; these go further.")
        case .updates: L("See which apps are out of date and update them in one place. macOS updates only App Store apps by itself.")
        case .windows: L("Apps that bring back what you miss from Windows.")
        case .terminal: L("A nicer prompt and faster replacements for classic commands.")
        case .tools: L("Small free apps that fill gaps in macOS.")
        case .ai: L("AI that runs on your Mac, offline, with nothing sent to a server. Each model is a download of several gigabytes.")
        case .privacy: L("See and block what apps send.")
        }
    }

    public var symbol: String {
        switch self {
        case .allInOne: "square.grid.2x2"
        case .updates: "arrow.triangle.2.circlepath"
        case .cleaners: "trash"
        case .windows: "macwindow.on.rectangle"
        case .terminal: "terminal"
        case .tools: "wrench.and.screwdriver"
        case .ai: "cpu"
        case .privacy: "hand.raised"
        }
    }
}

public struct RecommendedApp: Identifiable, Sendable, Hashable {
    /// A Homebrew formula or cask, or an app that is only a download from its website.
    public enum Kind: String, Sendable { case formula, cask, download }

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
    /// Starred in the list, unless an all-in-one app covers it on this Mac.
    public let recommended: Bool
    public let homepage: String
    /// An all-in-one app that does the same job, like vorssaint.
    public let replacedBy: String?
    /// Runs only on Apple silicon.
    public let appleSiliconOnly: Bool

    /// Part of Install Recommended on this Mac.
    public func isRecommended(appleSilicon: Bool = RecommendedApp.isAppleSilicon) -> Bool {
        if appleSiliconOnly && !appleSilicon { return false }
        if let replacedBy, appleSilicon, Catalog.app(replacedBy)?.appleSiliconOnly == true { return false }
        return recommended
    }

    /// Homebrew can install it. A download opens its website instead.
    public var installsWithHomebrew: Bool { kind != .download }

    /// The Homebrew command that installs it, or nil for a download.
    public var brewCommand: String? {
        installsWithHomebrew ? "brew install \(kind == .cask ? "--cask " : "")\(id)" : nil
    }

    /// False for an Apple silicon app on an Intel Mac. Such apps are not listed.
    public var runsHere: Bool { !appleSiliconOnly || Self.isAppleSilicon }

    public static var isAppleSilicon: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    public init(_ id: String, _ name: String, _ kind: Kind, _ group: AppGroup, _ detail: String,
                bundle: String? = nil, shell: String? = nil, recommended: Bool = false, homepage: String,
                replacedBy: String? = nil, appleSiliconOnly: Bool = false) {
        self.id = id
        self.name = name
        self.kind = kind
        self.group = group
        self.detail = L(detail)
        self.bundle = bundle
        self.shellLine = shell
        self.recommended = recommended
        self.homepage = homepage
        self.replacedBy = replacedBy
        self.appleSiliconOnly = appleSiliconOnly
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
        // All in one
        .init("vorssaint", "Vorssaint", .cask, .allInOne,
              "One menu bar app for a window switcher with previews, snapping, clipboard history, mouse and scroll settings, a system monitor, display brightness, a per-app volume mixer, and an uninstaller.",
              bundle: "Vorssaint.app", recommended: true, homepage: "https://github.com/vorssaint/vorssaint-utils",
              appleSiliconOnly: true),

        // App updates
        .init("maccurrent", "macCurrent", .download, .updates,
              "Finds updates for App Store, Homebrew, Sparkle, and directly downloaded apps, checks each one before it installs, and backs up the old version. Free while in beta.",
              bundle: "macCurrent.app", recommended: true, homepage: "https://maccurrent.com"),
        .init("updatest", "Updatest", .cask, .updates,
              "Lists updates for App Store, Homebrew, Sparkle, and Electron apps, and installs them in one click.",
              bundle: "Updatest.app", homepage: "https://updatest.app"),
        .init("latest", "Latest", .cask, .updates,
              "A small open-source window that shows which App Store and Sparkle apps have updates.",
              bundle: "Latest.app", homepage: "https://max.codes/latest"),
        .init("applite", "Applite", .cask, .updates,
              "Install, update, and remove Homebrew apps in a window instead of Terminal.",
              bundle: "Applite.app", homepage: "https://applite.app"),
        .init("topgrade", "topgrade", .formula, .updates,
              "Updates everything with one command: Homebrew, App Store apps, npm, pip, Rust, and more.",
              homepage: "https://github.com/topgrade-rs/topgrade"),
        .init("mas", "mas", .formula, .updates,
              "Lists and updates App Store apps from the command line.",
              homepage: "https://github.com/mas-cli/mas"),

        // Cleaners
        .init("mole", "Mole", .formula, .cleaners,
              "Cleans caches, logs, and leftovers, removes apps completely, and shows what fills your disk, all from one command: mo.",
              recommended: true, homepage: "https://mole.fit"),
        .init("appcleaner", "AppCleaner", .cask, .cleaners,
              "Removes an app with the settings and caches it leaves behind.",
              bundle: "AppCleaner.app", recommended: true, homepage: "https://freemacsoft.net/appcleaner/", replacedBy: "vorssaint"),
        .init("pearcleaner", "Pearcleaner", .cask, .cleaners,
              "An open-source uninstaller that also finds files left behind by apps you already deleted.",
              bundle: "Pearcleaner.app", homepage: "https://itsalin.com/appInfo/?id=pearcleaner", replacedBy: "vorssaint"),
        .init("peel", "Peel", .cask, .cleaners,
              "An open-source uninstaller that shows why each leftover file belongs to its app, finds what builds left in your projects, and can put back what it moved.",
              bundle: "Peel.app", homepage: "https://github.com/TuguiDragos/Peel"),
        .init("onyx", "OnyX", .cask, .cleaners,
              "Runs macOS maintenance scripts, rebuilds caches and indexes, and shows hidden settings.",
              bundle: "OnyX.app", homepage: "https://www.titanium-software.fr/en/onyx.html"),
        .init("grandperspective", "GrandPerspective", .cask, .cleaners,
              "Draws your disk as a map of blocks, one per file, so the big ones stand out.",
              bundle: "GrandPerspective.app", homepage: "https://grandperspectiv.sourceforge.net"),
        .init("omnidisksweeper", "OmniDiskSweeper", .cask, .cleaners,
              "Lists folders from largest to smallest, so you can delete what you no longer need.",
              bundle: "OmniDiskSweeper.app", homepage: "https://www.omnigroup.com/more"),
        .init("czkawka", "Czkawka", .formula, .cleaners,
              "Finds duplicate files, similar photos, big files, and empty folders.",
              homepage: "https://github.com/qarmin/czkawka"),
        .init("dust", "dust", .formula, .cleaners,
              "Shows which folders take the most space, as a tree in the terminal.",
              homepage: "https://github.com/bootandy/dust"),

        // Windows habits
        .init("alt-tab", "AltTab", .cask, .windows,
              "Switch between windows, not just apps, with previews, like Alt-Tab on Windows.",
              bundle: "AltTab.app", recommended: true, homepage: "https://alt-tab-macos.netlify.app", replacedBy: "vorssaint"),
        .init("rectangle", "Rectangle", .cask, .windows,
              "Snap windows to halves, thirds, and corners with keyboard shortcuts, like Windows-Arrow.",
              bundle: "Rectangle.app", recommended: true, homepage: "https://rectangleapp.com", replacedBy: "vorssaint"),
        .init("maccy", "Maccy", .cask, .windows,
              "Clipboard history in the menu bar, like Windows-V.",
              bundle: "Maccy.app", recommended: true, homepage: "https://maccy.app", replacedBy: "vorssaint"),
        .init("linearmouse", "LinearMouse", .cask, .windows,
              "A separate scroll direction for the mouse and the trackpad, and no mouse acceleration.",
              bundle: "LinearMouse.app", homepage: "https://linearmouse.app", replacedBy: "vorssaint"),

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
        .init("stats", "Stats", .cask, .tools,
              "CPU, memory, disk, network, and battery in the menu bar.",
              bundle: "Stats.app", recommended: true, homepage: "https://github.com/exelban/stats", replacedBy: "vorssaint"),
        .init("jordanbaird-ice", "Ice", .cask, .tools,
              "Hides menu bar icons you don't need.", bundle: "Ice.app", homepage: "https://icemenubar.app"),
        .init("keka", "Keka", .cask, .tools,
              "Opens and makes 7z, RAR, and other archives.", bundle: "Keka.app", homepage: "https://www.keka.io"),
        .init("iina", "IINA", .cask, .tools,
              "Plays almost any video file.", bundle: "IINA.app", homepage: "https://iina.io"),
        .init("monitorcontrol", "MonitorControl", .cask, .tools,
              "Brightness and volume keys for external displays.",
              bundle: "MonitorControl.app", homepage: "https://github.com/MonitorControl/MonitorControl", replacedBy: "vorssaint"),

        // Local AI
        .init("ollama-app", "Ollama", .cask, .ai,
              "Runs open models like Llama, Gemma, Qwen, and Mistral with one command, and serves them to other apps.",
              bundle: "Ollama.app", homepage: "https://ollama.com"),
        .init("lm-studio", "LM Studio", .cask, .ai,
              "Find, download, and chat with local models in a window. Uses MLX on Apple silicon.",
              bundle: "LM Studio.app", homepage: "https://lmstudio.ai", appleSiliconOnly: true),
        .init("omlx", "oMLX", .formula, .ai,
              "A fast model server built on Apple's MLX, with an OpenAI-compatible API for other apps.",
              homepage: "https://github.com/jundot/omlx", appleSiliconOnly: true),
        .init("osaurus", "Osaurus", .cask, .ai,
              "A small menu bar model server built on MLX, with chat and an OpenAI-compatible API.",
              bundle: "Osaurus.app", homepage: "https://osaurus.ai", appleSiliconOnly: true),
        .init("jan", "Jan", .cask, .ai,
              "An open-source, offline alternative to ChatGPT.", bundle: "Jan.app", homepage: "https://jan.ai"),
        .init("anythingllm", "AnythingLLM", .cask, .ai,
              "Chat with your own documents and notes using a local model.",
              bundle: "AnythingLLM.app", homepage: "https://anythingllm.com"),
        .init("draw-things", "Draw Things", .cask, .ai,
              "Makes and edits images with Stable Diffusion and Flux models, fast on Apple silicon.",
              bundle: "Draw Things.app", homepage: "https://drawthings.ai"),
        .init("comfy", "ComfyUI", .cask, .ai,
              "Builds image, video, and audio pipelines from nodes. The most flexible image generator.",
              bundle: "Comfy Desktop.app", homepage: "https://comfy.org", appleSiliconOnly: true),
        .init("diffusionbee", "DiffusionBee", .cask, .ai,
              "The simplest way to make images from text, with no settings to learn.",
              bundle: "DiffusionBee.app", homepage: "https://diffusionbee.com"),
        .init("voiceink", "VoiceInk", .cask, .ai,
              "Open-source dictation into any app, transcribed on your Mac with Whisper.",
              bundle: "VoiceInk.app", homepage: "https://tryvoiceink.com"),
        .init("macwhisper", "MacWhisper", .cask, .ai,
              "Transcribes recordings, meetings, and videos on your Mac. Free, with paid extras.",
              bundle: "MacWhisper.app", homepage: "https://goodsnooze.gumroad.com/l/macwhisper"),
        .init("llama.cpp", "llama.cpp", .formula, .ai,
              "The engine behind many local AI apps, as command line tools and a server.",
              homepage: "https://github.com/ggml-org/llama.cpp"),
        .init("mlx-lm", "MLX LM", .formula, .ai,
              "Apple's tools to run and fine-tune models with MLX from the command line.",
              homepage: "https://github.com/ml-explore/mlx-lm", appleSiliconOnly: true),
        .init("whisper.cpp", "whisper.cpp", .formula, .ai,
              "Speech to text from the command line, with Whisper models.",
              homepage: "https://github.com/ggml-org/whisper.cpp"),

        // Privacy
        .init("lulu", "LuLu", .cask, .privacy,
              "A free firewall that asks before an app connects to the internet for the first time.",
              bundle: "LuLu.app", recommended: true, homepage: "https://objective-see.org/products/lulu.html"),
    ]

    public static func app(_ id: String) -> RecommendedApp? { apps.first { $0.id == id } }

    /// The apps this Mac can run.
    public static var appsHere: [RecommendedApp] { apps.filter(\.runsHere) }
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
    /// Installed formula and cask names with a newer version. `fetch` updates Homebrew's index first (slow, online).
    func outdated(fetch: Bool) -> Set<String>
    func upgrade(_ app: RecommendedApp) throws
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
    public let log: ActivityLog?

    public init(packages: PackageManager, log: ActivityLog? = nil) {
        self.packages = packages
        self.log = log
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
        guard app.installsWithHomebrew else { throw BackendError(L("This app is not in Homebrew. Download it from its website.")) }
        guard packages.homebrew() != nil else { throw BackendError(L("Install Homebrew first.")) }
        let command = "brew install \(app.kind == .cask ? "--cask " : "")\(app.id)"
        do {
            try packages.install(app)
            log?.add(.info, .apps, "Installed \(app.name)", detail: command)
        } catch {
            log?.add(.error, .apps, "Could not install \(app.name)", detail: command + "\n" + error.localizedDescription)
            throw error
        }
        if shell, app.shellLine != nil { try setShell(app, on: true) }
    }

    /// Catalog apps Homebrew installed that have a newer version. Casks that update themselves are left out by Homebrew.
    public func outdated(fetch: Bool = false) -> Set<String> {
        guard packages.homebrew() != nil else { return [] }
        let ids = Set(Catalog.apps.filter(\.installsWithHomebrew).map(\.id))
        let found = packages.outdated(fetch: fetch).intersection(ids)
        log?.add(.debug, .apps, "Found \(found.count) app updates", detail: found.sorted().joined(separator: "\n"))
        return found
    }

    public func upgrade(_ app: RecommendedApp) throws {
        guard app.installsWithHomebrew else { throw BackendError(L("This app is not in Homebrew. Download it from its website.")) }
        let command = "brew upgrade \(app.kind == .cask ? "--cask " : "")\(app.id)"
        do {
            try packages.upgrade(app)
            log?.add(.info, .apps, "Updated \(app.name)", detail: command)
        } catch {
            log?.add(.error, .apps, "Could not update \(app.name)", detail: command + "\n" + error.localizedDescription)
            throw error
        }
    }

    /// Uninstalls with Homebrew and takes the shell line out.
    public func uninstall(_ app: RecommendedApp) throws {
        guard app.installsWithHomebrew else { throw BackendError(L("Homebrew did not install this app. Move it to the Trash to remove it.")) }
        if app.shellLine != nil { try setShell(app, on: false) }
        let command = "brew uninstall \(app.kind == .cask ? "--cask " : "")\(app.id)"
        do {
            try packages.uninstall(app)
            log?.add(.info, .apps, "Uninstalled \(app.name)", detail: command)
        } catch {
            log?.add(.error, .apps, "Could not uninstall \(app.name)", detail: command + "\n" + error.localizedDescription)
            throw error
        }
    }

    public func setShell(_ app: RecommendedApp, on: Bool) throws {
        let text = packages.readShellFile()
        let new = ShellBlock.setting(app, on: on, in: text)
        guard new != text else { return }
        guard packages.writeShellFile(new) else {
            log?.add(.error, .apps, "Could not change ~/.zshrc for \(app.name)")
            throw BackendError(L("Could not change ~/.zshrc."))
        }
        log?.add(.info, .apps, on ? "Added \(app.name) to ~/.zshrc" : "Removed \(app.name) from ~/.zshrc", detail: app.shellLine)
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

    public func outdated(fetch: Bool) -> Set<String> {
        guard let brew = homebrew() else { return [] }
        if fetch { _ = brewRun(brew, ["update", "--quiet"]) }
        let output = brewRun(brew, ["outdated", "--quiet"]).output
        return Set(output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    public func upgrade(_ app: RecommendedApp) throws {
        try perform(["upgrade"] + (app.kind == .cask ? ["--cask"] : []) + [app.id])
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
        var outdated: Set<String> = []
    }

    private let state = Mutex(State())

    public init(seeded: Bool = false, homebrew: Bool = true) {
        state.withLock { s in
            s.hasBrew = homebrew
            if seeded {
                s.installed = ["rectangle", "bat"]
                s.outdated = ["bat"]
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
        state.withLock { s in s.installed.remove(app.id); s.outdated.remove(app.id) }
    }

    public func outdated(fetch: Bool) -> Set<String> { state.withLock { $0.outdated.intersection($0.installed) } }

    public func upgrade(_ app: RecommendedApp) throws {
        try state.withLock { s in
            if s.failing.contains(app.id) { throw BackendError("Error: \(app.id): download failed") }
            s.outdated.remove(app.id)
        }
    }

    /// Test hook: a newer version of this id is out.
    public func markOutdated(_ id: String) { _ = state.withLock { $0.outdated.insert(id) } }

    public func readShellFile() -> String { state.withLock { $0.shell } }
    public func writeShellFile(_ text: String) -> Bool { state.withLock { $0.shell = text }; return true }

    /// Test hook: the next install of this id fails.
    public func fail(_ id: String) { _ = state.withLock { $0.failing.insert(id) } }
}
