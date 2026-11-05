import Foundation
import UnbloatMyMacKit

/// The command line tool. The app binary runs it when the first argument is a command:
///   unbloatmymac list [--json]
///   unbloatmymac status [--json]
///   unbloatmymac apply <id>... [--yes] [--dry-run] [--json]
///   unbloatmymac undo <id>... [--yes] [--dry-run] [--json]
///   unbloatmymac preset <recommended|privacy|performance|windows> [--yes] [--dry-run] [--json]
///   unbloatmymac presets [--json]
///   unbloatmymac revert [--yes] [--json]          undo everything
///   unbloatmymac export <file>
///   unbloatmymac import <file> [--yes] [--dry-run] [--json]
/// Changes ask "Apply? [y/N]" in a terminal; scripts pass --yes. Exit codes:
/// 0 ok, 1 some changes failed, 2 bad usage, 3 declined.
enum CLI {
    static let commands: Set<String> = ["list", "status", "apply", "undo", "preset", "presets", "revert",
                                        "export", "import", "help", "--help", "-h", "--version"]

    static func shouldRun(_ arguments: [String]) -> Bool {
        arguments.count > 1 && commands.contains(arguments[1])
    }

    private struct Options {
        var json = false
        var yes = false
        var dryRun = false
        var words: [String] = []
    }

