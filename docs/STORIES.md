# UnbloatMyMac stories

The backlog. Each story has checkable acceptance criteria. The Thimble project
"UnbloatMyMac Roadmap" mirrors the open ones; this file is the source.

## Done (0.1.0 code)

- [x] **S-001 Tweak engine with exact undo.** Every change saves the value from before in `journal.json`; undo restores it. *Check:* `EngineTests` "restores the value from before", "journal survives a relaunch".
- [x] **S-002 Apple Intelligence off, feature by feature.** Writing Tools, Genmoji, Image Playground, Image Wand, ChatGPT, summaries, inline predictions, Siri, and the AI background services. *Check:* profile flow test.
- [x] **S-003 Privacy, Performance, Annoyances, Finder, Dock, Typing tweaks.** 88 tweaks total, no two write the same key. *Check:* `noSharedKeys` test.
- [x] **S-004 Windows Mode.** Scroll direction, F-keys, Home/End, maximize, snap, scroll bars, taskbar Dock, drives on desktop, plus a full preset.
- [x] **S-005 Review before apply.** Changes are staged, listed in a sheet with what happens (password, profile, restarts, log out), then applied. One password prompt for all admin changes. *Check:* `onePrompt` test, review snapshot.
- [x] **S-006 Presets.** Recommended, Maximum Privacy, Performance Boost, Windows Mode. *Check:* self-test "a preset stages only what is not applied".
- [x] **S-007 Background Items.** Stop and allow third-party launch agents and daemons.
- [x] **S-008 Storage cleanup.** Caches, logs, Xcode data, simulators, installers, device updates, local snapshots; files go to the Trash.
- [x] **S-009 History and Undo Everything.** *Check:* `undoEverything` test, self-test.

## 0.1.0 — first public release

- [ ] **S-010 Check every tweak on a real Mac (macOS 27).** Apply and undo each category on a real Mac; each switch shows the right state after Refresh, and undo leaves `defaults read` as before. *Owner.*
- [ ] **S-011 Check the Apple Intelligence profile on macOS 27.** The profile installs from System Settings, the features disappear, removing it brings them back. Note any restriction key macOS ignores. *Owner.*
- [ ] **S-012 Check the password prompt and cancel.** One prompt for several admin tweaks; Cancel reports "You canceled" and changes nothing. *Owner.*
- [x] **S-013 Full Disk Access guidance.** When a protected setting fails, the result offers a button that opens Privacy & Security > Full Disk Access. *Check:* self-test reaches the button on the pretend Mac.
- [x] **S-014 App icon.** A Liquid Glass icon made with Icon Composer, reviewed in light, dark, and tinted looks.
- [x] **S-015 README, license, and screenshots.** README explains what changes, how undo works, and the risks.
- [x] **S-016 CI.** GitHub Actions runs the unit tests on every push.
- [x] **S-017 Release script.** `tools/release.sh <version>` signs with Developer ID and the hardened runtime, notarizes, staples, zips, and drafts a GitHub release.
- [x] **S-018 Notary credentials.** `xcrun notarytool store-credentials UnbloatMyMac` with an app-specific password, so the release script can notarize. *Owner.*
- [ ] **S-019 Publish 0.1.0.** Repo public on GitHub, release with the notarized zip, downloads open without a Gatekeeper warning. *Owner.* Waits on S-010.

## 0.2.0 — next

