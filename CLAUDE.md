# UnbloatMyMac

A native macOS app in SwiftUI that debloats macOS: optional, reversible tweaks
for Apple Intelligence, privacy, performance, annoyances, Finder, the Dock,
typing, and a Windows Mode, plus Background Items, Storage cleanup, and History.

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
- `Icon/AppIcon.icon` the app icon, an Icon Composer file (JSON plus SVG layers). `build.sh` compiles it with `tools/make_icon.sh`; `tools/icon_review.sh` renders every look into one PNG.
- `docs/` the brief, the screen index, and the user stories, when they exist.

## Build and check

- Build and install: `./build.sh`. Add `--open` to restart the app with the new build. The build shows warnings; fix them.
- Unit tests: `swift test --scratch-path ~/Library/Developer/UnbloatMyMac/test-build`.
- Self-test (the app's real functions on a /tmp store): `tools/selftest.sh`. Exit 0 when every check passes. Add a check for every story with logic in `SelfTest.swift`.
- After every UI change, take snapshots with sample data and look at them: `tools/snap.sh`.
  It writes `/tmp/UnbloatMyMac-shots/<page>-light.png` and `-dark.png` for every sidebar page, and `settings-<tab>-light.png` and `-dark.png` for every Settings tab, then quits. `APP_SNAPSHOT_PAGES=all,settings tools/snap.sh` limits the pages.
  For a panel, sheet, or popover, add a capture to `Snapshot.swift` like the Settings loop.
- Snapshots, seed data, and the self-test refuse to run without `APP_STORE` in /tmp.
- Never test against the real journal in `~/Library/Application Support/UnbloatMyMac/` or the real Mac.
- Then check the grid: `tools/grid-lint.sh` and `swift tools/check-layout.swift /tmp/UnbloatMyMac-shots/*-layout.json`. Both print PASS.
- A change is done when the build has no errors, the grid checks pass, and you looked at the light and dark snapshots.

## Design rules

- Use Apple's controls and system styles. Only the accent color is custom: `UI/Theme.swift` (`ThemeStore.defaultID`). People change it, and light or dark mode, in Settings > Appearance.
- Views use `.tint`, `Palette.accent`, `Palette.accentText` (accent-colored text), and `Palette.onAccent` (text on an accent fill). Never hard-code colors, radii, or durations in views.
- Compare accents: add `APP_ACCENT=<id>` to the snapshot command.
- Spacing comes from `Space` in `UI/Grid.swift`, on a 4 pt grid. Mark custom pages and cards with `.gridArea` and `.gridProbe`.
- Windows open calm: `.noInitialFocus()` on every window and sheet (no focus ring or selected text on open), `.fitsContent()` on sheets and Settings tabs (no scroll bar with nothing to scroll). System scroll bars. Both in `UI/WindowBehavior.swift`.
- Settings: one tab per topic in `SettingsView.swift`, one grouped Form per tab. Add a case to `SettingsTab` for a new tab.
- Window chrome (title bar, toolbar, sidebar, menus, sheets) stays system. Buttons use system styles, like `.borderedProminent`.
- Colors: `.primary`, `.secondary`, `.tint`, and system colors. Never fixed grays or white for text.
- Every action has a menu bar item and a keyboard shortcut.
- `Label` for icon and text pairs. SF Symbols for icons.
- `ContentUnavailableView` for empty states.
- Liquid Glass belongs to floating controls only, never to content.

## Skills

The bama plugin has a skill for each step: `mac-design` (design rules),
`design-system` (accent and tokens), `layout-grid`, `ux-design`,
`swift-swiftui`, `os-integrations`, `performance`, `build-and-verify`,
`test-mac-app`, `app-icon`, `user-stories`, and `improve-loop`. Use them.

## Git

- Commit after each working change, with a message that says what the user can now do.
