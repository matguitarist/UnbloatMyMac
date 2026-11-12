import AppKit
import Foundation
import UnbloatMyMacKit

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: Hashable, Identifiable {
    case overview
    case category(TweakCategory)
    case background, storage, apps, history, log

    /// The Tools section of the sidebar, in order.
    static let tools: [SidebarItem] = [.background, .storage, .apps, .history, .log]

    static var allCases: [SidebarItem] {
        [.overview] + TweakCategory.allCases.map { .category($0) } + tools
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
        case .log: "log"
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
        case .log: String(localized: "Activity Log")
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
        case .log: "list.bullet.rectangle"
        }
    }
}

/// A batch of Homebrew installs or updates: "Installing 3 of 8: Mole".
struct AppProgress: Equatable {
    enum Kind { case install, update }
    let kind: Kind
    let done: Int
    let total: Int
    let current: String

    var text: String {
        switch kind {
        case .install: String(localized: "Installing \(done + 1) of \(total): \(current)…")
        case .update: String(localized: "Updating \(done + 1) of \(total): \(current)…")
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
    /// Security checks that pass, by id (Security page).
    private(set) var securityStatus: [String: Bool] = [:]
    /// The leftovers the Review Leftovers sheet lists, or nil when it is closed.
    var leftoversToReview: [Leftover]?
    /// The versions the Xcode Device Support sheet lists, or nil when it is closed.
    var deviceSupportToReview: [DeviceSupportVersion]?
    /// Old installers or project build files the review sheet lists, or nil when it is closed.
    var filesToReview: ReviewFileList?
    /// Tweaks the app applied that were put back, most often by a macOS update.
    private(set) var reverted: [String] = []
    private(set) var macOSUpdated = false
    /// Login items, loaded on request because reading them needs the admin password.
    private(set) var loginItems: [LoginItem]?
    private(set) var hasLoaded = false

    /// Changes waiting for Review: tweak id -> apply (true) or undo (false).
    var staged: [String: Bool] = [:]
    var showReview = false
    /// The Set Up for Me sheet.
    var showSetup = false
    /// Apple's Command Line Tools for Xcode are installed (Set Up for Me offers them to developers).
    var commandLineToolsInstalled = true
    /// Set when Set Up for Me staged changes, so Review opens once its sheet closes.
    var reviewAfterSetup = false
    /// Snapshot mode only: the answers and step Set Up for Me opens on.
    var setupSnapshot: (answers: SetupAnswers, step: Int)?
    /// The tweak whose details popover is open.
    var detailsTweak: String?
    var confirmUndoAll = false
    /// Apps the Install Recommended sheet lists, or nil when it is closed.
    var confirmInstall: [RecommendedApp]?
    /// Whether /usr/local/bin/unbloatmymac points at this copy of the app.
    private(set) var commandLineToolInstalled = AppModel.commandLineToolIsInstalled()
    var isBusy = false
    var isScanning = false
    /// An error or notice for an alert.
    var notice: String?
    /// The Activity Log, oldest first. Read again on every refresh.
    private(set) var logEntries: [LogEntry] = []
    var logFilter = LogFilter()
    var showLogInspector = true
    var confirmClearLog = false

    var showAdvanced: Bool = UserDefaults.standard.bool(forKey: "showAdvanced") {
        didSet { UserDefaults.standard.set(showAdvanced, forKey: "showAdvanced") }
    }
    var restartApps: Bool = UserDefaults.standard.object(forKey: "restartApps") as? Bool ?? true {
        didSet { UserDefaults.standard.set(restartApps, forKey: "restartApps") }
    }
    /// The app's own language. Changing it takes effect after a restart.
    var language: AppLanguage = AppLanguage.current {
        didSet { if language != oldValue { language.apply() } }
    }
    /// Sparkle's setting, mirrored so Settings and Restore Settings redraw it.
    var checksForUpdates: Bool = Updater.shared.automaticallyChecks {
        didSet { if Updater.shared.isAvailable { Updater.shared.automaticallyChecks = checksForUpdates } }
    }
    /// The login agent that tells when macOS put back tweaks.
    private(set) var revertWatch = RevertWatch.status

    func setRevertWatch(_ on: Bool) async {
        do { try await RevertWatch.set(on) }
        catch { notice = error.localizedDescription }
        revertWatch = RevertWatch.status
        log?.add(.info, .app, on ? "Turned on the login check for put-back tweaks" : "Turned off the login check for put-back tweaks")
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
    /// Installed apps with a newer version in Homebrew.
    private(set) var appUpdates: Set<String> = []
    private(set) var checkingAppUpdates = false
    /// A batch of installs or updates running now, for the progress bar.
    private(set) var appProgress: AppProgress?

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
        async let security = Task.detached { engine.securityStatus() }.value
        let (s, i, checks) = await (state, items, security)
        securityStatus = checks
        statuses = s.statuses
        applied = s.applied
        history = s.history
        launchItemsDisabledByApp = s.launchItemsDisabledByApp
        reverted = s.reverted
        macOSUpdated = s.macOSUpdated
        launchItems = i
        await reloadLog()
        // Drop staged changes that already match the Mac.
        staged = staged.filter { id, on in (statuses[id]?.isOn ?? false) != on }
        hasLoaded = true
    }

    /// Applies the staged changes, except the ones Review was told to leave as they are.
    func applyStaged(skipping kept: Set<String> = []) async -> ApplyReport {
        for id in kept { staged[id] = nil }
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

    /// Open apps whose caches this target would move, asked before cleaning.
    func openApps(holding target: CleanupTarget) async -> [OpenApp] {
        let engine = engine
        return await Task.detached { engine.openApps(holding: target) }.value
    }

    /// Cleans a target. Apps in `quitting` are asked to quit first; other open apps keep their caches.
    func clean(_ target: CleanupTarget, quitting apps: [OpenApp] = []) async {
        let engine = engine
        isBusy = true
        let error = await Task.detached { engine.clean(target, quitting: apps) }.value
        sizes[target.id] = await Task.detached { engine.measure(target) }.value
        await refresh()
        isBusy = false
        if let error { notice = error }
    }

    /// Finds the leftovers of deleted apps and opens the sheet that lists them.
    func reviewLeftovers() async {
        let engine = engine
        sidebar = .storage
        isBusy = true
        let found = await Task.detached { engine.leftovers() }.value
        isBusy = false
        sizes["leftovers"] = CleanupSize(bytes: found.reduce(0) { $0 + $1.bytes }, items: found.count)
        if found.isEmpty {
            notice = String(localized: "No leftovers found. Every app with files in your Library is still installed, or used them in the last 30 days.")
        } else {
            leftoversToReview = found
        }
    }

    func trash(_ leftovers: [Leftover]) async {
        let engine = engine
        isBusy = true
        let error = await Task.detached { engine.trash(leftovers) }.value
        if let target = Catalog.cleanup.first(where: { $0.kind == .leftovers }) {
            sizes[target.id] = await Task.detached { engine.measure(target) }.value
        }
        await refresh()
        isBusy = false
        if let error { notice = error }
    }

    /// Finds Xcode's device support versions and opens the sheet that lists them.
    func reviewDeviceSupport() async {
        let engine = engine
        sidebar = .storage
        isBusy = true
        let found = await Task.detached { engine.deviceSupport() }.value
        isBusy = false
        sizes["deviceSupport"] = DeviceSupportFinder.size(of: found)
        if found.isEmpty {
            notice = String(localized: "No Xcode device support found. Xcode adds it when you run an app on a connected device.")
        } else {
            deviceSupportToReview = found
        }
    }

    func trash(deviceSupport versions: [DeviceSupportVersion]) async {
        let engine = engine
        isBusy = true
        let error = await Task.detached { engine.trash(deviceSupport: versions) }.value
        let left = await Task.detached { engine.deviceSupport() }.value
        sizes["deviceSupport"] = DeviceSupportFinder.size(of: left)
        await refresh()
        isBusy = false
        if let error { notice = error }
    }

    /// Finds a reviewed target's items (old installers, project build files) and opens the sheet that lists them.
    func reviewFiles(_ id: String) async {
        guard let target = Catalog.cleanup.first(where: { $0.id == id }) else { return }
        let engine = engine
        sidebar = .storage
        isBusy = true
        let found = await Task.detached { engine.reviewItems(target) }.value
        isBusy = false
        sizes[target.id] = ReviewItem.size(of: found)
        if found.isEmpty {
            notice = target.kind == .buildArtifacts
                ? String(localized: "No build files found in Developer, Projects, Code, or src.")
                : String(localized: "No installers found in Downloads. Ones from the last day are left out, since you may still be using them.")
        } else {
            filesToReview = ReviewFileList(target: target, items: found)
        }
    }

    func trash(_ items: [ReviewItem], from target: CleanupTarget) async {
        let engine = engine
        isBusy = true
        let error = await Task.detached { engine.trash(items, from: target) }.value
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
            log?.add(.info, .tweaks, "Exported tweaks to \(url.lastPathComponent)", detail: url.path)
        } catch {
            log?.add(.error, .tweaks, "Could not export tweaks: \(error.localizedDescription)", detail: url.path)
            notice = error.localizedDescription
        }
    }

    /// Stages the tweaks in a saved set that are not on yet, then opens Review.
    func importSet(from url: URL) async {
        do { await stage(try TweakSet.read(Data(contentsOf: url)), from: url) }
        catch { notice = error.localizedDescription }
    }

    /// Stages what a set adds and opens Review. Returns false when every tweak was already on.
    @discardableResult
    private func stage(_ set: TweakSet, from url: URL, quiet: Bool = false) async -> Bool {
        let engine = engine
        let changes = await Task.detached { engine.changes(for: set) }.value
        log?.add(.info, .tweaks, "Imported \(url.lastPathComponent): \(changes.count) of \(set.tweaks.count) tweaks to review",
                 detail: set.tweaks.joined(separator: "\n"))
        if changes.isEmpty {
            if !quiet { notice = String(localized: "Every tweak in this file is already applied.") }
            return false
        }
        staged.merge(changes) { _, new in new }
        review()
        return true
    }

    // MARK: Settings backup

    /// Reads the settings again, in case the command line tool restored a backup.
    func reloadPreferences() {
        guard !Store.isOverridden else { return }
        let saved = PreferenceStore.read()
        if let v = saved.showAdvanced, v != showAdvanced { showAdvanced = v }
        if let v = saved.restartApps, v != restartApps { restartApps = v }
        if let v = saved.accent, v != ThemeStore.shared.themeID { ThemeStore.shared.themeID = v }
        if AppLanguage.current != language { language = AppLanguage.current }
    }

    /// The app's own settings now.
    var preferences: AppPreferences {
        AppPreferences(showAdvanced: showAdvanced, restartApps: restartApps, accent: ThemeStore.shared.themeID,
                       language: language.code ?? "system",
                       checksForUpdates: Updater.shared.isAvailable ? checksForUpdates : nil)
    }

    /// Sets what the backup has and leaves the rest. Returns true when the language changed (it needs a restart).
    @discardableResult
    func apply(_ preferences: AppPreferences) -> Bool {
        if let value = preferences.showAdvanced { showAdvanced = value }
        if let value = preferences.restartApps { restartApps = value }
        if let id = preferences.accent, Theme.all.contains(where: { $0.id == id }) { ThemeStore.shared.themeID = id }
        if let value = preferences.checksForUpdates, Updater.shared.isAvailable { checksForUpdates = value }
        guard let code = preferences.language else { return false }
        let restored = code == "system" ? AppLanguage.system : AppLanguage(code: code)
        guard restored == .system || AppLanguage.available.contains(restored), restored != language else { return false }
        language = restored
        return true
    }

    /// Saves the app's settings and the tweaks that are on to one file.
    func backUpSettings(to url: URL) async {
        let engine = engine
        let preferences = preferences
        do {
            let data = try await Task.detached { try engine.exportSet(preferences: preferences) }.value
            try data.write(to: url, options: .atomic)
            log?.add(.info, .app, "Backed up settings to \(url.lastPathComponent)", detail: url.path)
        } catch {
            log?.add(.error, .app, "Could not back up settings: \(error.localizedDescription)", detail: url.path)
            notice = error.localizedDescription
        }
    }

    /// Applies the app's settings from a backup at once, then opens Review for its tweaks.
    func restoreSettings(from url: URL) async {
        do {
            let set = try TweakSet.read(Data(contentsOf: url))
            var restartNeeded = false
            if let preferences = set.preferences {
                restartNeeded = apply(preferences)
                log?.add(.info, .app, "Restored settings from \(url.lastPathComponent)", detail: url.path)
            }
            let staged = await stage(set, from: url, quiet: true)
            if restartNeeded {
                notice = String(localized: "Settings restored. The new language applies after you restart UnbloatMyMac.")
            } else if !staged {
                notice = set.preferences == nil
                    ? String(localized: "Every tweak in this file is already applied.")
                    : String(localized: "Settings restored. Every tweak in the backup is already applied.")
            }
        } catch {
            notice = error.localizedDescription
        }
    }

    func backUpWithPanel() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "UnbloatMyMac Settings.unbloat.json")
        panel.allowedContentTypes = [.json]
        panel.message = String(localized: "Save UnbloatMyMac’s settings and the tweaks that are on, to restore them later or on another Mac.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await backUpSettings(to: url) }
    }

    func restoreWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = String(localized: "Choose a settings backup or tweaks file saved by UnbloatMyMac.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await restoreSettings(from: url) }
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

    // MARK: Activity Log

    var log: ActivityLog? { engine.log }

    func reloadLog() async {
        guard let log else { return }
        logEntries = await Task.detached { log.entries() }.value
    }

    func clearLog() {
        log?.clear()
        logEntries = []
    }

    /// The lines as plain text, with a header that says which app and Mac wrote them.
    func logText(_ entries: [LogEntry]) -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return (["UnbloatMyMac \(version), macOS \(os)", ""] + entries.map(\.line)).joined(separator: "\n")
    }

    func copyLog(_ entries: [LogEntry]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logText(entries), forType: .string)
    }