    static func run(_ arguments: [String]) -> Int32 {
        var options = Options()
        for word in arguments.dropFirst(2) {
            switch word {
            case "--json": options.json = true
            case "--yes", "-y": options.yes = true
            case "--dry-run", "-n": options.dryRun = true
            default: options.words.append(word)
            }
        }
        let engine = Store.makeEngine()
        switch arguments[1] {
        case "list": return list(engine, options)
        case "status": return status(engine, options)
        case "presets": return presets(engine, options)
        case "apply", "undo":
            let on = arguments[1] == "apply"
            guard !options.words.isEmpty else { return usage("\(arguments[1]) needs one or more tweak ids. See: unbloatmymac list") }
            let unknown = options.words.filter { id in !engine.tweaks.contains { $0.id == id } }
            guard unknown.isEmpty else { return usage("Unknown tweak: \(unknown.joined(separator: ", ")). See: unbloatmymac list") }
            let current = engine.state()
            var changes: [String: Bool] = [:]
            for id in options.words where current.statuses[id]?.isAvailable == true && current.statuses[id]?.isOn != on {
                changes[id] = on
            }
            return change(engine, changes, options)
        case "preset":
            guard let id = options.words.first, let preset = Catalog.presets.first(where: { $0.id == id }) else {
                return usage("preset needs one of: \(Catalog.presets.map(\.id).joined(separator: ", "))")
            }
            let current = engine.state()
            var changes: [String: Bool] = [:]
            for id in preset.tweakIDs where current.statuses[id]?.isAvailable == true && current.statuses[id]?.isOn == false {
                changes[id] = true
            }
            return change(engine, changes, options)
        case "revert":
            guard confirm("Undo every change UnbloatMyMac made", options) else { return 3 }
            return finish(engine.undoEverything(), engine, options)
        case "export":
            guard let path = options.words.first else { return usage("export needs a file path") }
            do {
                try engine.exportSet().write(to: URL(fileURLWithPath: path), options: .atomic)
                print("Saved \(path)")
                return 0
            } catch {
                return fail(error.localizedDescription)
            }
        case "import":
            guard let path = options.words.first else { return usage("import needs a file path") }
            do {
                let set = try TweakSet.read(Data(contentsOf: URL(fileURLWithPath: path)))
                return change(engine, engine.changes(for: set), options)
            } catch {
                return fail(error.localizedDescription)
            }
        case "--version":
            print(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
            return 0
        default:
            print(help)
            return 0
        }
    }

    // MARK: Commands

    private static func list(_ engine: Engine, _ options: Options) -> Int32 {
        let state = engine.state()
        if options.json {
            let rows: [[String: Any]] = engine.tweaks.map { tweak in
                ["id": tweak.id, "title": tweak.title, "category": tweak.category.rawValue,
                 "status": name(state.statuses[tweak.id]), "risk": riskName(tweak.risk),
                 "needsAdmin": tweak.needsAdmin, "usesProfile": tweak.usesProfile, "detail": tweak.detail]
            }
            return printJSON(["tweaks": rows])
        }
        for category in TweakCategory.allCases {
            print("\n\(category.title)")
            for tweak in engine.tweaks where tweak.category == category {
                let status = name(state.statuses[tweak.id])
                let flags = [tweak.needsAdmin ? "password" : nil, tweak.usesProfile ? "profile" : nil,
                             tweak.risk == .advanced ? "advanced" : nil].compactMap { $0 }
                let suffix = flags.isEmpty ? "" : "  (\(flags.joined(separator: ", ")))"
                print("  \(pad(status, 11)) \(pad(tweak.id, 30)) \(tweak.title)\(suffix)")
            }
        }
        return 0
    }

    private static func status(_ engine: Engine, _ options: Options) -> Int32 {
        let state = engine.state()
        let applied = engine.tweaks.filter { state.statuses[$0.id]?.isOn == true }.map(\.id)
        let waiting = engine.tweaks.filter { state.statuses[$0.id] == .waiting }.map(\.id)
        if options.json {
            return printJSON(["applied": applied, "appliedByApp": state.applied.sorted(), "waitingForProfile": waiting,
                              "reverted": state.reverted, "macOSUpdated": state.macOSUpdated,
                              "total": engine.tweaks.count])
        }
        print("\(applied.count) of \(engine.tweaks.count) tweaks applied.")
        if !waiting.isEmpty { print("Waiting for approval in System Settings > General > Device Management: \(waiting.joined(separator: ", "))") }
        if !state.reverted.isEmpty { print("Put back by macOS\(state.macOSUpdated ? " after an update" : ""): \(state.reverted.joined(separator: ", ")). Run: unbloatmymac apply \(state.reverted.joined(separator: " "))") }
        return 0
    }

    private static func presets(_ engine: Engine, _ options: Options) -> Int32 {
        if options.json {
            return printJSON(["presets": Catalog.presets.map { ["id": $0.id, "title": $0.title, "summary": $0.summary, "tweaks": $0.tweakIDs] }])
        }
        for preset in Catalog.presets {
            print("\(pad(preset.id, 12)) \(preset.title): \(preset.summary)")
        }
        return 0
    }

    private static func change(_ engine: Engine, _ changes: [String: Bool], _ options: Options) -> Int32 {
        guard !changes.isEmpty else {
            if options.json { return printJSON(["changed": 0, "failures": [String: String]()]) }
            print("Nothing to change.")
            return 0
        }
        let tweaks = engine.tweaks.filter { changes[$0.id] != nil }
        if options.dryRun || !options.json {
            for tweak in tweaks { print("  \(changes[tweak.id]! ? "apply" : "undo ")  \(pad(tweak.id, 30)) \(tweak.title)") }
            if tweaks.contains(where: \.needsAdmin) { print("  macOS asks for your password once.") }
            if tweaks.contains(where: \.usesProfile) { print("  Approve the profile in System Settings > General > Device Management afterwards.") }
        }
        if options.dryRun { return 0 }
        guard confirm("Make these \(tweaks.count) changes", options) else { return 3 }
        return finish(engine.apply(changes), engine, options)
    }

    private static func finish(_ report: ApplyReport, _ engine: Engine, _ options: Options) -> Int32 {
        if options.json {
            _ = printJSON(["changed": report.changed, "failures": report.failures, "profileHandedOff": report.profileHandedOff,
                           "needsFullDiskAccess": report.needsFullDiskAccess, "needsLogout": report.needsLogout])
        } else {
            print("\(report.changed) changed.")
            for (id, message) in report.failures.sorted(by: { $0.key < $1.key }) { print("  failed \(id): \(message)") }
            if report.profileHandedOff { print("Approve the profile in System Settings > General > Device Management.") }
            if report.needsLogout { print("Log out and back in to finish.") }
        }
        return report.failures.isEmpty ? 0 : 1
    }

    // MARK: Helpers

    private static func confirm(_ question: String, _ options: Options) -> Bool {
        if options.yes { return true }
        guard isatty(STDIN_FILENO) == 1 else {
            FileHandle.standardError.write(Data("Add --yes to change the Mac from a script.\n".utf8))
            return false
        }
        print("\(question)? [y/N] ", terminator: "")
        return ["y", "yes"].contains(readLine()?.lowercased() ?? "")
    }

    private static func name(_ status: TweakStatus?) -> String {
        switch status {
        case .on: "on"
        case .off, nil: "off"
        case .partial: "partial"
        case .waiting: "waiting"
        case .unavailable: "unavailable"
        }
    }

    private static func riskName(_ risk: Risk) -> String {
        switch risk {
        case .safe: "safe"
        case .moderate: "moderate"
        case .advanced: "advanced"
        }
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    private static func printJSON(_ object: Any) -> Int32 {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return 1 }
        print(String(decoding: data, as: UTF8.self))
        return 0
    }

    private static func usage(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 2
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 1
    }

    static let help = """
    unbloatmymac: turn macOS tweaks on and off from the command line.

      list [--json]                 every tweak with its id and status
      status [--json]               what is applied, waiting, or put back by macOS
      apply <id>...                 apply tweaks
      undo <id>...                  undo tweaks, restoring the values from before
      presets [--json]              the presets
      preset <id>                   apply a preset (recommended, privacy, performance, windows)
      revert                        undo everything UnbloatMyMac changed
      export <file>                 save the applied tweaks to a file
      import <file>                 apply the tweaks saved in a file

    Options: --yes (don't ask), --dry-run (show what would change), --json.
    Changes in the app and here share one undo journal.
    """
}

/// Starts the command line tool or the app.
@main
enum Main {
    static func main() {
        if CLI.shouldRun(CommandLine.arguments) {
            setvbuf(stdout, nil, _IOLBF, 0)
            exit(CLI.run(CommandLine.arguments))
        }
        UnbloatMyMacApp.main()
    }
}
