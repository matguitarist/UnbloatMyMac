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
    #expect(Catalog.cleanup.filter(\.isReviewed).map(\.id) == ["leftovers", "oldInstallers", "deviceSupport", "buildArtifacts"])
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

@Test("Xcode device support names are read with and without a device, and anything else is left alone")
func deviceSupportNames() {
    #expect(DeviceSupportFinder.parse("iPhone12,8 27.2 (24B119)")! == ("iPhone12,8", "27.2", "24B119"))
    #expect(DeviceSupportFinder.parse("17.0 (21A329) arm64e")! == (nil, "17.0", "21A329"))
    #expect(DeviceSupportFinder.parse("Watch7,3 12.2.1 (23S60)")! == ("Watch7,3", "12.2.1", "23S60"))
    #expect(DeviceSupportFinder.parse("Logs") == nil)
    #expect(DeviceSupportFinder.parse("Backup of iPhone 27.2 (24B119)") == nil)
    #expect(DeviceSupportFinder.platform(ofFolder: "~/Library/Developer/Xcode/watchOS DeviceSupport") == "watchOS")
}

@Test("The newest device support version of each device is kept, by version and then by build")
func deviceSupportNewest() {
    func v(_ device: String?, _ version: String, _ build: String, _ platform: String = "iOS") -> DeviceSupportVersion {
        DeviceSupportVersion(path: "/\(platform)/\(device ?? "") \(version) (\(build))", platform: platform, device: device,
                             version: version, build: build, bytes: 1_000, modified: .now)
    }
    let versions = [v("iPhone15,2", "27.2", "24B119"), v("iPhone15,2", "27.10", "24K10"), v("iPhone15,2", "27.9", "24J5"),
                    v("iPhone15,2", "27.10", "24K12"), v("iPhone12,8", "27.2", "24B119"), v("Watch7,3", "12.2", "23S41", "watchOS")]
    let kept = DeviceSupportFinder.newest(versions)
    #expect(kept == ["/iOS/iPhone15,2 27.10 (24K12)", "/iOS/iPhone12,8 27.2 (24B119)", "/watchOS/Watch7,3 12.2 (23S41)"])
    let size = DeviceSupportFinder.size(of: versions)
    #expect(size.items == 3 && size.kept == 3 && size.bytes == 3_000)
    #expect(DeviceSupportFinder.grouped(versions).first { $0.group == "iOS · iPhone15,2" }?.versions.first?.build == "24K12")
}

@Test("Moving device support versions to the Trash notes it in History, and the newest stay")
func trashDeviceSupport() {
    let engine = Engine(backend: MockBackend(seeded: true), journalURL: FileManager.default.temporaryDirectory.appending(path: "journal-\(UUID().uuidString).json"))
    let found = engine.deviceSupport()
    let kept = DeviceSupportFinder.newest(found)
    #expect(engine.trash(deviceSupport: found.filter { !kept.contains($0.path) }) == nil)
    #expect(Set(engine.deviceSupport().map(\.path)) == kept)
    #expect(engine.state().history.last?.title.contains("2") == true)
    let target = Catalog.cleanup.first { $0.id == "deviceSupport" }!
    #expect(engine.measure(target).isEmpty && engine.measure(target).kept == 2)
}

@Test("Protected places never move to the Trash, and what the cleanups move is allowed")
func protectedPaths() {
    let home = "/Users/me"
    func reason(_ path: String) -> String? { ProtectedPaths.reason(for: path, home: home) }
    for path in ["/Users/me", "/Users/me/", "/Users/me/Library", "/Users/me/Library/Caches", "/Users/me/Documents",
                 "/Users/me/Library/Keychains/login.keychain-db", "/Users/me/Library/Mobile Documents/com~apple~CloudDocs",
                 "/Users/me/Library/Mail/V10", "/Users/me/.ssh/id_ed25519", "/Users/me/Library/Application Support/MobileSync/Backup",
                 "/Users/me/Library/Group Containers/group.com.apple.notes", "/Users/me/Pictures/Photos Library.photoslibrary",
                 "/Users/me/Developer/app/../../Library", "/System/Library/Caches", "/Applications", "/usr/local/bin/tool"] {
        #expect(reason(path) != nil, "\(path) should be protected")
    }
    for path in ["/Users/me/Library/Caches/com.spotify.client", "/Users/me/Library/Application Support/com.spotify.client",
                 "/Users/me/Downloads/Docker.dmg", "/Users/me/Developer/app/node_modules", "/Users/me/.npm/_cacache/index-v5",
                 "/Users/me/Library/Developer/Xcode/DerivedData/App-abc", "/Applications/Install macOS Tahoe.app",
                 "/Users/me/Library/Group Containers/UBF8T346G9.Office"] {
        #expect(reason(path) == nil, "\(path) should be allowed")
    }
}

