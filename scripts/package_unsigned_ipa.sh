#!/usr/bin/env bash
# Run on macOS after flutter build ios --release --no-codesign.
set -euo pipefail
cd "$(dirname "$0")/.."

app_path="build/ios/iphoneos/Runner.app"
if [[ ! -d "$app_path" || ! -f "$app_path/Info.plist" ]]; then
  echo "Runner.app not found. Complete the iOS release build on macOS first." >&2
  exit 1
fi
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This packaging script requires macOS (ditto and Apple tools)." >&2
  exit 1
fi

mkdir -p build/ios/ipa
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/lyricflow-ipa.XXXXXX")"
trap 'rm -rf -- "$staging_dir"' EXIT
mkdir -p "$staging_dir/Payload"
ditto "$app_path" "$staging_dir/Payload/Runner.app"
ditto -c -k --sequesterRsrc --keepParent \
  "$staging_dir/Payload" build/ios/ipa/LyricFlow-unsigned.ipa
unzip -tq build/ios/ipa/LyricFlow-unsigned.ipa
(
  cd build/ios/ipa
  shasum -a 256 LyricFlow-unsigned.ipa > LyricFlow-unsigned.ipa.sha256
)
echo "Created unsigned IPA. Sign with Sideloadly before installing on a device."
