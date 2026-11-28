#!/usr/bin/env bash
# Build an XBPS binary package inside a Void Linux environment.
# Usage: build.sh <version> <output-dir>
set -euo pipefail

version="${1:?version required}"
outdir="${2:-dist}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
arch="$(xbps-uhelper arch 2>/dev/null || uname -m)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

# Prefer the distro Zig when it is new enough, otherwise use the pinned build.
if command -v zig >/dev/null 2>&1 && zig version | grep -q '^0\.17\.'; then
    zig_bin="$(command -v zig)"
else
    case "$arch" in
        x86_64) zig_arch=x86_64; sha=3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a ;;
        aarch64) zig_arch=aarch64; sha=a1546d5646eb184437918d6635ca6b762a0e889eac09cef720ee7a1ed3fe7795 ;;
        *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
    esac
    cache="${XDG_CACHE_HOME:-$HOME/.cache}/acwm-packaging"
    mkdir -p "$cache"
    file="zig-${zig_arch}-linux-0.17.1.tar.xz"
    if [ ! -f "$cache/$file" ]; then
        curl -fL --retry 5 -o "$cache/$file" "https://ziglang.org/download/0.17.1/$file"
    fi
    printf '%s  %s\n' "$sha" "$cache/$file" | sha256sum -c -
    tar -xf "$cache/$file" -C "$stage"
    zig_bin="$stage/zig-${zig_arch}-linux-0.17.1/zig"
fi

export ZIG_LOCAL_CACHE_DIR="$stage/zig-local-cache"
export ZIG_GLOBAL_CACHE_DIR="$stage/zig-global-cache"
"$zig_bin" build \
    -Doptimize=ReleaseFast \
    -Dversion="$version" \
    -Dxwayland=true \
    -Dtray=false \
    --prefix "$stage/root"

mkdir -p "$stage/root/usr"
mv "$stage/root/bin" "$stage/root/usr/bin"
mv "$stage/root/share" "$stage/root/usr/share"
mv "$stage/root/lib" "$stage/root/usr/lib"
mkdir -p "$stage/root/usr/share/doc/acwm"
cp "$repo_root/LICENSE" "$stage/root/usr/share/doc/acwm/"

mkdir -p "$outdir"
outdir="$(cd "$outdir" && pwd)"
cd "$stage"
xbps-create \
    -A "$arch" \
    -n "acwm-${version}_1" \
    -s "Practical and powerful Wayland compositor" \
    -l "GPL-3.0-or-later" \
    -H "https://github.com/iresolvedllc/acwm" \
    -m "acwm maintainers <maintainers@acw.rest>" \
    -D "wlroots0.20>=0.20.0_1 scenefx>=0.5_1 wayland>=1.10.0_1 libinput>=1.2.0_1 libxkbcommon>=0.2.0_1 pixman>=0.14.0_1 libpcre2>=10.22_1 pango>=1.24.0_1 cairo>=1.18.0_1 cJSON>=1.7.19_1 libdrm>=2.4.0_1 gdk-pixbuf>=2.42.0_1 libxcb>=1.2_1 xcb-util-wm>=0.3.9_1 xorg-server-xwayland>=24.1.15_1" \
    -F "/etc/acwm/config.conf /etc/acwm/config.toml" \
    root
mv ./*.xbps "$outdir/"
( cd "$outdir" && sha256sum ./*.xbps > SHA256SUMS.xbps )
