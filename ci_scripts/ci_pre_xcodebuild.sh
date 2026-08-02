#!/bin/sh
# App Store Connect permanently rejects a build number it has already
# accepted. Xcode Cloud numbers its own builds, so use that rather than the
# static value in project.yml, which would collide on the second upload.
set -e

if [ -n "$CI_BUILD_NUMBER" ]; then
    echo "Setting CFBundleVersion to $CI_BUILD_NUMBER"
    plutil -replace CFBundleVersion -string "$CI_BUILD_NUMBER" \
        "$CI_PRIMARY_REPOSITORY_PATH/Cue/Info.plist"
fi