    func exportLogWithPanel() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "UnbloatMyMac Activity \(Date.now.formatted(.iso8601.year().month().day())).txt"
        panel.allowedContentTypes = [.plainText]
        panel.message = String(localized: "Save the activity log as text, to attach to a bug report.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try logText(logEntries).write(to: url, atomically: true, encoding: .utf8) }
        catch { notice = error.localizedDescription }
    }

    func showLogInFinder() {
        guard let log else { return }
        NSWorkspace.shared.activateFileViewerSelecting([log.url])
    }

    // MARK: Command line tool

    /// Links /usr/local/bin/unbloatmymac to this app's binary. Asks for the admin password.
    static let commandLineToolPath = "/usr/local/bin/unbloatmymac"

    /// True when the link exists and points at this app's binary. A link to another copy offers Install again.
    static func commandLineToolIsInstalled() -> Bool {
        guard !Store.isOverridden, let binary = Bundle.main.executablePath,
              let target = try? FileManager.default.destinationOfSymbolicLink(atPath: commandLineToolPath) else { return false }
        return URL(fileURLWithPath: target).resolvingSymlinksInPath().path == URL(fileURLWithPath: binary).resolvingSymlinksInPath().path
    }

    func installCommandLineTool() async {
        guard !Store.isOverridden, let binary = Bundle.main.executablePath else { return }
        let backend = engine.backend
        let script = "mkdir -p /usr/local/bin && ln -sf '\(binary)' \(Self.commandLineToolPath)"
        do {
            try await Task.detached { try backend.run([script], admin: true) }.value
            notice = String(localized: "Installed. Try “unbloatmymac list” in Terminal.")
        } catch {
            notice = error.localizedDescription
        }
        commandLineToolInstalled = Self.commandLineToolIsInstalled()
    }

