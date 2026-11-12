import Foundation
import Testing
@testable import UnbloatMyMacKit

private func makeEngine() -> (Engine, MockBackend) {
    let backend = MockBackend()
    let url = FileManager.default.temporaryDirectory.appending(path: "journal-\(UUID().uuidString).json")
    return (Engine(backend: backend, journalURL: url), backend)
}

// MARK: Security

@Test("Security tweaks turn on protection, and sharing switches show the feature like System Settings")
func securityTweaks() {
    let ids = Catalog.tweaks.filter { $0.category == .security }.map(\.id)
    #expect(ids == ["security.firewall", "security.stealth", "security.remoteLogin", "security.remoteAppleEvents",
                    "security.airdrop", "security.guest", "security.wakeNetwork"])
    // On means protected for the firewall; on means the door is open for Remote Login.
    #expect(Catalog.tweak("security.firewall")?.namesFeature == false)
    #expect(Catalog.tweak("security.stealth")?.namesFeature == false)
    for id in ["security.remoteLogin", "security.remoteAppleEvents", "security.guest", "security.wakeNetwork"] {
        #expect(Catalog.tweak(id)?.namesFeature == true, "\(id)")
    }
    // Every command needs the password, so they share one prompt.
    let commands = Catalog.tweaks.filter { $0.category == .security && $0.id != "security.airdrop" }
    let allAdmin = commands.allSatisfy { $0.needsAdmin }
    #expect(allAdmin)
}

@Test("Firewall, stealth, and closing sharing share one password prompt, and undo turns them back")
func securityOnePrompt() {
    let (engine, backend) = makeEngine()
    let ids = ["security.firewall", "security.stealth", "security.remoteLogin", "security.guest"]
    let report = engine.apply(Dictionary(uniqueKeysWithValues: ids.map { ($0, true) }))
    #expect(report.failures.isEmpty)
    #expect(backend.adminPrompts == 1)
    let state = engine.state()
    for id in ids { #expect(state.statuses[id] == .on, "\(id)") }
    _ = engine.apply(Dictionary(uniqueKeysWithValues: ids.map { ($0, false) }))
    for id in ids { #expect(engine.state().statuses[id] == .off, "\(id)") }
}

@Test("Security checks report each setting, and a failing one says what to do")
func securityChecks() {
    let (engine, _) = makeEngine()
    let status = engine.securityStatus()
    #expect(Set(status.keys) == Set(Catalog.securityChecks.map(\.id)))
    #expect(status["filevault"] == false && status["gatekeeper"] == true)
    for check in Catalog.securityChecks {
        #expect(!check.problem.isEmpty && check.problem != check.good)
        // Checks run without a password: no sudo, no admin prompt.
        #expect(!check.check.contains("sudo"))
    }
}

@Test("Browser telemetry tweaks write each browser's own policy keys")
func browserTelemetry() {
    let (engine, backend) = makeEngine()
    _ = engine.apply(["privacy.chrome": true, "privacy.firefox": true, "privacy.edge": true])
    #expect(backend.read(PrefKey("com.google.Chrome", "MetricsReportingEnabled")) == .bool(false))
    #expect(backend.read(PrefKey("org.mozilla.firefox", "EnterprisePoliciesEnabled")) == .bool(true))
    #expect(backend.read(PrefKey("org.mozilla.firefox", "DisableTelemetry")) == .bool(true))
    #expect(backend.read(PrefKey("com.microsoft.Edge", "DiagnosticData")) == .int(0))
    _ = engine.apply(["privacy.chrome": false, "privacy.firefox": false, "privacy.edge": false])
    #expect(backend.read(PrefKey("com.google.Chrome", "MetricsReportingEnabled")) == nil)
    #expect(backend.read(PrefKey("org.mozilla.firefox", "EnterprisePoliciesEnabled")) == nil)
}

// MARK: Storage

@Test("Storage targets have unique ids, and each group has some")
func storageTargets() {
    let ids = Catalog.cleanup.map(\.id)
    #expect(Set(ids).count == ids.count)
    for group in CleanupTarget.Group.allCases {
        let has = Catalog.cleanup.contains { $0.group == group }
        #expect(has, "\(group)")
    }
    #expect(Catalog.cleanup.filter(\.isReviewed).map(\.id) == ["leftovers"])
    // Recent Items never touches the Finder sidebar's favorites.
    if case .matching(_, let prefixes)? = Catalog.cleanup.first(where: { $0.id == "recentItems" })?.kind {
        let favorites = prefixes.contains { "com.apple.LSSharedFileList.FavoriteItems.sfl4".hasPrefix($0) }
        let recents = prefixes.contains { "com.apple.LSSharedFileList.RecentDocuments.sfl4".hasPrefix($0) }
        #expect(!favorites && recents)
    } else {
        Issue.record("recentItems is not a matching target")
    }
}

@Test("Web app caches are found only in Chromium app folders, and settings stay")
func chromiumCaches() {
    let tree: [String: [String]] = [
        "/AS": ["Slack", "Notes App", "discord"],
        "/AS/Slack": ["Cache", "Code Cache", "GPUCache", "Local Storage", "Cookies", "storage"],
        "/AS/discord": ["Cache", "GPUCache", "DawnGraphiteCache", "settings.json"],
        // A Cache folder without Chromium's markers is somebody else's data.
        "/AS/Notes App": ["Cache", "Notes.sqlite"],
    ]
    let paths = ChromiumCaches.paths(in: "/AS") { tree[$0] ?? [] }
    #expect(paths == ["/AS/Slack/Cache", "/AS/Slack/Code Cache", "/AS/Slack/GPUCache",
                      "/AS/discord/Cache", "/AS/discord/GPUCache", "/AS/discord/DawnGraphiteCache"])
}

