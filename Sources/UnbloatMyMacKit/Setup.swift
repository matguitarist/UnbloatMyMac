import Foundation

/// Set Up for Me: a few questions about how the person uses their Mac, turned into
/// the tweaks to stage and the apps to offer. Nothing changes until Review.
public enum SetupQuestion: String, CaseIterable, Codable, Sendable {
    case intelligence, siri, code, windows, privacy, speed

    public var title: String {
        switch self {
        case .intelligence: L("Do you use Apple Intelligence?")
        case .siri: L("Do you talk to Siri?")
        case .code: L("Do you write code?")
        case .windows: L("Are you used to Windows?")
        case .privacy: L("How private should your Mac be?")
        case .speed: L("Do you like the animations?")
        }
    }

    public var detail: String {
        switch self {
        case .intelligence: L("Writing Tools, Genmoji, Image Playground, ChatGPT, and summaries in Mail, Notes, and Safari.")
        case .siri: L("Siri, “Hey Siri”, and the Siri icon in the menu bar.")
        case .code: L("Programming, scripts, or the Terminal.")
        case .windows: L("If you came from a Windows PC, your Mac can scroll, type, and handle windows the same way.")
        case .privacy: L("Every choice keeps your apps working. Maximum also stops analytics and turns on the firewall.")
        case .speed: L("Windows zoom, the Dock bounces, and Mission Control slides. Without them, everything shows at once.")
        }
    }

    public var symbol: String {
        switch self {
        case .intelligence: "apple.intelligence"
        case .siri: "waveform"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .windows: "pc"
        case .privacy: "hand.raised"
        case .speed: "bolt"
        }
    }

    /// The two answers, yes first.
    public var options: [SetupOption] {
        switch self {
        case .intelligence: [
            SetupOption(true, L("I Use It"), L("Apple Intelligence stays as it is.")),
            SetupOption(false, L("I Don’t"), L("Its features and summaries turn off."))]
        case .siri: [
            SetupOption(true, L("I Do"), L("Siri stays on. Your recordings still stay off Apple’s servers.")),
            SetupOption(false, L("I Don’t"), L("Siri and its menu bar icon turn off."))]
        case .code: [
            SetupOption(true, L("I Do"), L("Finder shows hidden files and full paths, quotes and dashes stay as you type them, and Terminal tools are offered.")),
            SetupOption(false, L("I Don’t"), L("Nothing changes for developers."))]
        case .windows: [
            SetupOption(true, L("I Am"), L("Windows Mode: scrolling, function keys, Home and End, maximize, and drives on the desktop.")),
            SetupOption(false, L("I’m Not"), L("Your Mac keeps working like a Mac."))]
        case .privacy: [
            SetupOption(true, L("Maximum"), L("Analytics, ad services, browser telemetry, and Game Center off, the firewall on, and LuLu to see what apps send.")),
            SetupOption(false, L("Balanced"), L("No personalized ads and nothing you type sent for suggestions."))]
        case .speed: [
            SetupOption(true, L("I Like Them"), L("Animations stay as they are.")),
            SetupOption(false, L("Make It Instant"), L("Windows, the Dock, and Finder skip their animations, and photo analysis stops running in the background."))]
        }
    }

    /// The answer picked before the person chooses: what most people want.
    public var suggested: Bool {
        switch self {
        case .intelligence, .siri, .code, .windows, .privacy: false
        case .speed: true
        }
    }
}

/// One answer to a Set Up for Me question.
public struct SetupOption: Hashable, Sendable {
    public var value: Bool
    public var title: String
    public var detail: String

    init(_ value: Bool, _ title: String, _ detail: String) {
        self.value = value
        self.title = title
        self.detail = detail
    }
}

/// The person's answers and what they lead to.
public struct SetupAnswers: Codable, Hashable, Sendable {
    public var answers: [SetupQuestion: Bool]

    public init(_ answers: [SetupQuestion: Bool] = [:]) { self.answers = answers }

    public subscript(_ question: SetupQuestion) -> Bool {
        get { answers[question] ?? question.suggested }
        set { answers[question] = newValue }
    }

    /// Tweaks to stage, in catalog order. Everyone gets the Recommended preset without
    /// Apple Intelligence; each answer adds to it, and never takes away a feature the person said they use.
    public var tweakIDs: [String] {
        var ids = Set(Catalog.preset("recommended").filter { !$0.hasPrefix("ai.") })
        if !self[.intelligence] { ids.formUnion(Self.intelligenceFeatures) }
        if !self[.siri] { ids.insert("ai.siri") }
        if self[.code] { ids.formUnion(Self.developer) }
        if self[.windows] { ids.formUnion(Catalog.preset("windows")) }
        if self[.privacy] { ids.formUnion(Catalog.preset("privacy").filter { !$0.hasPrefix("ai.") }) }
        if !self[.speed] { ids.formUnion(Catalog.preset("performance")) }
        return Catalog.tweaks.map(\.id).filter(ids.contains)
    }

    /// Apple Intelligence features the person sees. Background services stay for Advanced.
    static let intelligenceFeatures: Set<String> = Set(
        Catalog.tweaks.filter { $0.category == .intelligence && $0.risk < .advanced && $0.id != "ai.siri" }.map(\.id))

    /// What gets in a developer's way: hidden files, smart punctuation, autocorrect, slow keys.
    static let developer: Set<String> = [
        "finder.extensions", "finder.hidden", "finder.pathBar", "finder.statusBar", "finder.posixTitle",
        "finder.library", "finder.foldersFirst", "finder.extensionWarning",
        "typing.autocorrect", "typing.quotes", "typing.dashes", "typing.pressAndHold", "typing.fastRepeat",
    ]

    /// Groups of recommended apps the answers ask for.
    public var appGroups: [AppGroup] {
        var groups: [AppGroup] = []
        if self[.code] { groups.append(.terminal) }
        if self[.windows] { groups.append(.windows) }
        if self[.privacy] { groups.append(.privacy) }
        return groups
    }

    /// The recommended apps of those groups on this Mac. An app an all-in-one app covers here
    /// brings that app instead, so Windows habits on Apple silicon means Vorssaint.
    public func appIDs(appleSilicon: Bool = RecommendedApp.isAppleSilicon) -> [String] {
        var ids: [String] = []
        for app in Catalog.apps where appGroups.contains(app.group) && (!app.appleSiliconOnly || appleSilicon) {
            if app.isRecommended(appleSilicon: appleSilicon) {
                ids.append(app.id)
            } else if app.recommended, let other = app.replacedBy, Catalog.app(other)?.isRecommended(appleSilicon: appleSilicon) == true {
                ids.append(other)
            }
        }
        var seen: Set<String> = []
        return ids.filter { seen.insert($0).inserted }
    }

    /// Offer Apple's Command Line Tools (git, clang, make), which Homebrew and most code need.
    public var wantsCommandLineTools: Bool { self[.code] }
}

/// Apple's Command Line Tools for Xcode. Installing opens Apple's own installer.
public enum CommandLineTools {
    /// Exits 0 when they, or Xcode, are installed.
    public static let check = "xcode-select -p >/dev/null 2>&1"
    public static let install = "xcode-select --install"
}

extension Catalog {
    /// A preset's tweak ids, or none.
    static func preset(_ id: String) -> [String] { presets.first { $0.id == id }?.tweakIDs ?? [] }
}
