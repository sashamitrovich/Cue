#!/bin/sh
# Xcode Cloud runs this immediately after cloning, before it looks for the
# project. Cue.xcodeproj is generated from project.yml and deliberately not
# committed, so without this the build fails with "Project Cue.xcodeproj does
# not exist at the root of the repository".
set -e

echo "Installing XcodeGen…"
brew install xcodegen

cd "$CI_PRIMARY_REPOSITORY_PATH"

# Signing.xcconfig holds the team ID and is gitignored, so it is absent here.
# The generated project still references it as a base configuration, and
# xcodebuild fails with "Unable to open base configuration reference file"
# if it is missing — a stub is enough, since Xcode Cloud injects its own
# signing settings and an unset DEVELOPMENT_TEAM is what we want in CI.
if [ ! -f Signing.xcconfig ]; then
    echo "Creating a stub Signing.xcconfig (Xcode Cloud manages signing)"
    echo "// Created by ci_post_clone.sh — Xcode Cloud provides signing." > Signing.xcconfig
fi

echo "Generating Cue.xcodeproj from project.yml…"
xcodegen generate
