import AppKit
import SwiftUI
import UnbloatMyMacKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

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
        // The command line tool may have changed the Mac while the app was in the background.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if model.hasLoaded, !model.isBusy { Task { await model.refresh() } }
        }
        .task {
            await model.refresh()
            SeedData.stageIfRequested(model: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
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
                ForEach([SidebarItem.background, .storage, .history]) { item in
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
        case .history: HistoryPage()
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
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
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
    }
}
