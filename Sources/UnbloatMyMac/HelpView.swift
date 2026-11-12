import AppKit
import SwiftUI

// The Help window (Help > UnbloatMyMac Help): short, task-based topics. Every
// paragraph is a String Catalog key, so it is translated like the rest of
// the app. **Bold** marks the names of buttons, pages, and menus.

enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted, tweaks, review, intelligence, undo, background, storage, apps, log, commandLine, settings, troubleshooting, shortcuts

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .gettingStarted: "Getting Started"
        case .tweaks: "Tweaks and Presets"
        case .review: "Reviewing Changes"
        case .intelligence: "Apple Intelligence"
        case .undo: "Undo and History"
        case .background: "Background Items"
        case .storage: "Storage"
        case .apps: "Recommended Apps"
        case .log: "Activity Log"
        case .commandLine: "Command Line Tool"
        case .settings: "Settings and Language"
        case .troubleshooting: "Troubleshooting"
        case .shortcuts: "Keyboard Shortcuts"
        }
    }

    var symbol: String {
        switch self {
        case .gettingStarted: "flag"
        case .tweaks: "slider.horizontal.3"
        case .review: "checklist"
        case .intelligence: "apple.intelligence"
        case .undo: "clock.arrow.circlepath"
        case .background: "gearshape.2"
        case .storage: "internaldrive"
        case .apps: "shippingbox"
        case .log: "list.bullet.rectangle"
        case .commandLine: "terminal"
        case .settings: "gearshape"
        case .troubleshooting: "wrench.and.screwdriver"
        case .shortcuts: "keyboard"
        }
    }
}