@Test("Bundle ids are read from Library names, and Apple's are never leftovers")
func leftoverNames() {
    #expect(LeftoverFinder.bundleID(fromName: "com.spotify.client.plist") == "com.spotify.client")
    #expect(LeftoverFinder.bundleID(fromName: "com.tinyspeck.slackmacgap.savedState") == "com.tinyspeck.slackmacgap")
    #expect(LeftoverFinder.bundleID(fromName: "us.zoom.xos.binarycookies") == "us.zoom.xos")
    #expect(LeftoverFinder.bundleID(fromName: "com.apple.finder.plist") == nil)
    #expect(LeftoverFinder.bundleID(fromName: "Slack") == nil)
    #expect(LeftoverFinder.bundleID(fromName: "Google Chrome.app") == nil)
    #expect(LeftoverFinder.bundleID(fromName: "group.com.docker") == nil)
    #expect(LeftoverFinder.bundleID(fromName: "UBF8T346G9.Office") == nil)
    #expect(LeftoverFinder.bundleID(fromName: "2.0.1.backup") == nil)
    #expect(LeftoverFinder.bundleID(fromName: "com.foo..bar") == nil)
}

@Test("A leftover belongs to no installed app and sat untouched for 30 days")
func leftoverRules() {
    let installed = LeftoverFinder.Installed(bundleIDs: ["com.google.Chrome", "com.microsoft.Word"])
    let old = Date(timeIntervalSinceNow: -60 * 24 * 3600)
    func find(_ name: String, modified: Date = old, registered: Bool = false) -> Leftover? {
        LeftoverFinder.leftover(path: "/Users/me/Library/Preferences/" + name, installed: installed,
                                registered: { _ in registered }, bytes: 10, modified: modified, ownID: "com.me.unbloat")
    }
    #expect(find("com.spotify.client.plist")?.bundleID == "com.spotify.client")
    #expect(find("com.spotify.client.plist")?.sameDeveloperInstalled == false)
    // An installed app, and its helpers, keep their files.
    #expect(find("com.google.Chrome.plist") == nil)
    #expect(find("com.google.Chrome.helper.plist") == nil)
    // Another app from the same developer: still listed, but flagged.
    #expect(find("com.microsoft.onenote.mac.plist")?.sameDeveloperInstalled == true)
    // LaunchServices knows the app somewhere else on the Mac.
    #expect(find("com.spotify.client.plist", registered: true) == nil)
    // Touched last week: something still uses it.
    #expect(find("com.spotify.client.plist", modified: Date(timeIntervalSinceNow: -7 * 24 * 3600)) == nil)
    // Never this app's own files.
    #expect(find("com.me.unbloat.plist") == nil)
}

