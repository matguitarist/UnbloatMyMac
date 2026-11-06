#!/bin/zsh
# Builds a notarized release zip and the Sparkle appcast, then prints the publish command.
# Usage: tools/release.sh 0.1.0
# Needs once: a "Developer ID Application" certificate in the keychain, and
#   xcrun notarytool store-credentials UnbloatMyMac --apple-id <id> --team-id <team>
set -euo pipefail
version=${1:?usage: tools/release.sh <version>}
here=${0:A:h:h}
name=UnbloatMyMac
profile=${NOTARY_PROFILE:-UnbloatMyMac}
dist="$here/dist"
app="$dist/$name.app"
zip="$dist/$name-$version.zip"

identity=$(security find-identity -v -p codesigning | grep -m1 '"Developer ID Application: ' | awk '{print $2}')
[[ -n "$identity" ]] || { echo "No Developer ID Application certificate in the keychain."; exit 1; }
[[ -z "$(git -C "$here" status --porcelain)" ]] || { echo "Commit your changes first."; exit 1; }

# The version goes into Info.plist.in, so the build and the tag agree.
sed -i '' -E "s|(<key>CFBundleShortVersionString</key><string>)[^<]*|\1$version|" "$here/Info.plist.in"

# Build and install with build.sh, then copy the bundle and sign it for distribution.
"$here/build.sh"
rm -rf "$dist" && mkdir -p "$dist"
ditto "$HOME/Applications/$name.app" "$app"
# Sparkle's helpers first, inside out, then the app (Sparkle's documented order).
sparkle="$app/Contents/Frameworks/Sparkle.framework"
if [[ -d "$sparkle" ]]; then
  sign() { codesign --force --options runtime --timestamp --sign "$identity" "$@"; }
  sign "$sparkle/Versions/B/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
  sign "$sparkle/Versions/B/Autoupdate"
  sign "$sparkle/Versions/B/Updater.app"
  sign "$sparkle"
fi
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --strict --verbose=2 "$app"

ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
spctl --assess --type execute --verbose "$app"
rm "$zip" && ditto -c -k --keepParent "$app" "$zip"
shasum -a 256 "$zip"

# The update feed. The app reads releases/latest/download/appcast.xml.
sparkle_bin="$HOME/Library/Developer/$name/build/artifacts/sparkle/Sparkle/bin"
if grep -q "__SPARKLE_PUBLIC_KEY__" "$here/Info.plist.in"; then
  echo "No Sparkle key yet (tools/sparkle-keys.sh): skipping appcast.xml."
else
  "$sparkle_bin/generate_appcast" --download-url-prefix "https://github.com/matguitarist/UnbloatMyMac/releases/download/v$version/" "$dist"
fi

git -C "$here" commit -qam "Release $version" || true
git -C "$here" tag -a "v$version" -m "$name $version"
echo "Built $zip"
assets=("$zip"); [[ -f "$dist/appcast.xml" ]] && assets+=("$dist/appcast.xml")
# Not a draft: Sparkle reads releases/latest, which skips drafts, and the repo
# must stay public for the feed and the zip to download.
echo "Next: git push --follow-tags && gh release create v$version ${assets[*]} --generate-notes --title '$name $version'"
