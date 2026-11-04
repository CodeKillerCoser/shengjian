#!/bin/zsh
set -eu
setopt PIPE_FAIL
cd "${0:A:h}"
configuration="${1:-Release}"
case "$configuration" in
  Release) optimization=(-O -whole-module-optimization) ;;
  Debug) optimization=(-Onone -g) ;;
  *) print -u2 'Usage: ./build.sh [Release|Debug]'; exit 2 ;;
esac
signing_dir="${SHENGJIAN_SIGNING_DIR:-$HOME/.config/shengjian/signing}"
identity="${SHENGJIAN_SIGNING_IDENTITY:-${RIMEVOICE_SIGNING_IDENTITY:-}}"
if [[ -z "$identity" && -f signing-identity.txt ]]; then identity="$(<signing-identity.txt)"; fi
if [[ -z "$identity" ]]; then identity="$(<"$signing_dir/certificate.sha1")"; fi
identity="${(U)identity}"
expected="$(<"$signing_dir/certificate.sha1")"
if [[ "$identity" != "$expected" ]] || ! security find-identity -v -p codesigning | /usr/bin/grep -F -- "$identity" >/dev/null; then
  print -u2 '缺少指定的固定签名证书。请先导入已有证书；不允许临时签名或替换签名身份。'
  exit 1
fi
bundle_id='com.shengjian.app'
requirement="designated => identifier \"$bundle_id\" and certificate leaf = H\"$identity\""
output="${BUILD_DIR:-$PWD/build}"
mkdir -p "$output"
stage="$(mktemp -d "${TMPDIR:-/tmp}/shengjian-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/声笺.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp App/Info.plist "$app/Contents/Info.plist"
if [[ -d App/BreezeBootstrap ]]; then ditto App/BreezeBootstrap "$app/Contents/Resources/BreezeBootstrap"; fi
python3 Scripts/set_version.py "$app/Contents/Info.plist"
cp Brand/shengjian-logo-v1.png "$app/Contents/Resources/ShengjianLogo.png"
cp Brand/Shengjian.icns "$app/Contents/Resources/Shengjian.icns"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -parse-as-library -swift-version 5 $optimization -sdk "$sdk" -target arm64-apple-macos14.0 \
  Sources/*.swift -o "$app/Contents/MacOS/Shengjian" \
  -framework SwiftUI -framework AppKit -framework AVFoundation -framework Speech -framework Security -framework Carbon -framework CoreAudio
codesign --force --sign "$identity" --identifier "$bundle_id" --requirements "=$requirement" "$app"
codesign --verify --strict --test-requirement "=identifier \"$bundle_id\" and certificate leaf = H\"$identity\"" "$app"
# Replace only after a complete build and signature verification.
rm -rf "$output/声笺.app"
ditto "$app" "$output/声笺.app"
print "Built $configuration: $output/声笺.app"
xcrun lipo -archs "$output/声笺.app/Contents/MacOS/Shengjian"
codesign -d -r- "$output/声笺.app"
