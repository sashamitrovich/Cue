#!/bin/sh
# Stamp the build number for archives.
#
# App Store Connect permanently rejects a build number it has already
# accepted, so cloud archives take Xcode Cloud's own counter rather than the
# static value in project.yml.
#
# Deliberately cannot fail the build. Xcode Cloud runs this before *every*
# action, including tests, where stamping a version is meaningless — and an
# earlier version of this script exited 1 there and failed the whole Test
# action while the Archive action using the same script succeeded.
set -e

# Nothing to stamp unless this is an archive.
case "${CI_XCODEBUILD_ACTION:-}" in
    archive|archive-app|"") ;;
    *)
        echo "Action is '${CI_XCODEBUILD_ACTION}' — no build number to stamp."
        exit 0
        ;;
esac

if [ -z "${CI_BUILD_NUMBER:-}" ]; then
    echo "No CI_BUILD_NUMBER — leaving CFBundleVersion as it is."
    exit 0
fi

# Prefer the documented repository path, fall back to this script's location.
REPO="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"

# Every bundle in the app, not just the app itself: an embedded extension
# whose CFBundleVersion differs from its parent is rejected at submission
# ("The CFBundleVersion of an app extension must match that of its containing
# parent app").
for PLIST in "$REPO/Cue/Info.plist" "$REPO/CueShare/Info.plist"; do
    if [ ! -f "$PLIST" ]; then
        echo "warning: $PLIST not found — skipping it."
        continue
    fi
    if plutil -replace CFBundleVersion -string "$CI_BUILD_NUMBER" "$PLIST"; then
        echo "CFBundleVersion set to $CI_BUILD_NUMBER in $PLIST"
    else
        echo "warning: could not stamp $PLIST — continuing anyway."
    fi
done

exit 0
