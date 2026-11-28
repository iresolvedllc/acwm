#!/usr/bin/env bash
# Produce a checksum-correct Void template for a release.
# Usage: build-void-template.sh <version> <source-tarball> <output-dir>
set -euo pipefail

version="${1:?version required}"
source_tarball="${2:?source tarball required}"
outdir="${3:-dist}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
sha="$(sha256sum "$source_tarball" | awk '{print $1}')"

mkdir -p "$outdir"
sed -e "s/^version=.*/version=${version}/" \
    -e "s/^checksum=.*/checksum=${sha}/" \
    "$repo_root/packaging/void/template" \
    > "$outdir/acwm-${version}-void-template"
