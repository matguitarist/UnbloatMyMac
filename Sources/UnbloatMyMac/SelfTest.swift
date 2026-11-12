import AppKit
import UnbloatMyMacKit

/// Self-test for agents: drives the app model on a pretend Mac (MockBackend),
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/UnbloatMyMac-self.json ~/Applications/UnbloatMyMac.app/Contents/MacOS/UnbloatMyMac --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden, ((model.engine.backend as? LoggingBackend)?.base ?? model.engine.backend) is MockBackend else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp so the test runs on a pretend Mac")
            finish(code: 1)
            return
        }
        Task {
            await model.refresh()
            guard let genmoji = Catalog.tweak("ai.genmoji"), let recents = Catalog.tweak("dock.recents"),
                  let extensions = Catalog.tweak("finder.extensions") else {
                check("catalog has the tweaks the test uses", false)
                finish(code: 1)
                return
            }

            check("feature switches start on", model.switchIsOn(genmoji))
            model.setSwitch(genmoji, false)
            check("switching a feature off stages the tweak", model.staged["ai.genmoji"] == true)
            model.setSwitch(genmoji, true)
            check("switching it back clears the change", model.staged.isEmpty)

            model.setSwitch(extensions, true)
            model.setSwitch(recents, false)
            check("two changes are staged", model.staged.count == 2)
            check("the sidebar badge counts them", model.pendingCount(in: .finder) == 1 && model.pendingCount(in: .dock) == 1)
            let report = await model.applyStaged()
            check("applying reports no failures", report.failures.isEmpty, "\(report.failures)")
            check("applied tweaks show as applied", model.isApplied(extensions) && model.isApplied(recents))
            check("staged changes are cleared", model.staged.isEmpty)
            check("history has both changes", model.history.count >= 2)
            check("the activity log lists both tweaks",
                  model.logEntries.contains { $0.source == .tweaks && $0.message == "Applied finder.extensions" }
                  && model.logEntries.contains { $0.source == .tweaks && $0.message == "Applied dock.recents" })
            check("the activity log shows the defaults command",
                  model.logEntries.contains { $0.source == .settings && ($0.detail ?? "").hasPrefix("defaults write com.apple.dock") })

            if let snap = Catalog.tweak("win.snap"), let scroll = Catalog.tweak("win.scrollBars") {
                model.setApplied(snap, true)
                model.setApplied(scroll, true)
                let kept = await model.applyStaged(skipping: ["win.snap"])
                check("Leave in Review keeps that setting and applies the rest",
                      kept.failures.isEmpty && !model.isApplied(snap) && model.isApplied(scroll) && model.staged.isEmpty)
                model.setApplied(scroll, false)
                _ = await model.applyStaged()
            }

            if let preset = Catalog.presets.first(where: { $0.id == "windows" }) {
                model.stage(preset)
                let progress = model.presetProgress(preset)
                check("a preset stages only what is not applied", model.staged.count == progress.total - progress.applied)
                model.discard()
                check("discard forgets staged changes", model.staged.isEmpty)
            }

            do {
                let developer = SetupAnswers([.intelligence: true, .code: true])
                let changes = model.setupChanges(developer)
                model.finishSetup(developer, apps: [], commandLineTools: false)
                check("Set Up for Me stages its changes and opens Review after",
                      !changes.isEmpty && model.staged.count == changes.count && model.reviewAfterSetup)
                check("Set Up for Me keeps Apple Intelligence for someone who uses it",
                      !model.staged.keys.contains { $0.hasPrefix("ai.") && $0 != "ai.siri" })
                check("Set Up for Me offers Terminal tools to a developer",
                      model.setupApps(developer).contains { $0.group == .terminal } && developer.wantsCommandLineTools)
                model.reviewAfterSetup = false
                model.discard()
            }

            check("advanced tweaks are hidden by default",
                  model.visibleTweaks(in: .intelligence).allSatisfy { $0.risk < .advanced } || model.showAdvanced)

            await model.undoEverything()
            check("undo everything clears what the app applied", model.applied.isEmpty)
            check("feature switches are back on", model.switchIsOn(recents))

            if let motion = Catalog.tweak("perf.reduceMotion") {
                model.setApplied(motion, true)
                let protected = await model.applyStaged()
                check("a protected setting asks for Full Disk Access", protected.needsFullDiskAccess)
                let errors = model.logEntries.filter { $0.level == .error }
                check("a refused setting is an error in the activity log", errors.contains { $0.message == "Could not apply perf.reduceMotion" })
                check("the Errors filter shows only errors",
                      !errors.isEmpty && model.logEntries.filter(LogFilter(levels: [.error]).matches) == errors)
            }

            await model.loadLoginItems()
            check("login items load", (model.loginItems?.count ?? 0) > 0)

            let file = URL(fileURLWithPath: "/tmp/UnbloatMyMac-self-set.json")
            try? TweakSet(tweaks: ["finder.pathBar", "dock.bounce"]).data().write(to: file)
            await model.importSet(from: file)
            check("importing a tweak set stages it for review", model.staged == ["finder.pathBar": true, "dock.bounce": true] && model.showReview)
            model.showReview = false
            model.discard()

            let told = RevertWatch.message(RevertNotice(tweaks: ["dock.recents", "dock.bounce"], macOSUpdated: true, osBuild: "25A1"))
            check("the login notification counts the put-back tweaks", told.title.contains("2") && !told.body.isEmpty)
            check("the login agent is never registered on a pretend Mac", RevertWatch.status == .off)

            // Same preferences as now, so nothing outside the pretend Mac changes.
            let backup = URL(fileURLWithPath: "/tmp/UnbloatMyMac-self-backup.json")
            await model.backUpSettings(to: backup)
            let saved = try? TweakSet.read(Data(contentsOf: backup))
            check("a settings backup holds the app's settings", saved?.preferences == model.preferences)
            try? TweakSet(tweaks: ["finder.pathBar"], preferences: model.preferences).data().write(to: backup)
            await model.restoreSettings(from: backup)
            check("restoring settings opens Review for the backup's tweaks", model.staged == ["finder.pathBar": true] && model.showReview)
            model.showReview = false
            model.discard()
            model.notice = nil

            await model.scanStorage()
            check("storage scan measures every target", model.sizes.count == Catalog.cleanup.count)
            if let web = Catalog.cleanup.first(where: { $0.id == "chromiumCaches" }) {
                let open = await model.openApps(holding: web)
                check("cleaning web app caches names the open apps first", open.map(\.name) == ["Slack", "Discord"])
                await model.clean(web, quitting: open)
                check("Quit and Clean quits them and cleans everything", model.sizes["chromiumCaches"]?.isEmpty == true && model.notice == nil)
            }

            check("the Security page reports every check", model.securityStatus.count == Catalog.securityChecks.count)
            check("a security check that fails is reported", model.securityStatus["filevault"] == false)
            if let firewall = Catalog.tweak("security.firewall"), let remoteLogin = Catalog.tweak("security.remoteLogin") {
                model.setSwitch(firewall, true)
                model.setSwitch(remoteLogin, false)
                check("turning on the firewall and off Remote Login stages both",
                      model.staged == ["security.firewall": true, "security.remoteLogin": true])
                _ = await model.applyStaged()
                check("the firewall is on and Remote Login is off", model.switchIsOn(firewall) && !model.switchIsOn(remoteLogin))
                await model.undoEverything()
                check("undo turns the firewall off and Remote Login on again", !model.switchIsOn(firewall) && model.switchIsOn(remoteLogin))
                model.notice = nil
            }

            await model.reviewDeviceSupport()
            let versions = model.deviceSupportToReview ?? []
            model.deviceSupportToReview = nil
            let kept = DeviceSupportFinder.newest(versions)
            check("Xcode Device Support lists every version and keeps the newest of each device",
                  versions.count == 4 && kept.count == 2 && model.sizes["deviceSupport"]?.items == 2)
            await model.trash(deviceSupport: versions.filter { !kept.contains($0.path) })
            check("moving old versions to the Trash leaves only the newest",
                  model.sizes["deviceSupport"]?.items == 0 && model.sizes["deviceSupport"]?.kept == 2
                  && model.logEntries.contains { $0.source == .storage && $0.message.hasPrefix("Moved 2 Xcode device support") })

            await model.reviewLeftovers()
            let leftovers = model.leftoversToReview ?? []
            check("Review Leftovers lists what deleted apps left", !leftovers.isEmpty)
            model.leftoversToReview = nil
            let spotify = leftovers.filter { $0.bundleID == "com.spotify.client" }
            await model.trash(spotify)
            check("moving leftovers to the Trash removes them from the list",
                  model.sizes["leftovers"]?.items == leftovers.count - spotify.count && !spotify.isEmpty)
            check("leftovers in the Trash are in History and the activity log",
                  model.history.contains { $0.title.contains("1") && $0.error == nil }
                  && model.logEntries.contains { $0.source == .storage && $0.message.hasPrefix("Moved \(spotify.count) leftovers") })

            await model.refreshApps()
            check("Homebrew is found on the pretend Mac", model.apps.homebrew != nil)
            let recommended = model.missingRecommended
            model.reviewInstallRecommended()
            check("Install Recommended first lists every missing starred app", model.confirmInstall?.map(\.id) == recommended.map(\.id))
            model.confirmInstall = nil
            await model.install(recommended)
            check("Install Recommended installs every starred app", model.missingRecommended.isEmpty && !recommended.isEmpty)
            if let mock = model.installer.packages as? MockPackageManager, let first = recommended.first(where: \.installsWithHomebrew) {
                mock.markOutdated(first.id)
                await model.checkAppUpdates()
                check("an app with a newer version shows Update", model.updatableApps.map(\.id) == [first.id])
                await model.update(model.updatableApps)
                check("Update All updates it", model.appUpdates.isEmpty && model.appProgress == nil)
            }
            check("tools with a shell line are turned on in ~/.zshrc",
                  recommended.filter { $0.shellLine != nil }.allSatisfy { model.apps.inShell.contains($0.id) })
            model.notice = nil
            if let posh = Catalog.app("oh-my-posh") {
                await model.setShell(posh, on: false)
                check("a shell line can be turned off alone", !model.apps.inShell.contains("oh-my-posh") && model.apps.inShell.contains("zoxide"))
                await model.uninstall(posh)
                check("uninstalling removes the app", model.appState(posh) == .notInstalled)
            }

            check("installs are in the activity log", model.logEntries.contains { $0.source == .apps && $0.message.hasPrefix("Installed ") })
            check("the exported log has every line", model.logText(model.logEntries).components(separatedBy: "\n").count >= model.logEntries.count)
            model.clearLog()
            check("Clear Log empties the activity log", model.logEntries.isEmpty)

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
