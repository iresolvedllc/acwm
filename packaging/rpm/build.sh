#!/usr/bin/env bash
# Build v4 and v6 RPMs for the current architecture.
# Usage: build.sh <version> <output-dir>
# Requires rpmbuild >= 6, the BuildRequires from acwm.spec, git, curl, xz.
set -euo pipefail

version="${1:?version required}"
outdir="${2:-dist}"
formats="${3:-4 6}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
arch="$(uname -m)"
case "$arch" in
    x86_64) zig_sha=3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a ;;
    aarch64) zig_sha=a1546d5646eb184437918d6635ca6b762a0e889eac09cef720ee7a1ed3fe7795 ;;
    *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
esac

zig_file="zig-${arch}-linux-0.17.1.tar.xz"
zig_url="https://ziglang.org/download/0.17.1/${zig_file}"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/acwm-packaging"
mkdir -p "$cache"

if [ ! -f "$cache/$zig_file" ]; then
    echo "downloading $zig_url" >&2
    curl -fL --retry 5 -o "$cache/$zig_file" "$zig_url"
fi
printf '%s  %s\n' "$zig_sha" "$cache/$zig_file" | sha256sum -c -

mkdir -p "$outdir"
outdir="$(cd "$outdir" && pwd)"

for fmt in $formats; do
    topdir="$cache/rpmbuild-v$fmt"
    rm -rf "$topdir"
    mkdir -p "$topdir"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
    cp "$cache/$zig_file" "$topdir/SOURCES/"
    sed "s/^Version:.*/Version:        ${version}/" \
        "$repo_root/packaging/rpm/acwm.spec" > "$topdir/SPECS/acwm.spec"
    if [ -n "${ACWM_SOURCE_TARBALL:-}" ]; then
        cp "$ACWM_SOURCE_TARBALL" "$topdir/SOURCES/acwm-${version}.tar.gz"
    else
        git -C "$repo_root" archive \
            --format=tar.gz \
            --prefix="acwm-${version}/" \
            -o "$topdir/SOURCES/acwm-${version}.tar.gz" HEAD
    fi

    rpmbuild -bb \
        --define "_topdir $topdir" \
        --define "_rpmformat $fmt" \
        --define "dist .v$fmt" \
        "$topdir/SPECS/acwm.spec"

    find "$topdir/RPMS" -name '*.rpm' -exec cp -v {} "$outdir/" \;
done

( cd "$outdir" && sha256sum ./*.rpm > SHA256SUMS.rpm )
