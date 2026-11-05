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
