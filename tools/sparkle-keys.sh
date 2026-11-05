#!/bin/zsh
# Creates the EdDSA key that signs updates (kept in your login keychain) and
# puts its public half in Info.plist.in, which turns on automatic updates.
# Run once. Back up the private key: generate_keys -x sparkle-private-key.txt
set -euo pipefail
here=${0:A:h:h}
bin="$HOME/Library/Developer/UnbloatMyMac/build/artifacts/sparkle/Sparkle/bin"
[[ -x "$bin/generate_keys" ]] || { echo "Build once first: ./build.sh"; exit 1; }
"$bin/generate_keys" >/dev/null
key=$("$bin/generate_keys" -p)
sed -i '' "s|<key>SUPublicEDKey</key><string>[^<]*</string>|<key>SUPublicEDKey</key><string>$key</string>|" "$here/Info.plist.in"
echo "Public key $key is in Info.plist.in. Commit it."
