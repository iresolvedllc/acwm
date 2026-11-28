;;; Guix package definition for acwm.
;;; Add this repository as a channel or build with:
;;;   guix build -f acwm.scm
;;;   guix package -f acwm.scm -i

(define-module (acwm)
  #:use-module (guix gexp)
  #:use-module (guix git)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module (gnu packages)
  #:use-module (gnu packages admin)
  #:use-module (gnu packages build-tools)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages gtk)
  #:use-module (gnu packages javascript)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages pciutils)
  #:use-module (gnu packages pcre)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages xdisorg)
  #:use-module (gnu packages xorg)
  #:use-module (gnu packages window-management)
  #:use-module (guix build-system zig)
  #:use-module ((guix licenses) #:prefix license:))

(define %acwm-version "0.1.1")

(define-public acwm
  (package
    (name "acwm")
    (version %acwm-version)
    (source (local-file "." "acwm-checkout"
                        #:recursive? #t
                        #:select? (or (git-predicate (current-source-directory))
                                      (const #t))))
    (build-system zig-build-system)
    (arguments
     (list #:install-source? #f
           #:zig-release-type "fast"
           #:zig-build-flags
           #~(list (string-append "-Dversion=" #$%acwm-version)
                   "-Dxwayland=true"
                   "-Dtray=false")))
    (native-inputs
     (list pkg-config wayland-protocols))
    (inputs
     (list cairo
           cjson
           gdk-pixbuf
           libdrm
           libinput
           libxkbcommon
           libxcb
           libdisplay-info
           libliftoff
           pango
           pcre2
           pixman
           scenefx
           seatd
           wayland
           wlroots-0.20
           xcb-util-wm))
    (home-page "https://github.com/iresolvedllc/acwm")
    (synopsis "Practical and powerful Wayland compositor")
    (description
     "acwm is a dwm-like, tag-based Wayland compositor built on wlroots and
scenefx.  It ships a built-in bar and SNI tray, animations, overview,
scrolling and dwindle layouts, an IPC interface, a screenshot portal and a
greetd greeter.")
    (license (list license:gpl3+     ; acwm, dwl
                   license:expat     ; dwm, sway, wlroots
                   license:cc0))))   ; tinywl

acwm
