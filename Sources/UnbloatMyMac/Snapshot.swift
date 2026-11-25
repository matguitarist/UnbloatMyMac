import AppKit
import AppTestKit
import SwiftUI
import UnbloatMyMacKit

/// Screenshot mode for agents.
///   APP_STORE=/tmp/test.store APP_SNAPSHOT=/tmp/shots ~/Applications/UnbloatMyMac.app/Contents/MacOS/UnbloatMyMac
/// writes <page>-light.png and <page>-dark.png for every sidebar page, and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=all,starred limits the pages. Add "settings" to include Settings, "help" for the Help window, "install" for the Install Recommended sheet, "setup" for Set Up for Me, "devicesupport" for Xcode Device Support, "installers" and "buildfiles" for their review sheets, "leftovers" for the Review Leftovers sheet.
/// Add APP_ACCENT=<id> to see the pages in another accent.
/// Add APP_SNAPSHOT_MIN=1 to shrink the main window to its smallest size first.
enum Snapshot {
    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction, openWindow: OpenWindowAction) {
        // Snapshots never run against the real journal.
        guard let run = SnapshotRun.requested(layout: { GridProbes.shared.write(to: $0.path, window: $1) }) else { return }
        Task {
            await run.start()
            let pages = SidebarItem.allCases
            await run.shootPages(pages.map(\.rawValue)) { name in
                if let page = pages.first(where: { $0.rawValue == name }) { model.sidebar = page }
            }
            if run.wants("review"), !model.staged.isEmpty {
                model.sidebar = .overview
                await run.shoot("review", window: { sheet() }, show: { model.showReview = true }, hide: { model.showReview = false })
            }
            await run.shoot("apps-progress", when: "progress", show: {
                model.sidebar = .apps
                model.showProgressForSnapshot(AppProgress(kind: .install, done: 2, total: 8, current: "Mole"))
            }, hide: { model.showProgressForSnapshot(nil) })
            if run.wants("details"), let tweak = Catalog.tweaks.first(where: { $0.category == .dock }) {
                model.sidebar = .category(.dock)
                await run.pause()
                await run.shoot("details", window: { NSApp.windows.first { $0.isVisible && $0.className.contains("Popover") } },
                                show: { model.detailsTweak = tweak.id }, hide: { model.detailsTweak = nil })
            }
            await run.shoot("install", window: { sheet() }, show: { model.reviewInstallRecommended() }, hide: { model.confirmInstall = nil })
            await run.shoot("devicesupport", window: { sheet() }, show: { await model.reviewDeviceSupport() },
                            hide: { model.deviceSupportToReview = nil })
            // Build files shows a folder the person added, to see the Searched Folders section with a Remove button.
            model.projectFolders = ["~/Documents/Rust"]
            for (name, id) in [("installers", "oldInstallers"), ("buildfiles", "buildArtifacts")] {
                await run.shoot(name, window: { sheet() }, show: { await model.reviewFiles(id) }, hide: { model.filesToReview = nil })
            }
            model.projectFolders = []
            let picked = SetupAnswers([.code: true, .windows: true, .privacy: true, .speed: false])
            for (name, step) in [("setup", 0), ("setup-summary", SetupQuestion.allCases.count)] {
                await run.shoot(name, when: "setup", window: { sheet() }, show: {
                    model.sidebar = .overview
                    model.setupSnapshot = (picked, step)
                    model.openSetup()
                }, hide: { model.showSetup = false })
            }
            model.setupSnapshot = nil
            await run.shoot("leftovers", window: { sheet() }, show: { await model.reviewLeftovers() }, hide: { model.leftoversToReview = nil })
            if run.wants("help") {
                let main = WindowShot.mainWindow()
                openWindow(id: HelpView.windowID)
                await run.pause(.seconds(1))
                let help = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet && $0.identifier?.rawValue.contains(HelpView.windowID) == true }
                await run.forEachAppearance { look in
                    await run.pause()
                    await run.capture("help", look, window: help)
                }
                help?.close()
                await run.pause(.seconds(0.4))
            }
            await run.shootSettings(tabs: SettingsTab.allCases.map(\.rawValue), open: { openSettings() },
                                    select: { tab in if let tab = SettingsTab(rawValue: tab) { model.settingsTab = tab } })
            run.finish()
        }
    }

    /// The sheet open on the main window.
    private static func sheet() -> NSWindow? { WindowShot.mainWindow()?.attachedSheet }
}