    func uninstallCommandLineTool() async {
        guard !Store.isOverridden else { return }
        let backend = engine.backend
        let script = "rm -f \(Self.commandLineToolPath)"
        do {
            try await Task.detached { try backend.run([script], admin: true) }.value
            notice = String(localized: "The command line tool is removed.")
        } catch {
            notice = error.localizedDescription
        }
        commandLineToolInstalled = Self.commandLineToolIsInstalled()
    }

    // MARK: Recommended apps

    func refreshApps() async {
        let installer = installer
        apps = await Task.detached { installer.state() }.value
        appsLoaded = true
        commandLineToolInstalled = Self.commandLineToolIsInstalled()
        await reloadLog()
    }

    func appState(_ app: RecommendedApp) -> AppInstallState { apps.states[app.id] ?? .notInstalled }

    /// Recommended apps not installed yet.
    var missingRecommended: [RecommendedApp] {
        Catalog.appsHere.filter { $0.isRecommended() && $0.installsWithHomebrew && appState($0) == .notInstalled }
    }

    /// Opens the sheet that lists what Install Recommended will install.
    func reviewInstallRecommended() {
        let missing = missingRecommended
        guard !missing.isEmpty else { return }
        sidebar = .apps
        confirmInstall = missing
    }

    func install(_ apps: [RecommendedApp]) async {
        let installer = installer
        let queue = apps.filter { appState($0) == .notInstalled && !appsWorking.contains($0.id) }
        let errors = await run(queue, kind: .install) { app in try installer.install(app) }
        if !errors.isEmpty { notice = errors.joined(separator: "\n") }
        else if queue.contains(where: { $0.shellLine != nil }) {
            notice = String(localized: "Installed. Open a new Terminal window to use it.")
        }
    }

