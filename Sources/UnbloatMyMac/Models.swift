import AppKit
import Foundation
import UnbloatMyMacKit

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: Hashable, Identifiable {
    case overview
    case category(TweakCategory)
    case background, storage, apps, history

    static var allCases: [SidebarItem] {
        [.overview] + TweakCategory.allCases.map { .category($0) } + [.background, .storage, .apps, .history]
    }

    var id: String { rawValue }

    var rawValue: String {
        switch self {
        case .overview: "overview"
        case .category(let category): category.rawValue
        case .background: "background"
        case .storage: "storage"
        case .apps: "apps"
        case .history: "history"
        }
    }

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .category(let category): category.title
        case .background: String(localized: "Background Items")
        case .storage: String(localized: "Storage")
        case .apps: String(localized: "Recommended Apps")
        case .history: String(localized: "History")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "sparkles"
        case .category(let category): category.symbol
        case .background: "gearshape.2"
        case .storage: "internaldrive"
        case .apps: "shippingbox"
        case .history: "clock.arrow.circlepath"
        }
    }
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    let engine: Engine
    let installer: AppInstaller
    var sidebar: SidebarItem? = .overview

    /// What the Mac looks like now, by tweak id.
    private(set) var statuses: [String: TweakStatus] = [:]
    private(set) var applied: Set<String> = []
    private(set) var history: [HistoryEntry] = []
    private(set) var launchItems: [LaunchItem] = []
    private(set) var launchItemsDisabledByApp: Set<String> = []
    private(set) var sizes: [String: CleanupSize] = [:]
    /// Tweaks the app applied that were put back, most often by a macOS update.
    private(set) var reverted: [String] = []
    private(set) var macOSUpdated = false
    /// Login items, loaded on request because reading them needs the admin password.
    private(set) var loginItems: [LoginItem]?
    private(set) var hasLoaded = false

    /// Changes waiting for Review: tweak id -> apply (true) or undo (false).
    var staged: [String: Bool] = [:]
    var showReview = false
    var confirmUndoAll = false
    var isBusy = false
    var isScanning = false
    /// An error or notice for an alert.
    var notice: String?

    var showAdvanced: Bool = UserDefaults.standard.bool(forKey: "showAdvanced") {
        didSet { UserDefaults.standard.set(showAdvanced, forKey: "showAdvanced") }
    }
    var restartApps: Bool = UserDefaults.standard.object(forKey: "restartApps") as? Bool ?? true {
        didSet { UserDefaults.standard.set(restartApps, forKey: "restartApps") }
    }
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    /// Recommended apps: Homebrew, what is installed, and what is in ~/.zshrc.
    private(set) var apps = AppsState()
    private(set) var appsLoaded = false
    /// Apps Homebrew is installing or removing now.
    private(set) var appsWorking: Set<String> = []

    init(engine: Engine, installer: AppInstaller) {
        self.engine = engine
        self.installer = installer
    }

    // MARK: Tweaks

    func tweaks(in category: TweakCategory) -> [Tweak] {
        engine.tweaks.filter { $0.category == category }
    }

    /// Advanced tweaks stay hidden unless Settings says to show them, or they are on or staged.
    func visibleTweaks(in category: TweakCategory) -> [Tweak] {
        tweaks(in: category).filter { showAdvanced || $0.risk < .advanced || isApplied($0) || staged[$0.id] != nil }
    }

    func status(_ tweak: Tweak) -> TweakStatus { statuses[tweak.id] ?? .off }

    /// Whether the tweak is applied, counting staged changes.
    func isApplied(_ tweak: Tweak) -> Bool { staged[tweak.id] ?? status(tweak).isOn }

    func setApplied(_ tweak: Tweak, _ on: Bool) {
        staged[tweak.id] = on == status(tweak).isOn ? nil : on
    }

    /// The switch: for a feature-named tweak it shows the feature, so it is the opposite of applied.
    func switchIsOn(_ tweak: Tweak) -> Bool { tweak.namesFeature ? !isApplied(tweak) : isApplied(tweak) }

    func setSwitch(_ tweak: Tweak, _ on: Bool) { setApplied(tweak, tweak.namesFeature ? !on : on) }

    func appliedCount(in category: TweakCategory) -> Int {
        tweaks(in: category).filter { status($0).isOn }.count
    }

    /// Tweaks this Mac can use: the "of" in "3 of 14 applied".
    func availableCount(in category: TweakCategory) -> Int {
        tweaks(in: category).filter { status($0).isAvailable }.count
    }

    func pendingCount(in category: TweakCategory) -> Int {
        tweaks(in: category).filter { staged[$0.id] != nil }.count
    }

    var stagedTweaks: [Tweak] { engine.tweaks.filter { staged[$0.id] != nil } }

    func stageAll(in category: TweakCategory, applied on: Bool) {
        for tweak in visibleTweaks(in: category) where status(tweak).isAvailable {
            setApplied(tweak, on)
        }
    }

    func stage(_ preset: Preset) {
        for id in preset.tweakIDs {
            guard let tweak = engine.tweaks.first(where: { $0.id == id }), status(tweak).isAvailable else { continue }
            setApplied(tweak, true)
        }
    }

    func presetProgress(_ preset: Preset) -> (applied: Int, total: Int) {
        let tweaks = preset.tweakIDs.compactMap { id in engine.tweaks.first { $0.id == id } }.filter { status($0).isAvailable }
        return (tweaks.filter { status($0).isOn }.count, tweaks.count)
    }

    func discard() { staged = [:] }

    func review() {
        guard !staged.isEmpty else { return }
        showReview = true
    }

    // MARK: Engine calls, off the main thread

    func refresh() async {
        let engine = engine
        async let state = Task.detached { engine.state() }.value
        async let items = Task.detached { engine.launchItems() }.value
        let (s, i) = await (state, items)
        statuses = s.statuses
        applied = s.applied
        history = s.history
        launchItemsDisabledByApp = s.launchItemsDisabledByApp
        reverted = s.reverted
        macOSUpdated = s.macOSUpdated
        launchItems = i
        // Drop staged changes that already match the Mac.
        staged = staged.filter { id, on in (statuses[id]?.isOn ?? false) != on }
        hasLoaded = true
    }

    func applyStaged() async -> ApplyReport {
        let changes = staged
        let engine = engine
        let restart = restartApps
        isBusy = true
        let report = await Task.detached { engine.apply(changes, restartApps: restart) }.value
        staged = [:]
        await refresh()
        isBusy = false
        return report
    }

    func undoEverything() async {
        let engine = engine
        isBusy = true
        let report = await Task.detached { engine.undoEverything() }.value
        staged = [:]
        await refresh()
        isBusy = false
        notice = report.failures.isEmpty
            ? String(localized: "Everything UnbloatMyMac changed is back the way it was.") + (report.needsLogout ? " " + String(localized: "Log out to finish.") : "")
            : String(localized: "Some changes could not be undone:") + "\n" + report.failures.values.sorted().joined(separator: "\n")
    }

    func setLaunchItem(_ item: LaunchItem, allowed: Bool) async {
        let engine = engine
        isBusy = true
        let error = await Task.detached { engine.setLaunchItem(item, disabled: !allowed) }.value
        await refresh()
        isBusy = false
        if let error { notice = error }
    }

    func scanStorage() async {
        guard !isScanning else { return }
        isScanning = true
        let engine = engine
        for target in Catalog.cleanup {
            sizes[target.id] = await Task.detached { engine.measure(target) }.value
        }
        isScanning = false
    }

    func clean(_ target: CleanupTarget) async {
        let engine = engine
        isBusy = true
        let error = await Task.detached { engine.clean(target) }.value
        sizes[target.id] = await Task.detached { engine.measure(target) }.value
        await refresh()
        isBusy = false
        if let error { notice = error }
    }

    var reclaimableBytes: Int64 {
        Catalog.cleanup.filter { $0.settingsPane == nil }.compactMap { sizes[$0.id]?.bytes }.reduce(0, +)
    }

    // MARK: Reverted by macOS

    /// Stages the reverted tweaks again, for Review.
    func stageReverted() {
        for id in reverted { staged[id] = true }
        review()
    }

    func forgetReverted() async {
        let engine = engine
        await Task.detached { engine.forgetReverted() }.value
        await refresh()
    }

    // MARK: Export and import

    func exportSet(to url: URL) async {
        let engine = engine
        do {
            let data = try await Task.detached { try engine.exportSet() }.value
            try data.write(to: url, options: .atomic)
        } catch {
            notice = error.localizedDescription
        }
    }

    /// Stages the tweaks in a saved set that are not on yet, then opens Review.
    func importSet(from url: URL) async {
        let engine = engine
        do {
            let set = try TweakSet.read(Data(contentsOf: url))
            let changes = await Task.detached { engine.changes(for: set) }.value
            if changes.isEmpty {
                notice = String(localized: "Every tweak in this file is already applied.")
                return
            }
            staged.merge(changes) { _, new in new }
            review()
        } catch {
            notice = error.localizedDescription
        }
    }

    func exportWithPanel() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "My Mac Tweaks.unbloat.json"
        panel.allowedContentTypes = [.json]
        panel.message = String(localized: "Save the tweaks that are on, to apply them on another Mac.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await exportSet(to: url) }
    }

    func importWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = String(localized: "Choose a tweaks file saved by UnbloatMyMac.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importSet(from: url) }
    }

    // MARK: Command line tool

    /// Links /usr/local/bin/unbloatmymac to this app's binary. Asks for the admin password.
    func installCommandLineTool() async {
        guard !Store.isOverridden, let binary = Bundle.main.executablePath else { return }
        let backend = engine.backend
        let script = "mkdir -p /usr/local/bin && ln -sf '\(binary)' /usr/local/bin/unbloatmymac"
        do {
            try await Task.detached { try backend.run([script], admin: true) }.value
            notice = String(localized: "Installed. Try “unbloatmymac list” in Terminal.")
        } catch {
            notice = error.localizedDescription
        }
    }

    // MARK: Recommended apps

    func refreshApps() async {
        let installer = installer
        apps = await Task.detached { installer.state() }.value
        appsLoaded = true
    }

    func appState(_ app: RecommendedApp) -> AppInstallState { apps.states[app.id] ?? .notInstalled }

    /// Recommended apps not installed yet.
    var missingRecommended: [RecommendedApp] {
        Catalog.appsHere.filter { $0.isRecommended() && appState($0) == .notInstalled }
    }

    func install(_ apps: [RecommendedApp]) async {
        let installer = installer
        var errors: [String] = []
        for app in apps where appState(app) == .notInstalled && !appsWorking.contains(app.id) {
            appsWorking.insert(app.id)
            do { try await Task.detached { try installer.install(app) }.value }
            catch { errors.append("\(app.name): \(error.localizedDescription)") }
            appsWorking.remove(app.id)
            await refreshApps()
        }
        if !errors.isEmpty { notice = errors.joined(separator: "\n") }
        else if apps.contains(where: { $0.shellLine != nil }) {
            notice = String(localized: "Installed. Open a new Terminal window to use it.")
        }
    }

    func uninstall(_ app: RecommendedApp) async {
        let installer = installer
        appsWorking.insert(app.id)
        do { try await Task.detached { try installer.uninstall(app) }.value }
        catch { notice = "\(app.name): \(error.localizedDescription)" }
        appsWorking.remove(app.id)
        await refreshApps()
    }

    func setShell(_ app: RecommendedApp, on: Bool) async {
        let installer = installer
        do { try await Task.detached { try installer.setShell(app, on: on) }.value }
        catch { notice = error.localizedDescription }
        await refreshApps()
    }

    static let homebrewCommand = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#

    func copyHomebrewCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.homebrewCommand, forType: .string)
        if let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: terminal, configuration: .init())
        }
        notice = String(localized: "The install command is on the clipboard. Paste it into Terminal, press Return, then come back and refresh.")
    }

    // MARK: Login items

    func loadLoginItems() async {
        let engine = engine
        isBusy = true
        do {
            loginItems = try await Task.detached { try engine.loginItems() }.value
        } catch {
            notice = error.localizedDescription
        }
        isBusy = false
    }

    func openSystemSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
    }
}
