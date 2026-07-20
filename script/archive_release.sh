#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_root="${script_dir:h}"
signing_identity="${PARADICT_SIGNING_IDENTITY:-Developer ID Application: Sebastian Kouba (2VVZV5X37Y)}"
team_id="${PARADICT_TEAM_ID:-2VVZV5X37Y}"

if [[ -n "${PARADICT_RELEASE_OUTPUT_DIR:-}" ]]; then
    output_dir="$PARADICT_RELEASE_OUTPUT_DIR"
    mkdir -p "$output_dir"
else
    mkdir -p "$project_root/build"
    output_dir="$(mktemp -d "$project_root/build/release.XXXXXX")"
fi

archive_path="$output_dir/ParaDict.xcarchive"
app_path="$archive_path/Products/Applications/ParaDict.app"
zip_path="$output_dir/ParaDict-Developer-ID.zip"

if [[ -e "$archive_path" || -e "$zip_path" ]]; then
    print -u2 "Release output already exists in $output_dir"
    exit 1
fi

xcodebuild \
    -project "$project_root/ParaDict.xcodeproj" \
    -scheme ParaDict \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$archive_path" \
    archive \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$signing_identity" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    DEVELOPMENT_TEAM="$team_id"

codesign --verify --deep --strict --verbose=2 "$app_path"

signature_details="$(codesign -dvv "$app_path" 2>&1)"
if [[ "$signature_details" != *"Authority=$signing_identity"* ]]; then
    print -u2 "Archive was not signed by the expected Developer ID identity"
    exit 1
fi

if [[ "$signature_details" != *"flags=0x10000(runtime)"* ]]; then
    print -u2 "Archive does not have hardened runtime enabled"
    exit 1
fi

if codesign -d --entitlements :- "$app_path" 2>&1 | grep -q "com.apple.security.get-task-allow"; then
    print -u2 "Archive contains the debug-only get-task-allow entitlement"
    exit 1
fi

ditto -c -k --keepParent "$app_path" "$zip_path"

print "Developer ID-signed archive: $app_path"
print "GitHub release ZIP: $zip_path"
