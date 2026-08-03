#!/bin/bash
# Archive and export a signed .ipa locally, for checking that signing and
# packaging work before pushing.
#
#   Tools/release.sh
#
# This does NOT upload. Uploads go through Xcode Cloud, which is the only path
# to TestFlight: push to main, the test suite runs and must pass, the archive
# is delivered to internal testers automatically. Keeping a second upload path
# meant two build-number counters (this one from project.yml, Xcode Cloud's
# from CI_BUILD_NUMBER) issuing numbers for one sequence — which is how a
# build 3 once landed after a build 18.
#
# Signing comes from Signing.xcconfig (gitignored).
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM=$(sed -n 's/^ *DEVELOPMENT_TEAM *= *//p' Signing.xcconfig | tr -d ' \r')
if [ -z "$TEAM" ]; then
    echo "No DEVELOPMENT_TEAM in Signing.xcconfig — copy Signing.xcconfig.example first." >&2
    exit 1
fi

OUT=build/dist
rm -rf "$OUT"
mkdir -p "$OUT"
xcodegen generate

xcodebuild -project Cue.xcodeproj -scheme Cue -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$OUT/OnCue.xcarchive" \
    -allowProvisioningUpdates archive

# uploadSymbols must stay false: with it on, Xcode 26's packaging step dies
# with the entirely unhelpful "error: exportArchive Copy failed" while
# copying the dSYM.
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
    <key>uploadSymbols</key><false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$OUT/OnCue.xcarchive" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -exportPath "$OUT/ipa" \
    -allowProvisioningUpdates

echo "Exported $OUT/ipa/Cue.ipa — not uploaded. Push to main to ship it."
