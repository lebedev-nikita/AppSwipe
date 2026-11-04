set shell := ["bash", "-euo", "pipefail", "-c"]

app := justfile_directory() / "build/Build/Products/Debug/AppSwipe.app"
identity := "AppSwipe Development"
logs := home_directory() / "Library/Logs/AppSwipe"
version := `sed -n 's/^    MARKETING_VERSION: //p' project.yml`
release_dir := justfile_directory() / "build/release"
release_zip := release_dir / "AppSwipe-" + version + ".zip"

default:
    @just --list

# Generate AppSwipe.xcodeproj from project.yml
generate:
    mise x -- xcodegen generate --quiet

# Build the Debug app and sign it with the local development certificate
build: generate
    xcodebuild -project AppSwipe.xcodeproj -scheme AppSwipe -configuration Debug \
        -derivedDataPath build -destination 'platform=macOS,arch=arm64' -quiet build
    codesign --force --sign "{{ identity }}" "{{ app }}"

# Run the SwitchCore unit tests
test:
    swift test --package-path SwitchCore

# Build, then relaunch the app
run: build
    -pkill -x AppSwipe
    open "{{ app }}"

# Follow the app's diagnostic log
log:
    tail -n 50 -f "{{ logs }}/appswipe.log"

# Build a universal Release app, sign it, and zip it with its SHA-256
package: generate test
    xcodebuild -project AppSwipe.xcodeproj -scheme AppSwipe -configuration Release \
        -derivedDataPath build -destination 'generic/platform=macOS' -quiet build
    codesign --force --sign "{{ identity }}" build/Build/Products/Release/AppSwipe.app
    rm -rf "{{ release_dir }}" && mkdir -p "{{ release_dir }}"
    ditto -c -k --sequesterRsrc --keepParent build/Build/Products/Release/AppSwipe.app "{{ release_zip }}"
    cd "{{ release_dir }}" && shasum -a 256 "$(basename "{{ release_zip }}")" > "$(basename "{{ release_zip }}").sha256"

# Publish the package as GitHub release v<version> from a clean, pushed main
release: package
    test -z "$(git status --porcelain)" || { echo "Commit your changes first." >&2; exit 1; }
    git push origin HEAD
    gh release create "v{{ version }}" "{{ release_zip }}" "{{ release_zip }}.sha256" \
        --title "AppSwipe {{ version }}" --generate-notes

# Point the cask in lebedev-nikita/homebrew-tap at the published release
cask:
    #!/usr/bin/env bash
    set -euo pipefail
    tap="$(brew --repo lebedev-nikita/tap)"
    sha="$(cut -d' ' -f1 "{{ release_zip }}.sha256")"
    sed -i '' -e 's/^  version ".*"$/  version "{{ version }}"/' -e "s/^  sha256 \".*\"$/  sha256 \"$sha\"/" \
        "$tap/Casks/appswipe.rb"
    git -C "$tap" commit -am "Update AppSwipe to {{ version }}"
    git -C "$tap" push
