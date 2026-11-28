# Gentoo overlay

Add this directory as a local overlay, or copy `app-misc/acwm` into your
overlay:

```sh
mkdir -p /var/db/repos/acwm
cp -a packaging/gentoo/* /var/db/repos/acwm/
eselect repository add acwm local /var/db/repos/acwm
emerge --sync acwm
emerge gui-wm/acwm
```

The release workflow generates the `Manifest` for the published tarball and
attaches a ready-to-use overlay tarball.
