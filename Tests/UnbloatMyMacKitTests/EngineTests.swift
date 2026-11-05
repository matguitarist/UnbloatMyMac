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
