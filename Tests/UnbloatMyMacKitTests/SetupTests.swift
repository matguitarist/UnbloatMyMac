import Foundation
import Testing
@testable import UnbloatMyMacKit

@Test("Set Up for Me only stages tweaks that exist, and never an advanced one")
func setupStagesKnownSafeTweaks() {
    let everything = SetupAnswers([.intelligence: false, .siri: false, .code: true, .windows: true, .privacy: true, .speed: false])
    for id in everything.tweakIDs {
        let tweak = Catalog.tweak(id)
        #expect(tweak != nil, "\(id) is not in the catalog")
        #expect((tweak?.risk ?? .advanced) < .advanced, "\(id) stops a system service")
    }
}

@Test("Someone who uses Apple Intelligence and Siri keeps both")
func setupKeepsFeaturesInUse() {
    let answers = SetupAnswers([.intelligence: true, .siri: true, .privacy: true])
    #expect(!answers.tweakIDs.contains { $0.hasPrefix("ai.") })
    #expect(answers.tweakIDs.contains("privacy.analytics"), "maximum privacy still stops analytics")
    #expect(answers.tweakIDs.contains("privacy.siriImprove"), "recordings stay off Apple’s servers either way")
}

@Test("The suggested answers give the Recommended preset with Apple Intelligence and Siri off")
func setupDefaults() {
    let ids = Set(SetupAnswers().tweakIDs)
    #expect(ids.isSuperset(of: Catalog.preset("recommended")))
    #expect(ids.contains("ai.siri"))
    #expect(!ids.contains("perf.windowAnimations"), "animations stay unless asked")
    #expect(!ids.contains("win.scrolling"))
    #expect(SetupAnswers().appIDs().isEmpty)
    #expect(!SetupAnswers().wantsCommandLineTools)
}

@Test("A developer gets Finder and typing fixes, Terminal tools, and the Command Line Tools")
func setupDeveloper() {
    let answers = SetupAnswers([.code: true])
    #expect(Set(answers.tweakIDs).isSuperset(of: ["finder.hidden", "typing.quotes", "typing.dashes"]))
    #expect(answers.appIDs().contains("zoxide"))
    #expect(answers.wantsCommandLineTools)
}

@Test("Windows habits bring Vorssaint on Apple silicon and the single apps on Intel")
func setupWindowsApps() {
    let answers = SetupAnswers([.windows: true])
    #expect(answers.appIDs(appleSilicon: true) == ["vorssaint"])
    let intel = answers.appIDs(appleSilicon: false)
    #expect(intel.contains("alt-tab") && intel.contains("rectangle") && !intel.contains("vorssaint"))
    #expect(Set(answers.tweakIDs).isSuperset(of: Catalog.preset("windows")))
}

@Test("Answers survive being saved and read back")
func setupAnswersRoundTrip() throws {
    let answers = SetupAnswers([.code: true, .speed: false])
    let back = try JSONDecoder().decode(SetupAnswers.self, from: JSONEncoder().encode(answers))
    #expect(back == answers)
    #expect(back[.privacy] == SetupQuestion.privacy.suggested)
}
