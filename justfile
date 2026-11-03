set shell := ["bash", "-euo", "pipefail", "-c"]

app := justfile_directory() / "build/Build/Products/Debug/OpenSwipe.app"
identity := "OpenSwipe Development"
logs := home_directory() / "Library/Logs/OpenSwipe"

default:
    @just --list

# Generate OpenSwipe.xcodeproj from project.yml
generate:
    mise x -- xcodegen generate --quiet

# Build the Debug app and sign it with the local development certificate
build: generate
    xcodebuild -project OpenSwipe.xcodeproj -scheme OpenSwipe -configuration Debug \
        -derivedDataPath build -destination 'platform=macOS,arch=arm64' -quiet build
    codesign --force --sign "{{ identity }}" "{{ app }}"

# Run the SwitchCore unit tests
test:
    swift test --package-path SwitchCore

# Build, then relaunch the app
run: build
    -pkill -x OpenSwipe
    open "{{ app }}"

# Follow the app's diagnostic log
log:
    tail -n 50 -f "{{ logs }}/openswipe.log"
