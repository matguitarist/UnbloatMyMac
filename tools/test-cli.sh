#!/bin/zsh
# Checks the command line tool on a pretend Mac (APP_STORE in /tmp). Exit 0 when every check passes.
set -u
bin=~/Applications/UnbloatMyMac.app/Contents/MacOS/UnbloatMyMac
export APP_STORE=/tmp/UnbloatMyMac-cli.json
rm -f $APP_STORE /tmp/UnbloatMyMac-cli-set.json /tmp/UnbloatMyMac-cli.preferences.json /tmp/UnbloatMyMac-cli-backup.json
fails=0
check() { local name=$1; shift; if "$@" >/dev/null 2>&1; then echo "PASS $name"; else echo "FAIL $name"; fails=$((fails+1)); fi }
json() { $bin "$@" --json; }

check "help prints the commands" sh -c "$bin help | grep -q 'apply <id>'"
check "list --json has every tweak" sh -c "$bin list --json | python3 -c 'import json,sys; assert len(json.load(sys.stdin)[\"tweaks\"]) > 80'"
check "unknown tweak exits 2" sh -c "$bin apply nope.nope; [ \$? -eq 2 ]"
check "apply without --yes from a script is declined" sh -c "$bin apply dock.recents < /dev/null; [ \$? -eq 3 ]"
check "dry run changes nothing" sh -c "$bin apply dock.recents --dry-run | grep -q dock.recents"
check "apply --yes reports one change" sh -c "$bin apply dock.recents --yes --json | python3 -c 'import json,sys; assert json.load(sys.stdin)[\"changed\"] == 1'"
check "a protected setting fails with exit 1" sh -c "$bin apply perf.reduceMotion --yes; [ \$? -eq 1 ]"
check "presets lists windows" sh -c "$bin presets | grep -q windows"
check "preset dry run lists its tweaks" sh -c "$bin preset windows --dry-run | grep -q win.scrolling"
check "export writes a tweak set" sh -c "$bin export /tmp/UnbloatMyMac-cli-set.json && grep -q '\"tweaks\"' /tmp/UnbloatMyMac-cli-set.json"
check "import reads it back" sh -c "$bin import /tmp/UnbloatMyMac-cli-set.json --dry-run"
check "backup saves settings and tweaks" sh -c "$bin backup /tmp/UnbloatMyMac-cli-backup.json && grep -q '\"preferences\"' /tmp/UnbloatMyMac-cli-backup.json"
check "restore with nothing new says so" sh -c "$bin restore /tmp/UnbloatMyMac-cli-backup.json | grep -q 'Nothing to restore'"
check "restore dry run lists a changed setting" sh -c "sed 's/\"accent\" : \"[a-z]*\"/\"accent\" : \"mint\"/' /tmp/UnbloatMyMac-cli-backup.json > /tmp/UnbloatMyMac-cli-set2.json && $bin restore /tmp/UnbloatMyMac-cli-set2.json --dry-run | grep -q 'accent.*mint'"
check "restore --yes sets it" sh -c "$bin restore /tmp/UnbloatMyMac-cli-set2.json --yes && $bin backup /tmp/UnbloatMyMac-cli-backup.json && grep -q mint /tmp/UnbloatMyMac-cli-backup.json"
check "revert --yes exits 0" sh -c "$bin revert --yes"
check "status --json works" sh -c "$bin status --json | python3 -c 'import json,sys; assert \"applied\" in json.load(sys.stdin)'"
check "apps --json lists the recommended apps" sh -c "$bin apps --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"homebrew\"] and any(a[\"id\"]==\"oh-my-posh\" for a in d[\"apps\"])'"
check "install --recommended dry run lists them" sh -c "$bin install --recommended --dry-run | grep -q vorssaint"
check "unknown app exits 2" sh -c "$bin install nope; [ \$? -eq 2 ]"
check "install maccurrent points to its website" sh -c "$bin install maccurrent --yes | grep -q maccurrent.com"
check "install --recommended skips apps not in Homebrew" sh -c "! $bin install --recommended --dry-run | grep -q maccurrent"
check "install --yes exits 0" sh -c "$bin install bat --yes"
check "outdated lists nothing on a fresh pretend Mac" sh -c "$bin outdated --json | python3 -c 'import json,sys; assert json.load(sys.stdin)[\"outdated\"] == []'"
check "update without names exits 2" sh -c "$bin update; [ \$? -eq 2 ]"
check "update --all with nothing to do exits 0" sh -c "$bin update --all --yes"
check "without Homebrew install exits 1" sh -c "APP_NO_BREW=1 $bin install bat --yes; [ \$? -eq 1 ]"

[[ $fails -eq 0 ]] && echo "CLI PASS" || echo "CLI FAIL $fails"
exit $fails