@Test("Moving leftovers to the Trash removes them and notes it in History")
func trashLeftovers() {
    let backend = MockBackend(seeded: true)
    let engine = Engine(backend: backend, journalURL: FileManager.default.temporaryDirectory.appending(path: "journal-\(UUID().uuidString).json"))
    let found = engine.leftovers()
    #expect(found.count == 6)
    let spotify = found.filter { $0.bundleID == "com.spotify.client" }
    #expect(engine.trash(spotify) == nil)
    #expect(engine.leftovers().count == 4)
    #expect(engine.state().history.last?.title.contains("1") == true)
    let target = Catalog.cleanup.first { $0.id == "leftovers" }!
    #expect(engine.measure(target).items == 4)
}

@Test("Shared frameworks, tools, and temporary files are never leftovers")
func leftoverFalsePositives() {
    // Found on a real Mac: Sparkle's helper serves many apps, Python and Playwright are not apps.
    #expect(LeftoverFinder.bundleID(fromName: "org.sparkle-project.Sparkle.Autoupdate.plist") == nil)
    #expect(LeftoverFinder.bundleID(fromName: "org.python.python.plist") == nil)
    #expect(LeftoverFinder.bundleID(fromName: "org.webkit.Playwright") == nil)
    #expect(LeftoverFinder.bundleID(fromName: "local.stardew-mod-manager.binarycookies_tmp_32077.dat") == nil)
    #expect(LeftoverFinder.bundleID(fromName: "com.bhprojects.GameBox") == "com.bhprojects.GameBox")
}

@Test("Cache folders are matched to open apps by bundle id, name, bundle name, or executable")
func cacheOwners() {
    let apps = [OpenApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap", pid: 1),
                OpenApp(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode", pid: 2, otherNames: ["Code", "Electron"]),
                OpenApp(name: "Discord", bundleID: "com.hnc.Discord", pid: 3)]
    #expect(OpenApp.owner(of: "com.tinyspeck.slackmacgap", among: apps)?.pid == 1)
    #expect(OpenApp.owner(of: "Slack", among: apps)?.pid == 1)
    #expect(OpenApp.owner(of: "Code", among: apps)?.pid == 2)
    #expect(OpenApp.owner(of: "discord", among: apps)?.pid == 3)
    #expect(OpenApp.owner(of: "Spotify", among: apps) == nil)
}

@Test("App Caches leaves Apple's protected caches alone, so cleaning never fails on them")
func protectedCaches() {
    let caches = Catalog.cleanup.first { $0.id == "caches" }!
    #expect(caches.keeps("com.apple.Safari") && caches.keeps("CloudKit") && caches.keeps("familycircled"))
    #expect(!caches.keeps("com.spotify.client") && !caches.keeps("Homebrew"))
}

@Test("Quit and Clean asks the open apps to quit, then cleans")
func quitAndClean() {
    let (engine, _) = makeEngine()
    let target = Catalog.cleanup.first { $0.id == "chromiumCaches" }!
    let open = engine.openApps(holding: target)
    #expect(open.map(\.name) == ["Slack", "Discord"])
    #expect(engine.clean(target, quitting: open) == nil)
    #expect(engine.openApps(holding: target).isEmpty)
    #expect(engine.measure(target).isEmpty)
}
