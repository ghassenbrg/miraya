#!/bin/bash
# Sidefolk's snapshot/production contract, adapted to Miraya's two platforms.
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "release-plan: $*" >&2; exit 1; }
version="$(tr -d '\r\n' < VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'VERSION must be X.Y.Z.'
build="$(git rev-list --count HEAD)"
channel="${CHANNEL:-}"
if [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
  tag="${GITHUB_REF#refs/tags/}"
  [[ "$tag" == "v$version" ]] || fail "tag $tag does not match VERSION ($version)."
  [[ -z "$channel" || "$channel" == production ]] || fail 'a version tag makes a production release.'
  channel=production
fi
channel="${channel:-snapshot}"
case "$channel" in
  production)
    tag="v$version"; label=""; prerelease=false
    [[ "${SIGNING:-no}" == yes ]] || fail 'production requires Developer ID signing and notarization secrets.'
    [[ "${ANDROID_SIGNING:-no}" == yes ]] || fail 'production requires the Android release keystore and passwords.'
    if existing="$(git rev-parse -q --verify "refs/tags/$tag^{commit}")" && [[ "$existing" != "$(git rev-parse HEAD)" ]]; then
      fail "$tag already marks another commit; raise VERSION first."
    fi
    ;;
  snapshot) tag="v$version-snapshot.$build"; label="snapshot.$build"; prerelease=true ;;
  *) fail 'channel must be production or snapshot.' ;;
esac
echo "channel=$channel"
echo "version=$version"
echo "build=$build"
echo "tag=$tag"
echo "label=$label"
echo "prerelease=$prerelease"
