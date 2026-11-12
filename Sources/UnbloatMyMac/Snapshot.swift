import AppKit
import IOKit.pwr_mgt
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
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Snapshots never run against the real database.
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a file in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            if env["APP_SNAPSHOT_MIN"] != nil, let main = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) {
                // The window clamps to its content's minimum size.
                main.setContentSize(NSSize(width: 1, height: 1))
                try? await Task.sleep(for: .seconds(0.5))
            }
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                for page in SidebarItem.allCases where only?.contains(page.rawValue) ?? true {
                    model.sidebar = page
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/\(page.rawValue)-\(mode).png")
                }
            }
            if (only == nil || only?.contains("review") == true), !model.staged.isEmpty {
                model.sidebar = .overview
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    model.showReview = true
                    try? await Task.sleep(for: .seconds(1))
                    let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                    capture(to: "\(dir)/review-\(mode).png", window: main?.attachedSheet)
                    model.showReview = false
                    try? await Task.sleep(for: .seconds(0.6))
                }
            }
            if only == nil || only?.contains("progress") == true {
                model.sidebar = .apps
                model.showProgressForSnapshot(AppProgress(kind: .install, done: 2, total: 8, current: "Mole"))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/apps-progress-\(mode).png")
                }
                model.showProgressForSnapshot(nil)
            }
            if only == nil || only?.contains("details") == true, let tweak = Catalog.tweaks.first(where: { $0.category == .dock }) {
                model.sidebar = .category(.dock)
                try? await Task.sleep(for: .seconds(0.8))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    model.detailsTweak = tweak.id
                    try? await Task.sleep(for: .seconds(1))
                    let popover = NSApp.windows.first { $0.isVisible && $0.className.contains("Popover") }
                    capture(to: "\(dir)/details-\(mode).png", window: popover)
                    model.detailsTweak = nil
                    try? await Task.sleep(for: .seconds(0.6))
                }
            }
            if only == nil || only?.contains("install") == true {
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    model.reviewInstallRecommended()
                    try? await Task.sleep(for: .seconds(1))
                    let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                    capture(to: "\(dir)/install-\(mode).png", window: main?.attachedSheet)
                    model.confirmInstall = nil
                    try? await Task.sleep(for: .seconds(0.6))
                }
            }
            if only == nil || only?.contains("devicesupport") == true {
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    await model.reviewDeviceSupport()
                    try? await Task.sleep(for: .seconds(1))
                    let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                    capture(to: "\(dir)/devicesupport-\(mode).png", window: main?.attachedSheet)
                    model.deviceSupportToReview = nil
                    try? await Task.sleep(for: .seconds(0.6))
                }
            }
            // Build files shows a folder the person added, to see the Searched Folders section with a Remove button.
            model.projectFolders = ["~/Documents/Rust"]
            for (name, id) in [("installers", "oldInstallers"), ("buildfiles", "buildArtifacts")] where only == nil || only?.contains(name) == true {
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    await model.reviewFiles(id)
                    try? await Task.sleep(for: .seconds(1))
                    let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                    capture(to: "\(dir)/\(name)-\(mode).png", window: main?.attachedSheet)
                    model.filesToReview = nil
                    try? await Task.sleep(for: .seconds(0.6))
                }
            }
            model.projectFolders = []
            if only == nil || only?.contains("setup") == true {
                model.sidebar = .overview
                let picked = SetupAnswers([.code: true, .windows: true, .privacy: true, .speed: false])
                for (name, step) in [("setup", 0), ("setup-summary", SetupQuestion.allCases.count)] {
                    for mode in ["light", "dark"] {
                        NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                        model.setupSnapshot = (picked, step)
                        model.openSetup()
                        try? await Task.sleep(for: .seconds(1))
                        let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                        capture(to: "\(dir)/\(name)-\(mode).png", window: main?.attachedSheet)
                        model.showSetup = false
                        try? await Task.sleep(for: .seconds(0.6))
                    }
                }
                model.setupSnapshot = nil
            }
            if only == nil || only?.contains("leftovers") == true {
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    await model.reviewLeftovers()
                    try? await Task.sleep(for: .seconds(1))
                    let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                    capture(to: "\(dir)/leftovers-\(mode).png", window: main?.attachedSheet)
                    model.leftoversToReview = nil
                    try? await Task.sleep(for: .seconds(0.6))
                }
            }
            if only == nil || only?.contains("help") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                openWindow(id: HelpView.windowID)
                try? await Task.sleep(for: .seconds(1))
                let help = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet && $0.identifier?.rawValue.contains(HelpView.windowID) == true }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/help-\(mode).png", window: help)
                }
                help?.close()
                try? await Task.sleep(for: .seconds(0.4))
            }
            if only == nil || only?.contains("settings") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet }
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one (your terminal, or Claude).
    /// Without it, falls back to drawing the view hierarchy, which leaves
    /// sidebars and glass blank.
    private static func capture(to path: String, window: NSWindow? = nil) {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        // Active, like a window someone is using: real accent colors and focus rings.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}