    /// Snapshot mode only: shows the progress bar without installing.
    func showProgressForSnapshot(_ progress: AppProgress?) {
        guard Store.isOverridden else { return }
        appProgress = progress
    }

    /// Installed apps with an update, in catalog order.
    var updatableApps: [RecommendedApp] { Catalog.appsHere.filter { appUpdates.contains($0.id) } }

    /// Asks Homebrew which apps have a newer version. `fetch` downloads Homebrew's index first.
    func checkAppUpdates(fetch: Bool = false) async {
        guard apps.homebrew != nil, !checkingAppUpdates else { return }
        let installer = installer
        checkingAppUpdates = true
        appUpdates = await Task.detached { installer.outdated(fetch: fetch) }.value
        checkingAppUpdates = false
        if fetch && appUpdates.isEmpty { notice = String(localized: "Every app installed with Homebrew is up to date.") }
        await reloadLog()
    }

    func update(_ apps: [RecommendedApp]) async {
        let installer = installer
        let queue = apps.filter { appUpdates.contains($0.id) && !appsWorking.contains($0.id) }
        let errors = await run(queue, kind: .update) { app in try installer.upgrade(app) }
        await checkAppUpdates()
        if !errors.isEmpty { notice = errors.joined(separator: "\n") }
    }

    /// Runs Homebrew on each app in turn, showing progress. Returns one line per failure.
    private func run(_ queue: [RecommendedApp], kind: AppProgress.Kind,
                     _ work: @escaping @Sendable (RecommendedApp) throws -> Void) async -> [String] {
        var errors: [String] = []
        for (index, app) in queue.enumerated() {
            appProgress = queue.count > 1 ? AppProgress(kind: kind, done: index, total: queue.count, current: app.name) : nil
            appsWorking.insert(app.id)
            do { try await Task.detached { try work(app) }.value }
            catch { errors.append("\(app.name): \(error.localizedDescription)") }
            appsWorking.remove(app.id)
            await refreshApps()
        }
        appProgress = nil
        return errors
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