struct HelpView: View {
    static let windowID = "help"
    @State private var selection: HelpTopic? = .gettingStarted

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selection) { topic in
                Label(topic.title, systemImage: topic.symbol).tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)  // room for French titles
        } detail: {
            ScrollView {
                let topic = selection ?? .gettingStarted
                VStack(alignment: .leading, spacing: Space.lg) {
                    Label(topic.title, systemImage: topic.symbol)
                        .font(.largeTitle.bold())
                        .padding(.bottom, Space.xs)
                        .gridProbe("help.title", area: "help")
                    content(for: topic)
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(Space.section)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .gridArea("help", inset: Space.section)
            }
            .id(selection)  // start each topic at the top
        }
        .navigationTitle("UnbloatMyMac Help")
        .noInitialFocus()
    }

    @ViewBuilder
    private func content(for topic: HelpTopic) -> some View {
        switch topic {
        case .gettingStarted:
            HelpText("UnbloatMyMac turns off what you don't use: Apple Intelligence, telemetry, slow animations, pop-ups, and background updaters. Every tweak is optional, shown to you before it applies, and can be undone.")
            HelpSection("Start on the Overview") {
                HelpText("**Overview** shows how much of each category is applied and offers presets. **Recommended** is a safe start: it turns off what most people never use, and nothing that breaks a feature you rely on.")
            }
            HelpSection("Three steps") {
                HelpBullets([
                    "Turn switches off or on. Nothing changes yet: the change waits in the toolbar.",
                    "Click **Review Changes** (⌘Return) to see every change and what it needs: a password, a profile, a restart.",
                    "Click **Apply Changes**. To go back, switch the tweak again, or use **Undo Everything** on the **History** page.",
                ])
            }
            HelpSection("Switches follow System Settings") {
                HelpText("A switch named after a macOS feature, like **Genmoji** or **Siri**, shows that feature. Switch it off to turn the feature off. Other switches, like **Show all file extensions**, are on when the tweak is applied.")
            }

        case .tweaks:
            HelpText("Tweaks are grouped in the sidebar: **Apple Intelligence**, **Privacy**, **Performance**, **Annoyances**, **Finder**, **Dock & Windows**, **Typing**, and **Windows Mode**. Each says what it does, and tags say what it needs.")
            HelpBullets([
                "**Password**: runs a command as administrator. All of them run together under one password prompt.",
                "**Profile**: needs your approval in System Settings.",
                "**Stops a service**: a background service is disabled for your account. It fully stops after you log out.",
                "**Restarts Dock** or **Finder**: the screen may flicker once.",
                "**Advanced**: stops system services, and some features stop working until you undo it. Hidden unless you turn them on in **Settings > General**.",
            ])
            HelpSection("What a tweak changes") {
                HelpText("Click **ⓘ** next to a tweak's name to see the exact commands it runs, such as **defaults write**, and how undo puts each one back. **Copy Commands** copies them.")
            }
            HelpSection("Presets") {
                HelpText("**Recommended**, **Maximum Privacy**, **Performance Boost**, and **Windows Mode** stage a set of tweaks at once. They only stage what is not applied yet, and you still review before anything changes. Find them on the **Overview** and in **Changes > Add Preset**.")
            }
            HelpSection("Back up, or move to another Mac") {
                HelpText("**File > Export Tweaks…** saves the tweaks that are on to a file. On the other Mac, **File > Import Tweaks…** stages the ones that are not on yet, for review.")
                HelpText("**File > Back Up Settings…** (⇧⌘B) saves the tweaks that are on and UnbloatMyMac’s own settings: advanced tweaks, restarting apps, the accent, the language, and update checks. **File > Restore Settings…** (⇧⌘R) sets those back at once and opens Review for the tweaks. Both are also in **Settings > Backup**.")
            }

        case .review:
            HelpText("Switches only stage changes. The toolbar counts them, and the sidebar shows a badge on each category with changes waiting.")
            HelpText("**Review Changes** lists every change with what will happen: a password prompt, a profile to approve, a Dock or Finder restart, or a log out. **Apply Changes** makes them all; **Discard** (⌥⌘Delete) forgets them.")
            HelpText("Each change has a menu. Pick **Leave On** or **Leave Off** to keep a setting as it is, for example when another app already manages it; only the other changes apply.")
            HelpSection("After applying") {
                HelpText("Most changes show at once. Some take effect in apps you open from now on, or after you log out; the review says which. To see Dock, Finder, and menu bar changes only after logging out, turn off **Restart the Dock, Finder, and menu bar after applying** in **Settings**.")
            }

        case .intelligence:
            HelpText("Apple Intelligence features are turned off with a configuration profile, the same way a company manages its Macs. UnbloatMyMac puts every Apple Intelligence restriction in one profile.")
            HelpBullets([
                "After **Apply Changes**, macOS asks you to approve the profile in **System Settings > General > Device Management**. Until then, the switches say **Approve in System Settings**.",
                "Changing these switches later replaces the profile, and macOS asks again.",
                "Switching them all back on removes the profile, which asks for your password.",
            ])
            HelpText("The background model services are separate tweaks that stop launch agents; they are marked **Advanced**.")

        case .undo:
            HelpText("Before UnbloatMyMac changes a setting, it saves the value that was there. Undo puts back that exact value, not a guess.")
            HelpBullets([
                "Switch a single tweak back and apply to undo it.",
                "**History** lists every change with its time, and failures with their reason.",
                "**Undo Everything…** (⌥⌘Z) puts back every setting, starts stopped services again, allows background items again, and removes the profile.",
            ])
            HelpSection("After a macOS update") {
                HelpText("A macOS update can put some settings back. The **Overview** then lists the tweaks that were reset, with **Review and Apply Again** and **Keep as Is**.")
            }
            HelpText("The saved values are in **journal.json**. **Settings > General > Show in Finder** shows it.")

        case .background:
            HelpText("Updaters and helpers that other apps start at login and keep running, like Google Updater or Adobe's helpers. Switch one off to stop it; switch it on to bring it back.")
            HelpText("Items for every user (daemons) ask for your password. **Show Login Items…** reads the login items and app background items listed in System Settings; that also needs your password. Turn those on or off in **System Settings > General > Login Items & Extensions**.")

        case .storage:
            HelpText("**Storage** measures caches, logs, Xcode data, old installers, iPhone and iPad updates, and Time Machine local snapshots. **Clean** moves files to the Trash, so you can still get them back.")
            HelpText("Simulators and local snapshots cannot go to the Trash: they are deleted at once, and the page says so before. Some items open their page in System Settings instead.")
            HelpText("**Leftovers from Deleted Apps** lists settings and data in your Library named after apps that are no longer installed and that nothing changed in 30 days. **Review…** (⌥⌘L) shows each one with its size; items from a developer who still has an app installed start unchecked. **Privacy Traces** clear the download history macOS keeps and the Recent Items lists.")

        case .apps:
            HelpText("Free apps and tools that do a job better than macOS does, grouped by need. A star marks the pick in each group.")
            HelpBullets([
                "**Install** uses Homebrew. If Homebrew is missing, the page shows how to install it.",
                "**Install Recommended Apps** (⌥⌘I) shows every starred app that is missing, each checked; uncheck any you do not want, then click Install.",
                "Apps that are only on their website show **Download** and open it.",
                "When Homebrew has a newer version of an app it installed, its row shows **Update**, and **Update N Apps** updates them all. **Changes > Check for App Updates** (⌥⌘U) asks Homebrew for the latest versions first. Apps that update themselves are left to do so.",
                "Terminal tools like Oh My Posh or zoxide can add their line to ~/.zshrc, inside a block UnbloatMyMac marks and removes again.",
            ])
            HelpText("Nothing installs until you click.")

        case .log:
            HelpText("The **Activity Log** lists everything UnbloatMyMac did to your Mac, line by line: each setting it wrote, each service it stopped, each command it ran, each file it changed, and each app it installed, from the app and from the command line tool.")
            HelpBullets([
                "**Debug**, **Info**, **Warning**, and **Error** show or hide each level; the number is how many lines it has. Debug lines are hidden at first.",
                "The **Source** menu shows one part of the Mac, like **Preferences** or **Commands**. Search finds words in the message and the command.",
                "Select a line to see the exact command or value in the inspector. **Copy Command** in the line's menu copies it.",
                "**Copy** and ⌘C copy the selected lines as text; **Export Log…** saves the whole log, to attach to a bug report.",
            ])
            HelpText("Lines are in English, like Console, so they read the same in a bug report. The log keeps the latest 5,000 lines in **activity.log**, next to the journal. **Clear Log…** deletes them; it does not undo anything.")

        case .commandLine:
            HelpText("**UnbloatMyMac > Install Command Line Tool…** adds **unbloatmymac** to /usr/local/bin. It shares the undo journal and the activity log with the app.")
            HelpBullets([
                "**unbloatmymac list** and **status**: every tweak and whether it is on.",
                "**unbloatmymac apply** or **undo** followed by tweak ids, or **preset recommended**.",
                "**unbloatmymac revert**: undo everything.",
                "**unbloatmymac export** and **import**: tweak files, like the File menu.",
                "**unbloatmymac backup** and **restore**: the app's settings and the tweaks that are on, like File > Back Up Settings.",
                "**unbloatmymac apps**, **install**, and **uninstall**: recommended apps.",
                "**unbloatmymac outdated** and **update** (an app name, or **--all**): update apps Homebrew installed.",
            ])
            HelpText("Changes ask for confirmation in a terminal; scripts add **--yes**. **--dry-run** shows what would change, and **--json** prints results for scripts.")

        case .settings:
            HelpText("Open **Settings** with ⌘Comma.")
            HelpBullets([
                "**General**: the app's language, advanced tweaks, restarting the Dock and Finder after applying, and a notification at login when macOS puts back tweaks.",
                "**Appearance**: light or dark mode, and the accent color.",
                "**Updates**: automatic update checks, the version, and **Check Now**.",
                "**Backup**: back up and restore settings, and where the undo journal is kept.",
            ])
            HelpSection("Language") {
                HelpText("UnbloatMyMac is in English and French. It follows your Mac's language unless you pick one in **Settings > General > Language**. The new language applies after **Restart Now**.")
            }

        case .troubleshooting:
            HelpQuestion("A setting did not change") {
                HelpText("Open the **Activity Log** and show **Error** lines: each says what macOS refused. Some settings, like Reduce Motion, need **Full Disk Access**: add UnbloatMyMac in **System Settings > Privacy & Security > Full Disk Access**, then apply again.")
            }
            HelpQuestion("Apple Intelligence switches say Approve in System Settings") {
                HelpText("The profile is waiting for you. Open **System Settings > General > Device Management**, double-click the UnbloatMyMac profile, and click **Install**.")
            }
            HelpQuestion("A service is still running") {
                HelpText("Stopped services fully stop after you log out and back in.")
            }
            HelpQuestion("A tweak came back after a macOS update") {
                HelpText("The **Overview** lists tweaks macOS put back. Click **Review and Apply Again**.")
            }
            HelpQuestion("I want everything back the way it was") {
                HelpText("**Changes > Undo Everything…** (⌥⌘Z). Then delete the app; nothing else stays behind but its folder in ~/Library/Application Support.")
            }
            HelpQuestion("Reporting a problem") {
                HelpText("**Help > Report a Problem…** opens a new issue on GitHub. Attach the log from **File > Export Activity Log…**.")
            }

        case .shortcuts:
            HelpShortcuts(rows: [
                ("⌘Return", "Review Changes"),
                ("⌥⌘Delete", "Discard Changes"),
                ("⌥⌘1 – ⌥⌘4", "Add a preset"),
                ("⌘R", "Refresh"),
                ("⌥⌘I", "Install Recommended Apps…"),
                ("⌥⌘U", "Check for App Updates"),
                ("⌥⌘L", "Review Leftovers from Deleted Apps…"),
                ("⇧⌥⌘U", "Update All Apps"),
                ("⌥⌘Z", "Undo Everything"),
                ("⇧⌘E", "Export Tweaks"),
                ("⇧⌘I", "Import Tweaks"),
                ("⇧⌘B", "Back Up Settings"),
                ("⇧⌘R", "Restore Settings"),
                ("⌘L", "Show Activity Log"),
                ("⌥⌘E", "Export Activity Log"),
                ("⌥⌘K", "Clear Activity Log"),
                ("⌃⌘I", "Show or hide the log inspector"),
                ("⌘F", "Search the log"),
                ("⌘,", "Settings"),
                ("⌘?", "UnbloatMyMac Help"),
            ])
        }
    }
}

