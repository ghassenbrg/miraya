#!/bin/bash
# Uses only the ephemeral CI keychain. Never exports a local signing key.
set -euo pipefail
for name in MACOS_CERTIFICATE_P12 MACOS_CERTIFICATE_PASSWORD APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD RUNNER_TEMP; do
  [[ -n "${!name:-}" ]] || { echo "Required signing secret is missing: $name" >&2; exit 1; }
done
keychain="$RUNNER_TEMP/miraya-signing.keychain-db"
password="$(uuidgen)"
certificate="$RUNNER_TEMP/miraya-developer-id.p12"
trap 'rm -f "$certificate"' EXIT
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
printf '%s' "$MACOS_CERTIFICATE_P12" | base64 --decode > "$certificate"
security import "$certificate" -k "$keychain" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null
existing=()
while IFS= read -r line; do existing+=("$(echo "$line" | sed 's/^[[:space:]]*"//;s/"[[:space:]]*$//')"); done < <(security list-keychains -d user)
security list-keychains -d user -s "$keychain" "${existing[@]}"
xcrun notarytool store-credentials miraya-notary --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --keychain "$keychain" >/dev/null
identity="$(security find-identity -v -p codesigning "$keychain" | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p')"
[[ -n "$identity" && "$identity" != *$'\n'* ]] || { echo 'Expected exactly one Developer ID identity in the imported certificate.' >&2; exit 1; }
echo "identity=$identity"
echo "keychain=$keychain"
