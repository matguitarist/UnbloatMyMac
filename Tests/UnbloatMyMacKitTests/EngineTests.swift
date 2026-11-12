import Foundation
import Testing
@testable import UnbloatMyMacKit

private func makeEngine(seeded: Bool = false) -> (Engine, MockBackend) {
    let backend = MockBackend(seeded: seeded)
    let url = FileManager.default.temporaryDirectory.appending(path: "journal-\(UUID().uuidString).json")
    return (Engine(backend: backend, journalURL: url), backend)
}

@Test("Every tweak id is unique and every preset names real tweaks")
func catalogIsConsistent() {
    let ids = Catalog.tweaks.map(\.id)
    #expect(Set(ids).count == ids.count)
    for preset in Catalog.presets {
        for id in preset.tweakIDs { #expect(Catalog.tweak(id) != nil, "\(preset.id) names \(id)") }
    }
}

@Test("No two tweaks write the same setting, so undoing one never breaks another")
func noSharedKeys() {
    var seen: [String: String] = [:]
    for tweak in Catalog.tweaks {
        for case .pref(let key, _) in tweak.actions {
            #expect(seen[key.id] == nil, "\(key) is in \(seen[key.id] ?? "") and \(tweak.id)")
            seen[key.id] = tweak.id
        }
    }
}

@Test("Turning a tweak on and off restores the value from before")
func undoRestoresOriginal() {
    let (engine, backend) = makeEngine()
    let key = PrefKey("com.apple.dock", "autohide-delay")
    _ = backend.write(key, .double(0.5))
    let report = engine.apply(["perf.dockAutohide": true])
    #expect(report.failures.isEmpty)
    #expect(engine.state().statuses["perf.dockAutohide"] == .on)
    #expect(backend.restarted.contains(.dock))
    _ = engine.apply(["perf.dockAutohide": false])
    #expect(backend.read(key) == .double(0.5))
    #expect(backend.read(PrefKey("com.apple.dock", "autohide-time-modifier")) == nil)
    #expect(engine.state().statuses["perf.dockAutohide"] == .off)
}

@Test("Turning off a tweak that was already set before goes back to the macOS default")
func offWithoutHistoryDeletes() {
    let (engine, backend) = makeEngine(seeded: true)
    #expect(engine.state().statuses["finder.extensions"] == .on)
    _ = engine.apply(["finder.extensions": false])
    #expect(backend.read(PrefKey("NSGlobalDomain", "AppleShowAllExtensions")) == nil)
}

@Test("Apple Intelligence restrictions go into one profile that waits for approval")
func profileFlow() {
    let (engine, backend) = makeEngine()
    let report = engine.apply(["ai.genmoji": true, "ai.writingTools": true])
    #expect(report.profileHandedOff)
    #expect(backend.pendingProfile == ["allowGenmoji", "allowWritingTools"])
    #expect(engine.state().statuses["ai.genmoji"] == .waiting)
    backend.approveProfile()
    #expect(engine.state().statuses["ai.genmoji"] == .on)
    // Turning one off hands over a smaller profile; turning the last off removes it.
    _ = engine.apply(["ai.genmoji": false])
    #expect(backend.pendingProfile == ["allowWritingTools"])
    backend.approveProfile()
    _ = engine.apply(["ai.writingTools": false])
    #expect(backend.managedRestrictions().isEmpty)
}

@Test("All admin changes share one password prompt")
func onePrompt() {
    let (engine, backend) = makeEngine()
    _ = engine.apply(["privacy.analytics": true, "perf.powerNap": true, "perf.spotlight": true])
    #expect(backend.adminPrompts == 1)
    #expect(engine.state().statuses["perf.powerNap"] == .on)
}

@Test("Agents missing from this macOS make the tweak unavailable, not broken")
func missingAgent() {
    let (engine, _) = makeEngine()
    #expect(engine.state().statuses["ai.callIntelligence"]?.isAvailable == false)
    #expect(engine.state().statuses["privacy.gameCenter"] == .off)
    _ = engine.apply(["privacy.gameCenter": true])
    #expect(engine.state().statuses["privacy.gameCenter"] == .on)
}

@Test("A protected setting reports a failure with a way out")
func refusedSetting() {
    let (engine, _) = makeEngine()
    let report = engine.apply(["perf.reduceMotion": true])
    #expect(report.failures["perf.reduceMotion"]?.contains("Full Disk Access") == true)
    #expect(!engine.state().applied.contains("perf.reduceMotion"))
}

@Test("Files are backed up and restored")
func fileRestore() {
    let (engine, backend) = makeEngine()
    let path = "~/Library/KeyBindings/DefaultKeyBinding.dict"
    _ = backend.writeFile(path, "{ mine }")
    _ = engine.apply(["win.homeEnd": true])
    #expect(backend.readFile(path)?.contains("moveToBeginningOfLine") == true)
    _ = engine.apply(["win.homeEnd": false])
    #expect(backend.readFile(path) == "{ mine }")
}

@Test("Undo everything turns off what the app changed and restarts stopped items")
func undoEverything() {
    let (engine, backend) = makeEngine()
    _ = engine.apply(["perf.launchAnimation": true, "privacy.ads": true, "finder.library": true])
    let item = backend.launchItems()[0]
    #expect(engine.setLaunchItem(item, disabled: true) == nil)
    _ = engine.undoEverything()
    let state = engine.state()
    #expect(state.applied.isEmpty)
    #expect(state.statuses["privacy.ads"] == .off)
    #expect(state.statuses["finder.library"] == .off)
    #expect(backend.launchItems()[0].isDisabled == false)
}

@Test("The journal survives a relaunch")
func journalPersists() {
    let backend = MockBackend()
    let url = FileManager.default.temporaryDirectory.appending(path: "journal-\(UUID().uuidString).json")
    let key = PrefKey("com.apple.dock", "show-recents")
    _ = backend.write(key, .bool(true))
    _ = Engine(backend: backend, journalURL: url).apply(["dock.recents": true])
    let reopened = Engine(backend: backend, journalURL: url)
    #expect(reopened.state().history.count == 1)
    _ = reopened.apply(["dock.recents": false])
    #expect(backend.read(key) == .bool(true))
}

@Test("Bools stored as numbers count as applied")
func looseMatch() {
    #expect(PrefValue.bool(false).matches(.int(0)))
    #expect(PrefValue.double(0).matches(.int(0)))
    #expect(!PrefValue.bool(true).matches(nil))
}

@Test("The profile is a valid configuration profile")
func profileData() throws {
    let data = try Profile.data(restrictions: ["allowGenmoji"])
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    #expect(plist?["PayloadType"] as? String == "Configuration")
    let content = (plist?["PayloadContent"] as? [[String: Any]])?.first
    #expect(content?["allowGenmoji"] as? Bool == false)
}

@Test("Key binding tweaks share one file and the original comes back")
func sharedKeyBindings() {
    let (engine, backend) = makeEngine()
    let path = Engine.keyBindingsPath
    _ = backend.writeFile(path, "{ mine }")
    _ = engine.apply(["win.homeEnd": true, "win.controlShortcuts": true])
    let file = backend.readFile(path) ?? ""
    #expect(file.contains("moveToBeginningOfLine:") && file.contains("copy:"))
    #expect(engine.state().statuses["win.controlShortcuts"] == .on)
    _ = engine.apply(["win.homeEnd": false])
    #expect(engine.state().statuses["win.homeEnd"] == .off)
    #expect(engine.state().statuses["win.controlShortcuts"] == .on)
    _ = engine.apply(["win.controlShortcuts": false])
    #expect(backend.readFile(path) == "{ mine }")
}

@Test("Safari settings report that Full Disk Access is needed")
func safariNeedsAccess() {
    let (engine, _) = makeEngine()
    let report = engine.apply(["privacy.safariPreload": true])
    #expect(report.needsFullDiskAccess)
}

@Test("The login check tells once about tweaks a macOS update put back")
func revertNoticeOnce() throws {
    let (engine, backend) = makeEngine()
    _ = engine.apply(["dock.recents": true])
    #expect(engine.revertNotice(lastKey: nil) == nil)
    backend.simulateUpdate(resetting: PrefKey("com.apple.dock", "show-recents"))
    let notice = try #require(engine.revertNotice(lastKey: nil))
    #expect(notice.tweaks == ["dock.recents"] && notice.macOSUpdated)
    #expect(engine.revertNotice(lastKey: notice.key) == nil, "already told")
    engine.forgetReverted()
    #expect(engine.revertNotice(lastKey: nil) == nil)
}

@Test("A macOS update that resets a tweak is noticed")
func revertedByUpdate() {
    let (engine, backend) = makeEngine()
    _ = engine.apply(["dock.recents": true, "dock.bounce": true])
    #expect(engine.state().reverted.isEmpty)
    backend.simulateUpdate(resetting: PrefKey("com.apple.dock", "show-recents"))
    let state = engine.state()
    #expect(state.macOSUpdated)
    #expect(state.reverted == ["dock.recents"])
    engine.forgetReverted()
    #expect(engine.state().reverted.isEmpty && !engine.state().macOSUpdated)
}

@Test("A saved tweak set brings the same tweaks to another Mac")
func exportImport() throws {
    let (engine, _) = makeEngine()
    _ = engine.apply(["dock.recents": true, "finder.pathBar": true])
    let set = try TweakSet.read(engine.exportSet())
    #expect(Set(set.tweaks) == ["dock.recents", "finder.pathBar"])
    let (other, _) = makeEngine()
    #expect(other.changes(for: set) == ["dock.recents": true, "finder.pathBar": true])
    #expect(throws: (any Error).self) { try TweakSet.read(Data("{}".utf8)) }
}

@Test("Every tweak can say what it runs and how undo puts it back")
func actionLines() throws {
    for tweak in Catalog.tweaks {
        #expect(!tweak.actions.isEmpty, "\(tweak.id)")
        for action in tweak.actions { #expect(!action.applyLine.isEmpty && !action.undoLine.isEmpty, "\(tweak.id)") }
    }
    #expect(Action.set("com.apple.dock", "show-recents", false).applyLine == "defaults write com.apple.dock show-recents -bool false")
    #expect(Action.set("NSGlobalDomain", "x", 2, currentHost: true).applyLine == "defaults -currentHost write NSGlobalDomain x -int 2")
}

@Test("A settings backup keeps the app's preferences, and a tweaks-only file still reads")
func settingsBackup() throws {
    let (engine, _) = makeEngine()
    _ = engine.apply(["dock.recents": true])
    let preferences = AppPreferences(showAdvanced: true, restartApps: false, accent: "mint", language: "fr", checksForUpdates: true)
    let backup = try TweakSet.read(engine.exportSet(preferences: preferences))
    #expect(backup.preferences == preferences)
    #expect(backup.tweaks == ["dock.recents"])
    #expect(try TweakSet.read(engine.exportSet()).preferences == nil)
    // A file from before backups existed, with no preferences key.
    let old = Data(#"{"app":"UnbloatMyMac","created":"2026-11-01T10:00:00Z","format":1,"tweaks":["finder.pathBar"]}"#.utf8)
    let read = try TweakSet.read(old)
    #expect(read.tweaks == ["finder.pathBar"] && read.preferences == nil)
    // A backup from a later version with only some preferences restores those.
    let partial = Data(#"{"app":"UnbloatMyMac","created":"2026-11-01T10:00:00Z","format":1,"tweaks":[],"preferences":{"accent":"teal"}}"#.utf8)
    #expect(try TweakSet.read(partial).preferences == AppPreferences(accent: "teal"))
}

@Test("Login items are read from sfltool output for this user only")
func parsesLoginItems() {
    let text = """
    ========================
     Records for UID 0 : 00000000
    ========================
     #1:
                     Name: Root Thing
                     Type: daemon (0x10)
              Disposition: [enabled, allowed, visible, notified] (11)
               Identifier: 16.com.root.thing
    ========================
     Records for UID 501 : 1234
    ========================
     #1:
                     Name: Docker Inc
                     Type: developer (0x20)
              Disposition: [enabled, allowed, visible, notified] (11)
               Identifier: Docker Inc
     #2:
                     Name: Docker
           Developer Name: Docker Inc
                     Type: app (0x2)
              Disposition: [disabled, allowed, visible, notified] (10)
               Identifier: 2.com.docker.docker
                      URL: file:///Applications/Docker.app/
    """
    let items = LoginItemParser.parse(text, uid: 501)
    #expect(items.count == 1)
    #expect(items.first?.name == "Docker" && items.first?.kind == "app" && items.first?.isEnabled == false)
}

@Test("Every library string has a French translation")
func libraryStringsTranslated() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../Localization/Tweaks.xcstrings")
    let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let keys = Set((catalog?["strings"] as? [String: Any])?.keys.map { $0 } ?? [])
    var all: [String] = []
    for t in Catalog.tweaks { all += [t.title, t.detail, t.section] + (t.caveat.map { [$0] } ?? []) }
    for c in TweakCategory.allCases { all += [c.title, c.summary] }
    for p in Catalog.presets { all += [p.title, p.summary] }
    for c in Catalog.cleanup { all += [c.title, c.detail] }
    for g in CleanupTarget.Group.allCases { all.append(g.title) }
    for c in Catalog.securityChecks { all += [c.title, c.good, c.problem] }
    for a in Catalog.apps { all.append(a.detail) }
    for g in AppGroup.allCases { all += [g.title, g.summary] }
    for q in SetupQuestion.allCases { all += [q.title, q.detail] + q.options.flatMap { [$0.title, $0.detail] } }
    all += ["Install Homebrew first.", "Could not change ~/.zshrc.", "Homebrew could not finish.",
            "This app is not in Homebrew. Download it from its website.", "Review leftovers one by one.",
            "Only leftovers in your Library folder can be moved to the Trash.", "Cleaned leftovers of %lld deleted apps", "%@ did not quit, so its caches stayed.", "Homebrew did not install this app. Move it to the Trash to remove it.",
            "Cleaned %lld Xcode device support versions", "%@ is protected, so it stayed where it was.", "Disk image", "Installer package", "Not downloaded from the web, so it may be a disk image you made. Look before you pick it.", "%@ makes it again on the next build.", "This project changed in the last week. Your next build would be slower.", "Some items changed since they were listed. Scan again, then review them.", "Cargo’s incremental cache. The next %@ build compiles your own crates once more.", "Builds made with --target %@. Cargo makes them again when you build for it.", "The %@ build. Cargo makes it again when you build it.", "Built in the last month. Building it again takes a while.", "Only folders in Xcode’s DeviceSupport folders can be moved to the Trash."]
    let missing = Set(all).subtracting(keys)
    #expect(missing.isEmpty, "untranslated: \(missing.sorted())")
}

@Test("Every description says what happens with the switch on, so on and off never read backwards")
func descriptionsMatchTheSwitch() {
    // A feature switch shows the feature: its text describes the feature, never turning it off.
    let offWords = ["Stops ", "Turns off", "no longer", "Removes ", "Hides ", "stay "]
    for tweak in Catalog.tweaks where tweak.namesFeature {
        let reads = offWords.filter { tweak.detail.contains($0) }
        #expect(reads.isEmpty, "\(tweak.id): \(tweak.detail)")
    }
}

@Test("Recommended switches point at the unbloated side, and Windows Mode stays a matter of taste")
func recommendedSwitches() {
    #expect(Catalog.tweak("privacy.analytics")?.recommendedSwitch == false)
    #expect(Catalog.tweak("security.firewall")?.recommendedSwitch == true)
    #expect(Catalog.tweak("security.remoteLogin")?.recommendedSwitch == false)
    #expect(Catalog.tweak("finder.extensions")?.recommendedSwitch == true)
    #expect(Catalog.tweak("win.snap")?.recommendedSwitch == nil)
    #expect(Catalog.tweak("typing.autocorrect")?.recommendedSwitch == nil)
    // Advanced tweaks stop system services: no blanket recommendation unless a preset has them.
    #expect(Catalog.tweak("ai.siriServices")?.recommendedSwitch == nil)
}
