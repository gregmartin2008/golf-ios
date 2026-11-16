#!/bin/bash
# Builds the app with Xcode and leaves a short summary of the result in out/.
# usage: ci_xcodebuild.sh sim|device
set -uo pipefail
kind="$1"
mkdir -p out build
# The bundle identifier the app is built with. An install tool may change it when it signs the
# app; building with the id the tool will use (App/bundle-id.txt, or CADDIE_BUNDLE_ID) keeps
# the build and the installed app the same.
bundle_id="${CADDIE_BUNDLE_ID:-$(tr -d '[:space:]' < App/bundle-id.txt)}"
bundle_id="${bundle_id:-app.caddie.golf}"
if [ "$kind" = sim ]; then
  simulator=$(scripts/ci_simulator.sh)
  echo "simulator: $simulator" | tee out/simulator.txt
  destination="platform=iOS Simulator,name=$simulator"
  configuration=Debug
  # Signed "to run locally" (no certificate needed), so the simulator build can use the Keychain.
  signing=(CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO)
else
  destination='generic/platform=iOS'
  configuration=Release
  # Left unsigned: the installer (iloader) signs it with the owner's Apple ID.
  signing=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=)
fi
xcodebuild -project Caddie.xcodeproj -scheme Caddie -configuration "$configuration" \
  -destination "$destination" -derivedDataPath "build/$kind" -clonedSourcePackagesDirPath build/spm \
  -skipPackagePluginValidation -skipMacroValidation \
  "${signing[@]}" PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" \
  build > "build/$kind.log" 2>&1
status=$?
grep -E "error:|warning: unre|BUILD (SUCCEEDED|FAILED)" "build/$kind.log" | sort -u | head -300 > "out/$kind-build.log"
grep -A7 "error:" "build/$kind.log" | head -800 > "out/$kind-errors.log" || true
grep -E "^/.*(App/Sources|CaddieCore).*warning:" "build/$kind.log" | sort -u | head -150 > "out/$kind-warnings.log" || true
tail -40 "build/$kind.log" | cut -c1-300 > "out/$kind-tail.log"
cat "out/$kind-build.log"
exit $status
