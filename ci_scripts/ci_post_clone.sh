#!/bin/sh
# Xcode Cloud runs this immediately after cloning, before it looks for the
# project. Cue.xcodeproj is generated from project.yml and deliberately not
# committed, so without this the build fails with "Project Cue.xcodeproj does
# not exist at the root of the repository".
set -e

echo "Installing XcodeGen…"
brew install xcodegen

cd "$CI_PRIMARY_REPOSITORY_PATH"
echo "Generating Cue.xcodeproj from project.yml…"
xcodegen generate

# Signing.xcconfig is local-only (it holds the team ID and is gitignored), so
# it is absent here. project.yml disables the missing-config-file validation
# for exactly this reason, and Xcode Cloud manages signing itself.
