%global zig_version 0.17.1
%ifarch x86_64
%global zig_arch x86_64
%endif
%ifarch aarch64
%global zig_arch aarch64
%endif
%global debug_package %{nil}

Name:           acwm
Version:        0.1.0
Release:        1%{?dist}
Summary:        Practical and powerful Wayland compositor

License:        GPL-3.0-or-later
URL:            https://github.com/iresolvedllc/acwm
Source0:        acwm-%{version}.tar.gz
Source1:        zig-%{zig_arch}-linux-%{zig_version}.tar.xz

BuildRequires:  gcc
BuildRequires:  pkgconf-pkg-config
BuildRequires:  findutils
BuildRequires:  xz
BuildRequires:  wayland-devel
BuildRequires:  wayland-protocols-devel
BuildRequires:  wlroots-devel >= 0.20
BuildRequires:  scenefx-devel >= 0.5
BuildRequires:  libxkbcommon-devel
BuildRequires:  libinput-devel
BuildRequires:  pixman-devel
BuildRequires:  pcre2-devel
BuildRequires:  pango-devel
BuildRequires:  cairo-devel
BuildRequires:  cjson-devel
BuildRequires:  libdrm-devel
BuildRequires:  systemd-devel
BuildRequires:  gdk-pixbuf2-devel
BuildRequires:  libxcb-devel
BuildRequires:  xcb-util-wm-devel
BuildRequires:  mesa-libEGL-devel
BuildRequires:  mesa-libGLES-devel
BuildRequires:  libdisplay-info-devel
BuildRequires:  libliftoff-devel
BuildRequires:  hwdata

Recommends:     xorg-x11-server-Xwayland

%description
acwm is a dwm-like, tag-based Wayland compositor built on wlroots and
scenefx. It ships a built-in bar and SNI tray, animations, overview,
scrolling and dwindle layouts, an IPC interface, a screenshot portal and
an optional greetd greeter.

%prep
%autosetup -n %{name}-%{version}
tar -xf %{SOURCE1}

%build
export PATH="$PWD/zig-%{zig_arch}-linux-%{zig_version}:$PATH"
export ZIG_LOCAL_CACHE_DIR="%{_builddir}/zig-local-cache"
export ZIG_GLOBAL_CACHE_DIR="%{_builddir}/zig-global-cache"
zig build \
  -Doptimize=ReleaseFast \
  -Dversion=%{version} \
  -Dxwayland=true \
  -Dtray=true \
  --prefix "%{_builddir}/acwm-stage"

%install
install -d "%{buildroot}%{_bindir}" "%{buildroot}%{_datadir}" "%{buildroot}%{_prefix}/lib" "%{buildroot}%{_sysconfdir}"
cp -a "%{_builddir}/acwm-stage/bin/." "%{buildroot}%{_bindir}/"
cp -a "%{_builddir}/acwm-stage/share/." "%{buildroot}%{_datadir}/"
cp -a "%{_builddir}/acwm-stage/lib/." "%{buildroot}%{_prefix}/lib/"
cp -a "%{_builddir}/acwm-stage/etc/." "%{buildroot}%{_sysconfdir}/"

%files
%{_bindir}/acwm
%{_bindir}/acwm-msg
%{_bindir}/acwm-nag
%{_bindir}/acwm-launch
%{_bindir}/acwm-portal
%{_bindir}/acwm-greeter
%{_mandir}/man1/acwm*.1*
%{_datadir}/wayland-sessions/acwm.desktop
%{_datadir}/xdg-desktop-portal/acwm-portals.conf
%{_datadir}/xdg-desktop-portal/portals/acwm.portal
%{_datadir}/dbus-1/services/org.freedesktop.impl.portal.desktop.acwm.service
%{_prefix}/lib/systemd/user/acwm-portal.service
%{_prefix}/lib/systemd/user/dbus-org.freedesktop.impl.portal.desktop.acwm.service
%{_prefix}/lib/systemd/user/acwm-session.target
%dir %{_sysconfdir}/acwm
%config(noreplace) %{_sysconfdir}/acwm/config.conf
%config(noreplace) %{_sysconfdir}/acwm/config.toml
%license LICENSE

%changelog
* Fri Nov 27 2026 acwm maintainers <maintainers@acw.rest> - 0.1.0-1
- Initial package
