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
PLIST="$REPO/Cue/Info.plist"

if [ ! -f "$PLIST" ]; then
    echo "warning: $PLIST not found — skipping the build number stamp."
    exit 0
fi

if plutil -replace CFBundleVersion -string "$CI_BUILD_NUMBER" "$PLIST"; then
    echo "CFBundleVersion set to $CI_BUILD_NUMBER"
else
    echo "warning: could not stamp CFBundleVersion — continuing anyway."
fi

exit 0
