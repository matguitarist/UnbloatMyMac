#!/bin/zsh
# Lists interface strings with no French translation. Exit 0 when none is missing.
# Interface strings come from the compiler; library strings (Tweaks table) from L("...")
# calls and the catalog, checked by EngineTests "every library string is translated".
set -u
here=${0:A:h:h}
tmp=$(mktemp -d)
swift build --package-path "$here" --scratch-path "$HOME/Library/Developer/UnbloatMyMac/l10n-build" \
  -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$tmp" >/dev/null 2>&1
rm -f "$tmp"/{Backend,Catalog,Engine,MacBackend,Model,CLI}.stringsdata
echo '{"sourceLanguage":"en","strings":{},"version":"1.0"}' > "$tmp/x.xcstrings"
xcrun xcstringstool sync "$tmp/x.xcstrings" --stringsdata "$tmp"/*.stringsdata
python3 -I - "$tmp/x.xcstrings" "$here/Localization/Localizable.xcstrings" <<'PY'
import json, sys
found = set(json.load(open(sys.argv[1]))["strings"])
have = {k for k, v in json.load(open(sys.argv[2]))["strings"].items() if "fr" in v.get("localizations", {})}
missing = sorted(found - have)
for key in missing: print("MISSING", repr(key))
print("L10N PASS" if not missing else f"L10N FAIL {len(missing)} missing")
sys.exit(1 if missing else 0)
PY
