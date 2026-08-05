#!/usr/bin/env bash
# Release helpers for the denokv workspace, used by the release
# workflow and runnable locally.
#
#   scripts/release.sh bump <version>    rewrite crate versions and the
#                                        lockfile to <version>
#   scripts/release.sh notes <version>   print release notes for the
#                                        range <last tag>..HEAD
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  echo "usage: $0 bump|notes <version>" >&2
  exit 1
}

[ $# -eq 2 ] || usage
command=$1
version=$2

if ! grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' <<< "$version"; then
  echo "invalid version: $version" >&2
  exit 1
fi

case "$command" in
  bump)
    for crate in denokv proto postgres remote sqlite timemachine; do
      sed -i.bak -E "s/^version = \"[^\"]+\"$/version = \"$version\"/" \
        "$crate/Cargo.toml"
      rm "$crate/Cargo.toml.bak"
    done
    sed -i.bak -E \
      "s/^(denokv_[a-z]+ = \{ version = )\"[^\"]+\"/\1\"$version\"/" \
      Cargo.toml
    rm Cargo.toml.bak
    cargo update --workspace --quiet
    ;;
  notes)
    repository=${GITHUB_REPOSITORY:-denoland/denokv}
    if prev=$(git describe --tags --abbrev=0 HEAD 2>/dev/null); then
      range="$prev..HEAD"
      changelog="https://github.com/$repository/compare/$prev...$version"
    else
      range=HEAD
      changelog="https://github.com/$repository/commits/$version"
    fi
    echo "## What's Changed"
    git log --oneline --no-decorate --no-merges "$range" \
      | sed -E 's/^[0-9a-f]+ /* /'
    echo
    echo "**Full Changelog**: $changelog"
    ;;
  *)
    usage
    ;;
esac
