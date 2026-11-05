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
        guard Store.isOverridden, model.engine.backend is MockBackend else {
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

            if let preset = Catalog.presets.first(where: { $0.id == "windows" }) {
                model.stage(preset)
                let progress = model.presetProgress(preset)
                check("a preset stages only what is not applied", model.staged.count == progress.total - progress.applied)
                model.discard()
                check("discard forgets staged changes", model.staged.isEmpty)
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
            }

            await model.loadLoginItems()
            check("login items load", (model.loginItems?.count ?? 0) > 0)

            let file = URL(fileURLWithPath: "/tmp/UnbloatMyMac-self-set.json")
            try? TweakSet(tweaks: ["finder.pathBar", "dock.bounce"]).data().write(to: file)
            await model.importSet(from: file)
            check("importing a tweak set stages it for review", model.staged == ["finder.pathBar": true, "dock.bounce": true] && model.showReview)
            model.showReview = false
            model.discard()

            await model.scanStorage()
            check("storage scan measures every target", model.sizes.count == Catalog.cleanup.count)

            await model.refreshApps()
            check("Homebrew is found on the pretend Mac", model.apps.homebrew != nil)
            let recommended = model.missingRecommended
            await model.install(recommended)
            check("Install Recommended installs every starred app", model.missingRecommended.isEmpty && !recommended.isEmpty)
            check("tools with a shell line are turned on in ~/.zshrc",
                  recommended.filter { $0.shellLine != nil }.allSatisfy { model.apps.inShell.contains($0.id) })
            model.notice = nil
            if let posh = Catalog.app("oh-my-posh") {
                await model.setShell(posh, on: false)
                check("a shell line can be turned off alone", !model.apps.inShell.contains("oh-my-posh") && model.apps.inShell.contains("zoxide"))
                await model.uninstall(posh)
                check("uninstalling removes the app", model.appState(posh) == .notInstalled)
            }

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
