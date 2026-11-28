# Copyright 2026 acwm contributors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Practical and powerful Wayland compositor"
HOMEPAGE="https://github.com/iresolvedllc/acwm"
SRC_URI="https://github.com/iresolvedllc/acwm/releases/download/v${PV}/acwm-${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="GPL-3.0-or-later"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
IUSE="X"

RDEPEND="
	dev-libs/cjson
	dev-libs/pcre2
	gui-libs/scenefx
	gui-libs/wlroots:0.20
	media-libs/libglvnd
	media-libs/mesa
	sys-apps/systemd
	x11-libs/cairo
	x11-libs/gdk-pixbuf
	x11-libs/libdrm
	x11-libs/libinput
	x11-libs/libxcb
	x11-libs/libxkbcommon
	x11-libs/pango
	x11-libs/pixman
	x11-libs/xcb-util-wm
	x11-base/xwayland
"
DEPEND="${RDEPEND}
	dev-libs/wayland
	dev-libs/wayland-protocols
"
BDEPEND="
	dev-lang/zig
	virtual/pkgconfig
"

src_compile() {
	zig build \
		-Doptimize=ReleaseFast \
		-Dversion=${PV} \
		-Dxwayland=$(usex X true false) \
		-Dtray=true \
		--prefix "${T}/stage" || die "zig build failed"
}

src_install() {
	dodir /usr/bin /usr/share /usr/lib /etc
	cp -a "${T}/stage/bin/." "${D}/usr/bin/" || die
	cp -a "${T}/stage/share/." "${D}/usr/share/" || die
	cp -a "${T}/stage/lib/." "${D}/usr/lib/" || die
	cp -a "${T}/stage/etc/." "${D}/etc/" || die
	dodoc "${S}/LICENSE"
}

QA_FLAGS_IGNORED="usr/bin/acwm.*"
