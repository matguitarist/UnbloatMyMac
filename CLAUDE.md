# UnbloatMyMac

A native macOS app in SwiftUI that debloats macOS: optional, reversible tweaks
for Apple Intelligence, privacy, performance, annoyances, Finder, the Dock,
typing, and a Windows Mode, plus Background Items, Storage cleanup, and History.

Shared rules for my Mac apps (build and check, design rules, skills, git):
@~/.claude/mac-app-conventions.md

## How changes work (read before adding a tweak)

- Tweaks live in `Sources/UnbloatMyMacKit/Catalog.swift`. An action is a `defaults` value, a launch agent to disable, a profile restriction (Apple Intelligence), a command with its revert and check, or a file.
- `Engine` applies through a `SystemBackend`. Before changing a value it saves the original in `journal.json` (~/Library/Application Support/UnbloatMyMac), and undo restores exactly that.
- Every change also goes to the Activity Log (`activity.log` next to the journal) through `LoggingBackend` in `ActivityLog.swift`; log lines stay in English.
- Admin commands run together under one password prompt. Apple Intelligence restrictions go into one configuration profile that the person approves in System Settings.
- Two tweaks must never write the same key (a unit test checks this).
- Switches follow System Settings: a tweak whose title names a macOS feature (`Catalog.featureTitled`) shows the feature, so off applies the tweak.
- `APP_STORE` set = `MockBackend`, a pretend Mac. Tests, snapshots, and the self-test never touch the real system. Never run the app against the real Mac from a test.

## Adding a recommended app

- Add it to `Catalog.apps` in `Sources/UnbloatMyMacKit/Apps.swift`. The id is the Homebrew token; check it with `brew info --json=v2 <token>`. Use `.cask` with `bundle:`, `.formula` with no bundle, or `.download` with `bundle:` for an app that is only on its website (the row shows Download, and Install Recommended skips it).
- A new group needs a case in `AppGroup`, with a title, summary, and SF Symbol.
- `recommended: true` stars the pick. Use `replacedBy: "vorssaint"` when Vorssaint covers the app, and `appleSiliconOnly:` when it needs Apple silicon.
- Add a French string for every detail, title, and summary in `Localization/Tweaks.xcstrings`; the test "Every library string has a French translation" fails until you do. UI text goes in `Localizable.xcstrings`.
- Add a test in `AppsTests.swift`, a story in `docs/STORIES.md`, the names in the README's Recommended Apps paragraph, and a task in Thimble under the current version heading.

## Layout

- `Sources/UnbloatMyMac/` the app. `App.swift` has the window, menus, and the database location.
- `Sources/UnbloatMyMacKit/` rules and data logic with no SwiftUI. Tests in `Tests/UnbloatMyMacKitTests/`.
- `Package.swift` a Swift package. There is no Xcode project.
- `build.sh` builds, signs, and installs `~/Applications/UnbloatMyMac.app`.
- Release: `tools/release.sh <version>` (settings in `release.conf`, version in `Info.plist.in`). Use the mac-release skill.
- `Icon/AppIcon.icon` the app icon, an Icon Composer file (JSON plus SVG layers). `build.sh` compiles it with `tools/make_icon.sh`; `tools/icon_review.sh` renders every look into one PNG.
- `docs/` the brief, the screen index, and the user stories, when they exist.

## Checks specific to this app

- `APP_SNAPSHOT_MIN=1 tools/snap.sh` shoots the window at its smallest size.
- Never test against the real journal in `~/Library/Application Support/UnbloatMyMac/` or the real Mac.