private struct HelpText: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(2)
    }
}

private struct HelpBullets: View {
    let items: [LocalizedStringKey]
    init(_ items: [LocalizedStringKey]) { self.items = items }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(verbatim: "•").foregroundStyle(.secondary)
                    HelpText(item)
                }
            }
        }
        .padding(.leading, Space.xs)
    }
}

private struct HelpSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content
    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title).font(.title3.bold())
            content
        }
        .padding(.top, Space.xs)
    }
}

/// A troubleshooting question with its answer.
private struct HelpQuestion<Content: View>: View {
    let question: LocalizedStringKey
    @ViewBuilder let content: Content
    init(_ question: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.question = question
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(question).font(.headline)
            content
        }
    }
}

private struct HelpShortcuts: View {
    let rows: [(keys: String, action: LocalizedStringKey)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Space.xxl, verticalSpacing: Space.sm) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(verbatim: row.keys).monospaced().foregroundStyle(.secondary)
                    Text(row.action)
                }
            }
        }
    }
}

/// Help menu items. A view, so it can open windows and reads the model as it changes.
struct HelpCommands: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("UnbloatMyMac Help") { openWindow(id: HelpView.windowID) }
            .keyboardShortcut("?", modifiers: .command)
        Button("Show Activity Log") {
            model.sidebar = .log
            openWindow(id: "main")
        }
        .keyboardShortcut("l")
        Divider()
        Link("What's New", destination: AppLinks.releases)
        Link("UnbloatMyMac on GitHub", destination: AppLinks.repository)
        Link("Report a Problem or Suggest an Idea…", destination: AppLinks.newIssue)
    }
}

enum AppLinks {
    static let repository = URL(string: "https://github.com/matguitarist/UnbloatMyMac")!
    static let releases = URL(string: "https://github.com/matguitarist/UnbloatMyMac/releases")!
    static let newIssue = URL(string: "https://github.com/matguitarist/UnbloatMyMac/issues/new")!
}
