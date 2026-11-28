#!/usr/bin/env bash
# Create a Gentoo overlay tarball with a valid Manifest for a release.
# Usage: build-gentoo-overlay.sh <version> <source-tarball> <output-dir>
set -euo pipefail

version="${1:?version required}"
source_tarball="${2:?source tarball required}"
outdir="${3:-dist}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/app-misc/acwm"
cp "$repo_root/packaging/gentoo/app-misc/acwm/metadata.xml" "$tmp/app-misc/acwm/"
cp "$repo_root/packaging/gentoo/app-misc/acwm/acwm-0.1.1.ebuild" \
    "$tmp/app-misc/acwm/acwm-${version}.ebuild"

size="$(stat -c%s "$source_tarball")"
b2="$(b2sum -l 512 "$source_tarball" | awk '{print $1}')"
sha="$(sha512sum "$source_tarball" | awk '{print $1}')"
{
    echo "DIST acwm-${version}.tar.gz ${size} BLAKE2B ${b2} SHA512 ${sha}"
} > "$tmp/app-misc/acwm/Manifest"

mkdir -p "$outdir"
outdir="$(cd "$outdir" && pwd)"
tar -czf "$outdir/acwm-${version}-gentoo-overlay.tar.gz" -C "$tmp" .
sha256sum "$outdir/acwm-${version}-gentoo-overlay.tar.gz" >> "$outdir/SHA256SUMS.gentoo"
