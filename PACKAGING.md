# Packaging acwm

This document is the reference for building and installing acwm packages.
The release workflow produces the binary artifacts; the recipes in
`packaging/` are the source of truth for each format.

## Supported platforms

Official release artifacts are built for:

- `x86_64` Linux
- `aarch64` Linux

The compositor requires Wayland, wlroots 0.20, scenefx 0.5 and Zig 0.17.x to
build. Runtime packages use the distribution packages of those libraries.

## Release artifacts

Each release attaches all of the following:

| Artifact | Format | Notes |
|---|---|---|
| `acwm-<ver>.tar.gz` | source | Used by all source recipes |
| `acwm-<ver>.scm` | Guix recipe | Copy of the repository `acwm.scm` |
| `acwm-<ver>-1.v4.<arch>.rpm` | RPM v4 | Fedora 45 build, v4 package format |
| `acwm-<ver>-1.v6.<arch>.rpm` | RPM v6 | Fedora 45 build, v6 package format |
| `acwm-<ver>_1.<arch>.xbps` | Void XBPS | Built in a Void glibc container; no tray/portal (Void has no libsystemd) |
| `acwm-<ver>-gentoo-overlay.tar.gz` | Gentoo overlay | Ebuild, metadata and generated Manifest |
| `acwm-<ver>-void-template` | Void template | Checksum-correct template for the release tarball |
| `SHA256SUMS` | checksums | Covers every attached asset |

The Nix package is consumed directly from the flake; no separate binary
tarball is published because Nix store closures are not relocatable.

### RPM v4 and v6

Both RPM variants are built from the same source and spec on Fedora 45. The
only difference is the package format:

- **v4** is emitted with `rpmbuild --define '_rpmformat 4'` for consumers
  that still need the older header/payload format.
- **v6** is the native rpm 6.x format with modern hashes and 64-bit size
  tags.

The v4 RPM is not a promise of Enterprise Linux 9 compatibility: the binary
is still linked against Fedora 45 libraries. Build in an older target
container if you need an older glibc baseline.

## Installing

### Fedora / RPM

```sh
sudo dnf install ./acwm-<ver>-1.v6.x86_64.rpm
# or, for older RPM tooling:
sudo dnf install ./acwm-<ver>-1.v4.x86_64.rpm
```

### Void Linux

```sh
sudo xbps-install --repository=/path/to/artifacts acwm
```

Or copy the recipe into a `void-packages` checkout:

```sh
cp packaging/void/template void-packages/srcpkgs/acwm/template
cd void-packages
./xbps-src pkg acwm
sudo xbps-install --repository=hostdir/binpkgs acwm
```

The release workflow rewrites the template's `version` and `checksum` and
publishes it as `acwm-<ver>-void-template`.

### Gentoo

```sh
mkdir -p /var/db/repos/acwm
tar -xzf acwm-<ver>-gentoo-overlay.tar.gz -C /var/db/repos/acwm
eselect repository add acwm local /var/db/repos/acwm
emerge --sync acwm
emerge gui-wm/acwm
```

### Guix

From a checkout:

```sh
guix build -f acwm.scm
guix package -f acwm.scm -i
```

The recipe uses Guix's `zig-build-system`, `wlroots-0.20` and `scenefx`.
Zig 0.17 is required.

### Nix

```sh
nix build github:iresolvedllc/acwm
nix run github:iresolvedllc/acwm -- -v
```

Or use the flake as an input; the NixOS and Home Manager modules are in the
same flake.

### Source

```sh
tar -xzf acwm-<ver>.tar.gz
cd acwm-<ver>
zig build -Doptimize=ReleaseFast -Dversion=<ver>
sudo zig build -Doptimize=ReleaseFast -Dversion=<ver> --prefix=/usr
```

`zig build install` puts configuration under `$prefix/etc/acwm`; distribution
packages move it to `/etc/acwm`.

## Release process and immutable releases

GitHub immutable releases lock a release's tag and assets once it is
published. The release workflow therefore:

1. creates a **draft** release,
2. uploads every artifact and checksum to the draft,
3. publishes the draft exactly once.

Do not upload assets to an already-published immutable release. If a package
must be replaced, issue a new patch release. Backfilling an existing release
requires temporarily disabling immutability and then re-enabling it; this is
not part of the automated flow.

## Building locally

- RPM: `packaging/rpm/build.sh <version> <output-dir> [format]`
- Void: `packaging/void/build.sh <version> <output-dir>`
- Gentoo overlay: `packaging/release/build-gentoo-overlay.sh <version> <source-tarball> <output-dir>`
- Void template: `packaging/release/build-void-template.sh <version> <source-tarball> <output-dir>`

The RPM and Void scripts download and verify the pinned Zig 0.17.1 toolchain
unless a suitable system Zig is already available.

## Verification

```sh
sha256sum -c SHA256SUMS
rpm -qpi acwm-<ver>-1.v6.<arch>.rpm
rpm -qp --requires acwm-<ver>-1.v6.<arch>.rpm
xbps-query -R --property=run_depends acwm
```

CI builds the compositor and runs the Zig test suite on Depot runners for
both architectures. Release packaging runs on the same two architectures;
RPM and Void packages are built inside their target distribution containers.
