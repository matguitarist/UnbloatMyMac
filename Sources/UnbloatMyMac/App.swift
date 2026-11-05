import AppKit
import SwiftUI
import UnbloatMyMacKit

// UnbloatMyMac
//   UnbloatMyMac                      the app, changing this Mac
//   APP_STORE=<file> UnbloatMyMac     a pretend Mac (MockBackend) with its journal in <file>; never touches the system
//   APP_SNAPSHOT=<dir> UnbloatMyMac   save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 UnbloatMyMac           with APP_STORE: a pretend Mac with some tweaks on and some staged (tools/snap.sh)
//   UnbloatMyMac --selftest           run the self-test on a pretend Mac and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> UnbloatMyMac      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 UnbloatMyMac           draw the 8 pt grid and the layout probes over the window

/// The app. Main (CLI.swift) starts it unless the command line tool runs.
struct UnbloatMyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(engine: Store.makeEngine(), installer: Store.makeInstaller())

    var body: some Scene {
        Window("UnbloatMyMac", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1080, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                    .disabled(!Updater.shared.isAvailable)
                Button("Install Command Line Tool…") { Task { await model.installCommandLineTool() } }
            }
            CommandGroup(replacing: .importExport) {
                Button("Export Tweaks…") { model.exportWithPanel() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Import Tweaks…") { model.importWithPanel() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandMenu("Changes") {
                Button("Review Changes…") { model.review() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.staged.isEmpty || model.isBusy)
                Button("Discard Changes") { model.discard() }
                    .keyboardShortcut(.delete, modifiers: [.command, .option])
                    .disabled(model.staged.isEmpty)
                Divider()
                Menu("Add Preset") {
                    ForEach(Array(Catalog.presets.enumerated()), id: \.element.id) { index, preset in
                        Button(preset.title) { model.stage(preset) }
                            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option])
                    }
                }
                Divider()
                Button("Refresh") { Task { await model.refresh(); await model.refreshApps() } }
                    .keyboardShortcut("r")
                Button("Install Recommended Apps") { model.sidebar = .apps; Task { await model.install(model.missingRecommended) } }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .disabled(model.apps.homebrew == nil || model.missingRecommended.isEmpty || !model.appsWorking.isEmpty)
                Button("Undo Everything…") { model.sidebar = .history; model.confirmUndoAll = true }
                    .keyboardShortcut("z", modifiers: [.command, .option])
                    .disabled(model.applied.isEmpty && model.launchItemsDisabledByApp.isEmpty)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        _ = Updater.shared
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where the undo journal lives: ~/Library/Application Support/UnbloatMyMac/journal.json.
/// With APP_STORE set, the app runs on a pretend Mac and never changes the system.
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, self-test).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var folder: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "UnbloatMyMac", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return folder.appending(path: "journal.json")
    }

    static func makeInstaller() -> AppInstaller {
        if isOverridden {
            let env = ProcessInfo.processInfo.environment
            return AppInstaller(packages: MockPackageManager(seeded: env["APP_SEED"] == "1", homebrew: env["APP_NO_BREW"] != "1"))
        }
        return AppInstaller(packages: Homebrew())
    }

    static func makeEngine() -> Engine {
        if isOverridden {
            let seeded = ProcessInfo.processInfo.environment["APP_SEED"] == "1"
            return Engine(backend: MockBackend(seeded: seeded), journalURL: url)
        }
        return Engine(backend: MacBackend(supportFolder: folder), journalURL: url)
    }
}