@Test("Old installers: big, a day old, not open, and suggested only when downloaded")
func installerRules() {
    let old = Date(timeIntervalSinceNow: -3 * 24 * 3600)
    func item(_ name: String, bytes: Int64 = 100_000_000, modified: Date = old, downloaded: Bool = true, mounted: Set<String> = []) -> ReviewItem? {
        InstallerFinder.item(path: "/Users/me/Downloads/" + name, folder: "~/Downloads", bytes: bytes, modified: modified,
                             downloaded: downloaded, mounted: mounted)
    }
    #expect(item("Docker.dmg")?.suggested == true)
    #expect(item("Zoom.PKG")?.suggested == true)
    #expect(item("Backup.dmg", downloaded: false)?.suggested == false)
    #expect(item("Small.dmg", bytes: 5_000_000) == nil)
    #expect(item("Today.dmg", modified: .now) == nil)
    #expect(item("Notes.zip") == nil)
    #expect(item("Open.dmg", mounted: ["/Users/me/Downloads/Open.dmg"]) == nil)
    let info = "================================================\nimage-path      : /Users/me/Downloads/Open.dmg\nimage-alias     : /Users/me/Downloads/Open.dmg\n"
    #expect(InstallerFinder.mounted(fromHdiutil: info) == ["/Users/me/Downloads/Open.dmg"])
    #expect(InstallerFinder.folders == ["~/Downloads", "~/Desktop"])
}

@Test("Build folders are found only beside their tool's file, and recent projects are not suggested")
func buildArtifactRules() {
    let tree: [String: [String]] = [
        "/D": ["web", "rust", "notes", ".hidden", "app"],
        "/D/web": ["package.json", "node_modules", "src"],
        "/D/web/node_modules": ["left-pad"],
        "/D/web/node_modules/left-pad": ["package.json", "node_modules"],
        "/D/web/src": ["index.js"],
        "/D/rust": ["Cargo.toml", "target", "src"],
        "/D/rust/target": ["debug"],
        "/D/rust/src": [],
        // A folder named target without Cargo.toml is somebody's data.
        "/D/notes": ["target", "build"],
        "/D/notes/target": ["plan.md"],
        "/D/notes/build": ["x"],
        "/D/.hidden": ["package.json", "node_modules"],
        "/D/.hidden/node_modules": [],
        "/D/app": ["App.xcodeproj", "DerivedData"],
        "/D/app/DerivedData": ["Build"],
    ]
    let found = BuildArtifactFinder.find(in: "/D") { tree[$0] }
    #expect(found.map(\.path).sorted() == ["/D/app/DerivedData", "/D/rust/target", "/D/web/node_modules"])
    let rule = BuildArtifactFinder.rules[0]
    let recent = BuildArtifactFinder.item(path: "/D/web/node_modules", project: "/Users/me/Developer/web", rule: rule, bytes: 1,
                                          projectChanged: .now, home: "/Users/me")
    #expect(!recent.suggested && recent.note != nil && recent.group == "~/Developer/web")
    let old = BuildArtifactFinder.item(path: "/D/web/node_modules", project: "/D/web", rule: rule, bytes: 1,
                                       projectChanged: Date(timeIntervalSinceNow: -30 * 24 * 3600))
    #expect(old.suggested)
}

@Test("Reviewed items move to the Trash and the row counts what is left")
func trashReviewItems() {
    let engine = Engine(backend: MockBackend(seeded: true), journalURL: FileManager.default.temporaryDirectory.appending(path: "journal-\(UUID().uuidString).json"))
    let target = Catalog.cleanup.first { $0.id == "buildArtifacts" }!
    let found = engine.reviewItems(target)
    #expect(engine.trash(found.filter(\.suggested), from: target) == nil)
    #expect(engine.reviewItems(target).count == 3)
    #expect(engine.measure(target).isEmpty && engine.measure(target).kept == 3)
}

