#!/bin/sh
set -e

# Larpnet.xcodeproj is generated from project.yml and is gitignored (see
# .gitignore), so Xcode Cloud's checkout doesn't have it. Regenerate it here
# before the archive/build/test action runs.
brew install xcodegen

cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

# The generated project has no Package.resolved yet, but Xcode Cloud requires
# one to exist before the build/archive action (it doesn't resolve packages
# live during that step). Resolve now so the file is in place beforehand.
xcodebuild -resolvePackageDependencies -project Larpnet.xcodeproj -scheme Larpnet
