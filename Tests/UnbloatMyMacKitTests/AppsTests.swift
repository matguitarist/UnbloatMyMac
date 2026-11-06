import Foundation
import Testing
@testable import UnbloatMyMacKit

@Test("Recommended app ids are unique and shell lines are guarded")
func appsCatalogIsConsistent() {
    let ids = Catalog.apps.map(\.id)
    #expect(Set(ids).count == ids.count)
    for app in Catalog.apps {
        if let line = app.shellLine { #expect(line.hasPrefix("command -v "), "\(app.id) runs even when uninstalled") }
        if app.kind == .formula { #expect(app.bundle == nil) }
    }
}

@Test("Adding and removing shell lines leaves the rest of ~/.zshrc as it was")
func shellBlockRoundTrip() throws {
    let original = "export PATH=\"$HOME/bin:$PATH\"\nalias ll='ls -l'\n"
    let posh = try #require(Catalog.app("oh-my-posh"))
    let zoxide = try #require(Catalog.app("zoxide"))

    let one = ShellBlock.setting(posh, on: true, in: original)
    #expect(one.hasPrefix(original))
    #expect(ShellBlock.enabled(in: one) == ["oh-my-posh"])

    let two = ShellBlock.setting(zoxide, on: true, in: one)
    #expect(ShellBlock.enabled(in: two) == ["oh-my-posh", "zoxide"])
    #expect(ShellBlock.setting(zoxide, on: true, in: two) == two, "adding twice changes nothing")

    let back = ShellBlock.setting(posh, on: false, in: ShellBlock.setting(zoxide, on: false, in: two))
    #expect(back == original)
}

@Test("Text after the block survives")
func shellBlockKeepsTextAfter() throws {
    let posh = try #require(Catalog.app("oh-my-posh"))
    let withBlock = ShellBlock.setting(posh, on: true, in: "a\n") + "b\n"
    #expect(ShellBlock.setting(posh, on: false, in: withBlock) == "a\nb\n")
}

@Test("Installing adds the shell line, uninstalling removes both")
func installAndUninstall() throws {
    let packages = MockPackageManager()
    let installer = AppInstaller(packages: packages)
    let fzf = try #require(Catalog.app("fzf"))
    try installer.install(fzf)
    var state = installer.state()
    #expect(state.states["fzf"] == .installed)
    #expect(state.inShell == ["fzf"])
    try installer.uninstall(fzf)
    state = installer.state()
    #expect(state.states["fzf"] == .notInstalled)
    #expect(state.inShell.isEmpty)
    #expect(packages.readShellFile() == "export PATH=\"$HOME/bin:$PATH\"\n")
}

@Test("Without Homebrew nothing installs, and apps already in Applications show as installed")
func noHomebrew() throws {
    let installer = AppInstaller(packages: MockPackageManager(seeded: true, homebrew: false))
    #expect(installer.state().homebrew == nil)
    #expect(installer.state().states["iina"] == .installedElsewhere)
    #expect(throws: BackendError.self) { try installer.install(#require(Catalog.app("bat"))) }
}

@Test("A failed install keeps ~/.zshrc as it was")
func failedInstall() throws {
    let packages = MockPackageManager()
    packages.fail("oh-my-posh")
    let installer = AppInstaller(packages: packages)
    #expect(throws: BackendError.self) { try installer.install(#require(Catalog.app("oh-my-posh"))) }
    #expect(installer.state().inShell.isEmpty)
}

@Test("Updates list only catalog apps Homebrew installed, and updating clears them")
func appUpdates() throws {
    let packages = MockPackageManager(seeded: true)
    let installer = AppInstaller(packages: packages)
    #expect(installer.outdated() == ["bat"])
    packages.markOutdated("not-in-catalog")
    #expect(installer.outdated() == ["bat"])
    try installer.upgrade(#require(Catalog.app("bat")))
    #expect(installer.outdated().isEmpty)
    let none = AppInstaller(packages: MockPackageManager(seeded: true, homebrew: false))
    #expect(none.outdated().isEmpty)
}

@Test("On Apple silicon Vorssaint replaces the apps it covers; on Intel they stay recommended")
func allInOneReplaces() throws {
    let vorssaint = try #require(Catalog.app("vorssaint"))
    let altTab = try #require(Catalog.app("alt-tab"))
    #expect(vorssaint.isRecommended(appleSilicon: true))
    #expect(!altTab.isRecommended(appleSilicon: true))
    #expect(!vorssaint.isRecommended(appleSilicon: false))
    #expect(altTab.isRecommended(appleSilicon: false))
    for app in Catalog.apps {
        if let other = app.replacedBy { #expect(Catalog.app(other) != nil, "\(app.id) names \(other)") }
    }
}

@Test("Local AI apps are listed, and Apple silicon apps are hidden on Intel")
func localAI() {
    let ai = Catalog.apps.filter { $0.group == .ai }
    #expect(ai.count >= 10)
    #expect(ai.allSatisfy { !$0.isRecommended() }, "Install Recommended never pulls in AI apps")
    #expect(Catalog.appsHere.count == Catalog.apps.filter { !$0.appleSiliconOnly || RecommendedApp.isAppleSilicon }.count)
}

@Test("App updaters are listed, and macCurrent opens its website instead of Homebrew")
func appUpdaters() throws {
    let updaters = Catalog.apps.filter { $0.group == .updates }
    #expect(updaters.count >= 5)
    let current = try #require(Catalog.app("maccurrent"))
    #expect(current.isRecommended() && !current.installsWithHomebrew && current.brewCommand == nil && current.bundle != nil)
    for app in Catalog.apps where !app.installsWithHomebrew { #expect(app.bundle != nil, "\(app.id) needs a bundle to show it is installed") }
    #expect(Catalog.app("topgrade")?.brewCommand == "brew install topgrade")
    #expect(Catalog.app("latest")?.brewCommand == "brew install --cask latest")
}

@Test("Cleaners are listed with Mole starred, and AppCleaner moved there")
func cleaners() throws {
    let cleaners = Catalog.apps.filter { $0.group == .cleaners }
    #expect(cleaners.count >= 6)
    #expect(Catalog.app("mole")?.isRecommended() == true)
    #expect(Catalog.app("appcleaner")?.group == .cleaners)
}
