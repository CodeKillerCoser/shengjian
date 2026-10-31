#!/bin/bash
set -euo pipefail
: "${SIGNING_CERTIFICATE_P12:?Missing SIGNING_CERTIFICATE_P12 secret}"
: "${SIGNING_CERTIFICATE_PASSWORD:?Missing SIGNING_CERTIFICATE_PASSWORD secret}"
: "${RUNNER_TEMP:?Only run this on a disposable CI runner}"
export SIGNING_KEYCHAIN="$RUNNER_TEMP/shengjian-signing.keychain-db"
certificate="$RUNNER_TEMP/shengjian-signing.p12"
keychain_password="$(openssl rand -hex 32)"
echo "::add-mask::$keychain_password"
printf '%s' "$SIGNING_CERTIFICATE_P12" | base64 --decode > "$certificate"
chmod 600 "$certificate"
security create-keychain -p "$keychain_password" "$SIGNING_KEYCHAIN"
security set-keychain-settings -lut 21600 "$SIGNING_KEYCHAIN"
security unlock-keychain -p "$keychain_password" "$SIGNING_KEYCHAIN"
security import "$certificate" -P "$SIGNING_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -t cert -f pkcs12 -k "$SIGNING_KEYCHAIN" >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$SIGNING_KEYCHAIN" >/dev/null
security find-certificate -c 'RimeVoice Local Code Signing' -p "$SIGNING_KEYCHAIN" > "$RUNNER_TEMP/shengjian-signing.pem"
actual="$(openssl x509 -in "$RUNNER_TEMP/shengjian-signing.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
expected="$SHENGJIAN_EXPECTED_SIGNING_IDENTITY"
[[ "$actual" == "$expected" ]] || { echo 'Unexpected signing certificate'; exit 1; }
sudo -n security add-trusted-cert -d -r trustRoot -p codeSign -k "$SIGNING_KEYCHAIN" "$RUNNER_TEMP/shengjian-signing.pem"
security list-keychains -d user -s "$SIGNING_KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
mkdir -p "$RUNNER_TEMP/shengjian-signing"
printf '%s\n' "$expected" > "$RUNNER_TEMP/shengjian-signing/certificate.sha1"
echo "SHENGJIAN_SIGNING_DIR=$RUNNER_TEMP/shengjian-signing" >> "$GITHUB_ENV"
echo "SHENGJIAN_SIGNING_IDENTITY=$expected" >> "$GITHUB_ENV"
