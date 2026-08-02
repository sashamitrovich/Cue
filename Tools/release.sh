#!/bin/bash
# Archive, export and (optionally) upload a build to App Store Connect.
#
#   Tools/release.sh                 # archive + export only
#   Tools/release.sh --upload        # ...and upload to App Store Connect
#
# Signing comes from Signing.xcconfig (gitignored). Uploading additionally
# needs an App Store Connect API key: put AuthKey_<KEYID>.p8 in
# ~/.appstoreconnect/private_keys/ and export ASC_KEY_ID and ASC_ISSUER_ID.
#
# Bump CFBundleVersion in project.yml before every upload — App Store Connect
# permanently rejects a build number it has already accepted.
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

# Build numbers come from one place: the highest App Store Connect has
# already accepted, plus one. project.yml and Xcode Cloud's CI_BUILD_NUMBER
# are separate counters that interleave — a local upload numbered below a
# cloud build looks like it went backwards, and App Store Connect requires
# the number to increase for a submission.
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then
    NEXT=$(python3 Tools/next_build_number.py) || exit 1
    echo "Stamping CFBundleVersion $NEXT (next after the highest already uploaded)"
    plutil -replace CFBundleVersion -string "$NEXT" Cue/Info.plist
fi

xcodebuild -project Cue.xcodeproj -scheme Cue -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$OUT/OnCue.xcarchive" \
    -allowProvisioningUpdates archive

# uploadSymbols must stay false: with it on, Xcode 26's packaging step dies
# with the entirely unhelpful "error: exportArchive Copy failed" while
# copying the dSYM. Symbols can be uploaded separately from Organizer.
cat > "$OUT/ExportOptions.plist" <<EOF
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
EOF

xcodebuild -exportArchive \
    -archivePath "$OUT/OnCue.xcarchive" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -exportPath "$OUT/ipa" \
    -allowProvisioningUpdates

IPA="$OUT/ipa/Cue.ipa"
echo "Exported $IPA"

if [ "${1:-}" = "--upload" ]; then
    : "${ASC_KEY_ID:?set ASC_KEY_ID}" "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
    # Validate first — a rejected upload still burns the build number.
    xcrun altool --validate-app -f "$IPA" -t ios \
        --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
    xcrun altool --upload-app -f "$IPA" -t ios \
        --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
    echo "Uploaded as build $(plutil -extract CFBundleVersion raw Cue/Info.plist)."
fi

# Cue/Info.plist is tracked, and the stamp above edited it. Regenerate so the
# working tree isn't left dirty with a number that means nothing locally.
xcodegen generate >/dev/null