@Test("A Rust target lists each build and incremental cache, and a part inside a picked folder counts once")
func cargoParts() {
    let tree: [String: [String]] = [
        "/P": ["Cargo.toml", "target"],
        "/P/target": ["CACHEDIR.TAG", "debug", "ship", "aarch64-apple-darwin", "tmp"],
        "/P/target/debug": ["deps", "incremental"], "/P/target/debug/deps": [], "/P/target/debug/incremental": [],
        "/P/target/ship": ["deps"], "/P/target/ship/deps": [],
        "/P/target/aarch64-apple-darwin": ["debug"], "/P/target/aarch64-apple-darwin/debug": ["incremental"],
        "/P/target/aarch64-apple-darwin/debug/incremental": [], "/P/target/tmp": [],
    ]
    let parts = BuildArtifactFinder.cargoParts(in: "/P/target") { tree[$0] }
    #expect(parts.map(\.path) == ["/P/target/aarch64-apple-darwin", "/P/target/aarch64-apple-darwin/debug/incremental",
                                  "/P/target/debug", "/P/target/debug/incremental", "/P/target/ship"])
    #expect(BuildArtifactFinder.cargoTarget(of: "/P/target/debug/incremental") { tree[$0] } == "/P/target")
    #expect(BuildArtifactFinder.cargoTarget(of: "/P/target/debug/deps") { tree[$0] } == nil)

    let month = Date(timeIntervalSinceNow: -40 * 24 * 3600)
    let cache = BuildArtifactFinder.cargoItem(path: "/P/target/debug/incremental", part: .incremental(profile: "debug"),
                                              project: "/P", bytes: 10, lastBuilt: .now)
    let fresh = BuildArtifactFinder.cargoItem(path: "/P/target/ship", part: .build("ship"), project: "/P", bytes: 20, lastBuilt: .now)
    let old = BuildArtifactFinder.cargoItem(path: "/P/target/aarch64-apple-darwin", part: .build("aarch64-apple-darwin"),
                                            project: "/P", bytes: 30, lastBuilt: month)
    #expect(cache.suggested && !fresh.suggested && old.suggested && cache.name == "target/debug/incremental")

    let whole = ReviewItem(path: "/P/target", group: "/P", name: "target", detail: "", bytes: 100, modified: .now, suggested: true)
    #expect(ReviewItem.outermost([whole, cache, old]).map(\.path) == ["/P/target"])
    #expect(ReviewItem.size(of: [whole, cache, fresh]).bytes == 100)
}

@Test("Added project folders are searched once each, written with ~, and Library or hidden folders are refused")
func projectFolders() {
    let home = "/Users/me"
    #expect(BuildArtifactFinder.abbreviate("/Users/me/Documents/Rust/", home: home) == "~/Documents/Rust")
    #expect(BuildArtifactFinder.abbreviate("/Volumes/Work/code", home: home) == "/Volumes/Work/code")
    let roots = BuildArtifactFinder.searchRoots(adding: ["/Users/me/Documents/Rust", "~/Developer", "/Volumes/Work/code"], home: home)
    #expect(roots.filter { $0 == "~/Developer" }.count == 1)
    #expect(roots.suffix(2) == ["~/Documents/Rust", "/Volumes/Work/code"])
    #expect(BuildArtifactFinder.refusal(forFolder: "/Users/me/Library/Caches", home: home) != nil)
    #expect(BuildArtifactFinder.refusal(forFolder: "/Users/me/.cargo", home: home) != nil)
    #expect(BuildArtifactFinder.refusal(forFolder: "/System/Library", home: home) != nil)
    #expect(BuildArtifactFinder.refusal(forFolder: "/Users/me/Documents/Rust", home: home) == nil)
}

@Test("A project in an added folder is found only once that folder is searched")
func addedProjectFolder() {
    let engine = Engine(backend: MockBackend(seeded: true), journalURL: FileManager.default.temporaryDirectory.appending(path: "journal-\(UUID().uuidString).json"))
    let target = Catalog.cleanup.first { $0.id == "buildArtifacts" }!
    #expect(!engine.reviewItems(target).contains { $0.group.hasPrefix("~/Documents") })
    engine.projectFolders = ["~/Documents/Rust"]
    #expect(engine.reviewItems(target).contains { $0.group == "~/Documents/Rust/Parser" })
}
