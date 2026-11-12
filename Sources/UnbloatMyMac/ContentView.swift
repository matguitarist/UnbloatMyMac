import AppKit
import SwiftUI
import UnbloatMyMacKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            sidebar
        } detail: {
            page(model.sidebar ?? .overview)
                .toolbar { toolbar }
        }
        .sheet(isPresented: $model.showReview) {
            ReviewSheet()
                .environment(model)
                .themed()
        }
        .sheet(item: Binding(get: { model.confirmInstall.map(InstallList.init) },
                             set: { model.confirmInstall = $0?.apps })) { list in
            InstallRecommendedSheet(apps: list.apps)
                .environment(model)
                .themed()
        }
        .sheet(item: Binding(get: { model.leftoversToReview.map(LeftoverList.init) },
                             set: { model.leftoversToReview = $0?.items })) { list in
            LeftoversSheet(items: list.items)
                .environment(model)
                .themed()
        }
        .alert("UnbloatMyMac", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
        .confirmationDialog("Undo everything UnbloatMyMac changed?", isPresented: $model.confirmUndoAll) {
            Button("Undo Everything", role: .destructive) { Task { await model.undoEverything() } }
        } message: {
            Text("Every setting goes back to the value it had before, stopped services start again, and the Apple Intelligence profile is removed. You may be asked for your password.")
        }
        .confirmationDialog("Clear the activity log?", isPresented: $model.confirmClearLog) {
            Button("Clear Log", role: .destructive) { model.clearLog() }
        } message: {
            Text("Every line is deleted. Your changes and their undo history are kept.")
        }
        // The command line tool may have changed the Mac while the app was in the background.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in becameActive() }
        .task {
            await model.refresh()
            await model.refreshApps()
            SeedData.stageIfRequested(model: model)
            await model.reloadLog()
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings, openWindow: openWindow)
        }
    }

    private func becameActive() {
        model.reloadPreferences()
        if model.hasLoaded, !model.isBusy { Task { await model.refresh(); await model.refreshApps() } }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(selection: $model.sidebar) {
            Label(SidebarItem.overview.title, systemImage: SidebarItem.overview.symbol)
                .tag(SidebarItem.overview)
            Section("Tweaks") {
                ForEach(TweakCategory.allCases, id: \.self) { category in
                    let item = SidebarItem.category(category)
                    Label(item.title, systemImage: item.symbol)
                        .badge(model.pendingCount(in: category))
                        .tag(item)
                }
            }
            Section("Tools") {
                ForEach(SidebarItem.tools) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
    }

    @ViewBuilder
    private func page(_ item: SidebarItem) -> some View {
        switch item {
        case .overview: OverviewPage()
        case .category(let category): TweakPage(category: category)
        case .background: BackgroundPage()
        case .storage: StoragePage()
        case .apps: AppsPage()
        case .history: HistoryPage()
        case .log: LogPage()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if !model.staged.isEmpty {
            ToolbarItem {
                Button("Discard", systemImage: "arrow.uturn.backward") { model.discard() }
                    .help("Forget the changes you have not applied (Option-Command-Delete)")
            }
            ToolbarItem {
                Button {
                    model.review()
                } label: {
                    model.staged.count == 1 ? Text("Review 1 Change") : Text("Review \(model.staged.count) Changes")
                }
                .buttonStyle(.borderedProminent)
                .help("See and apply your changes (Command-Return)")
                .disabled(model.isBusy)
            }
        }
        ToolbarItem {
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh(); await model.refreshApps() } }
                .help("Read the current settings again (Command-R)")
        }
    }
}

/// Seed mode for snapshots: stage a few changes so the toolbar and review sheet show.
enum SeedData {
    static func stageIfRequested(model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1", Store.isOverridden else { return }
        model.staged = ["ai.writingTools": true, "ai.chatgpt": true, "perf.windowAnimations": true,
                        "privacy.analytics": true, "win.scrolling": true]
        seedLog(model.log)
    }

    /// A morning of activity for the Activity Log snapshots.
    private static func seedLog(_ log: ActivityLog?) {
        guard let log, log.entries().count < 5 else { return }
        log.add(.debug, .tweaks, "Applying 3 changes", detail: "on  finder.extensions\non  dock.recents\non  ai.genmoji")
        log.add(.info, .settings, "Set NSGlobalDomain AppleShowAllExtensions to true", detail: "defaults write NSGlobalDomain \"AppleShowAllExtensions\" -bool true")
        log.add(.info, .settings, "Set com.apple.dock show-recents to false", detail: "defaults write com.apple.dock \"show-recents\" -bool false")
        log.add(.info, .profile, "Handed the Apple Intelligence profile to System Settings for approval", detail: "allowGenmoji\nallowImagePlayground")
        log.add(.info, .tweaks, "Applied finder.extensions", detail: "Show all file extensions")
        log.add(.info, .tweaks, "Applied dock.recents", detail: "Hide recent apps in the Dock")
        log.add(.info, .tweaks, "Applied ai.genmoji", detail: "Genmoji")
        log.add(.warning, .profile, "Waiting for approval in System Settings > General > Device Management")
        log.add(.debug, .app, "Restarted Dock, Finder")
        log.add(.info, .services, "Stopped com.apple.Siri.agent", detail: "launchctl disable gui/<uid>/com.apple.Siri.agent")
        log.add(.error, .settings, "macOS refused to change com.apple.universalaccess reduceMotion", detail: "defaults write com.apple.universalaccess \"reduceMotion\" -bool true")
        log.add(.error, .tweaks, "Could not apply perf.reduceMotion", detail: "UnbloatMyMac needs Full Disk Access to change this setting.")
        log.add(.warning, .settings, "Some settings need Full Disk Access for UnbloatMyMac")
        log.add(.info, .background, "Stopped background item com.google.keystone.agent", detail: "~/Library/LaunchAgents/com.google.keystone.agent.plist")
        log.add(.info, .storage, "Cleaned caches")
        log.add(.info, .apps, "Installed Stats", detail: "brew install --cask stats")
        log.add(.info, .apps, "Added zoxide to ~/.zshrc", detail: "eval \"$(zoxide init zsh)\"")
    }
}