- [x] **S-030 Command-line tool.** `unbloatmymac status | apply <ids> | undo <ids> | preset <id> | revert`, sent to the running app (agent-cli skill). *Check:* `tools/test-cli.sh`.
- [x] **S-031 Export and import a tweak set.** Save the applied tweaks to a file and apply it on another Mac.
- [x] **S-032 Remove Apple Intelligence models.** Find the model assets on disk, show their size, remove them, and keep them from downloading again. Needs research first.
- [x] **S-033 Login Items list.** Show login items and app background items from the Background Task Manager, not only launch agents.
- [x] **S-034 Re-apply after macOS updates.** Detect a new macOS build that reset tweaks and offer to apply them again.
- [x] **S-035 Automatic updates.** Sparkle feed from GitHub releases. The public key is in `Info.plist.in`, so UnbloatMyMac > Check for Updates… is enabled in installed builds. The first check finds an update once a release carries `appcast.xml` (`tools/release.sh`).
- [x] **S-036 French localization.** Every string in a String Catalog, translated to French.
- [x] **S-037 Safari privacy tweaks.** Search suggestions, preloading, and privacy-preserving ad measurement, written in Safari's container (needs Full Disk Access).
- [x] **S-038 Windows-style Control shortcuts.** Optional key bindings so Control-C, V, X, Z, A work in text like on Windows.
- [x] **S-039 Recommended apps with Homebrew.** A Recommended Apps page lists free apps and tools by group (Windows habits, command line, Mac utilities, privacy), installs one or all recommended with Homebrew, and shows how to get Homebrew when it is missing. *Check:* self-test "Install Recommended installs every starred app", `AppsTests`.
- [x] **S-040 Shell setup for terminal tools.** Oh My Posh, eza, zoxide, and fzf can add one line each to `~/.zshrc` in a marked block; turning one off or uninstalling removes only its line. *Check:* `AppsTests` "Adding and removing shell lines leaves the rest of ~/.zshrc as it was".
- [x] **S-041 Apps from the command line.** `unbloatmymac apps | install <app>… | install --recommended | uninstall <app>…`. *Check:* `tools/test-cli.sh`.
- [x] **S-042 Vorssaint as the all-in-one pick.** On Apple silicon, Vorssaint is recommended instead of AltTab, Rectangle, Maccy, LinearMouse, Stats, MonitorControl, and AppCleaner, which say "Vorssaint does this too". On Intel they stay recommended. *Check:* `AppsTests` "On Apple silicon Vorssaint replaces the apps it covers".
- [x] **S-043 Local AI apps.** A Local AI group lists offline AI apps and tools: Ollama, LM Studio, oMLX, Osaurus, Jan, AnythingLLM, Draw Things, ComfyUI, DiffusionBee, VoiceInk, MacWhisper, llama.cpp, MLX LM, whisper.cpp. None is starred, so Install Recommended never downloads them; Apple silicon only apps are hidden on Intel. *Check:* `AppsTests` "Local AI apps are listed".
- [x] **S-044 App updaters.** An App Updates group lists macCurrent (starred), Updatest, Latest, Applite, topgrade, and mas. macCurrent is not in Homebrew, so its row says Download and opens maccurrent.com, and Install Recommended and `install --recommended` skip it. *Check:* `AppsTests` "App updaters are listed".
- [x] **S-045 Cleaners.** A Cleaners group lists Mole (starred), AppCleaner, Pearcleaner, OnyX, GrandPerspective, OmniDiskSweeper, Czkawka, and dust. AppCleaner and Pearcleaner say "Vorssaint does this too" on Apple silicon. *Check:* `AppsTests` "Cleaners are listed".
- [x] **S-046 Activity Log.** A Tools page lists everything the app and the command line tool did to the Mac: each defaults write with its exact command, each service, profile, command, file, background item, cleanup, and app install. Level chips (Debug, Info, Warning, Error) with counts, a source menu, search, an inspector with the full command, Copy, Export Log…, Clear Log…. Lines are in English, kept in `activity.log` next to the journal, newest 5,000. *Check:* `ActivityLogTests`, self-test "the activity log lists both tweaks", "a refused setting is an error in the activity log", "Clear Log empties the activity log".
- [x] **S-047 Help.** Help > UnbloatMyMac Help (⌘?) opens a window with task-based topics (getting started, tweaks, review, Apple Intelligence, undo, background items, storage, apps, activity log, command line, settings, troubleshooting, shortcuts), in English and French. The Help menu also has Show Activity Log (⌘L), What's New, GitHub, and Report a Problem. *Check:* `help-light.png` and `help-dark.png` snapshots.
- [x] **S-048 Choose the app's language.** Settings > General > Language picks System, English, or Français, independent of macOS, with Restart Now. *Check:* `settings-general` snapshots.
- [x] **S-049 Command line tool menu knows it is installed.** UnbloatMyMac > Install Command Line Tool… becomes Uninstall Command Line Tool… when `/usr/local/bin/unbloatmymac` points at this app; a link to another copy offers Install again.
- [x] **S-050 Review before Install Recommended.** Install N Recommended… and Changes > Install Recommended Apps… (⌥⌘I) open a sheet listing every missing starred app by group, with its description and Homebrew command, each checked. Uncheck any, then Install N Apps; Cancel installs nothing. *Check:* self-test "Install Recommended first lists every missing starred app", `install-light.png` and `install-dark.png` snapshots.
- [x] **S-051 Back up and restore settings.** File > Back Up Settings… (⇧⌘B) and Restore Settings… (⇧⌘R), also in Settings > General > Backup, save one file with the tweaks that are on and the app's own settings (advanced tweaks, restarting apps, accent, language, update checks). Restore sets the settings at once and opens Review for the tweaks; a tweaks-only export restores too. *Check:* `EngineTests` "A settings backup keeps the app's preferences, and a tweaks-only file still reads", self-test "a settings backup holds the app's settings" and "restoring settings opens Review for the backup's tweaks".
