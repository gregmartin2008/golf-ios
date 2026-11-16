#!/bin/bash
# Wraps the device build as an .ipa that can be installed with iloader, which signs it with the
# installer's own Apple ID. With --release, publishes it as the repository's "latest" release.
set -euo pipefail
app="build/device/Build/Products/Release-iphoneos/Caddie.app"
test -d "$app"
rm -rf build/ipa && mkdir -p build/ipa/Payload
cp -R "$app" build/ipa/Payload/
(cd build/ipa && zip -qry Caddie.ipa Payload)
{
  echo "size: $(du -h build/ipa/Caddie.ipa | cut -f1)"
  echo "sha256: $(shasum -a 256 build/ipa/Caddie.ipa | cut -d' ' -f1)"
  echo "commit: ${GITHUB_SHA:-local}"
  echo "architectures: $(lipo -archs "$app/Caddie")"
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" -c "Print :MinimumOSVersion" \
    -c "Print :NSLocationWhenInUseUsageDescription" "$app/Info.plist"
} | tee out/ipa.txt

if [ "${1:-}" = "--release" ]; then
  notes="Unsigned build of Caddie for iPhone (iOS 26 or later), from commit ${GITHUB_SHA:0:7}. Install Caddie.ipa with iloader; see the README."
  gh release delete latest --cleanup-tag -y 2>/dev/null || true
  gh release create latest build/ipa/Caddie.ipa --target "$GITHUB_SHA" --title "Caddie for iPhone" --notes "$notes"
  echo "released" | tee -a out/ipa.txt
fi
