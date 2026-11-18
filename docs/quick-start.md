---
title: Quick Start
description: Basic configuration and first steps with acwm.
---

Now that you have acwm installed, let's get your environment set up.

## Initial Setup

1. **Create Configuration Directory**

   acwm looks for configuration files in `~/.config/acwm/`.

   ```bash
   mkdir -p ~/.config/acwm
   ```

2. **Copy Default Config**

   A default configuration file is provided at `/etc/acwm/config.conf`. Copy it to your local directory to start customizing.

   ```bash
   cp /etc/acwm/config.conf ~/.config/acwm/config.conf
   ```

3. **Launch acwm**

   You can now start the compositor from your TTY.

   ```bash
   acwm
   ```

   Optional: To specify a custom config file path:

   ```bash
   acwm -c /path/to/your/config.conf
   ```

## Essential Keybindings

acwm uses the following keybinds by default:

| Key Combination | Action |
| :--- | :--- |
| `Alt` + `Return` | Open Terminal (defaults to `foot`) |
| `Alt` + `Space` / solo `Super` release | Open Launcher (`acwm-launch`) |
| `Alt` + `Q` | Close (Kill) the active window |
| `Super` + `M` | Quit acwm |
| `Super` + `F` | Toggle Fullscreen |
| `Alt` + `Arrow Keys` | Move focus (Left, Right, Up, Down) |
| `Ctrl` + `1-9` | Switch to Tag 1-9 |
| `Alt` + `1-9` | Move window to Tag 1-9 |

> **Warning:** Some default bindings rely on specific tools like `foot` (terminal) and `rofi` (launcher). Ensure you have them installed or update your `config.conf` to use your preferred alternatives.

## Recommended Tools

To get a fully functional desktop experience, we recommend installing the following components:

| Category | Recommended Tools |
| :--- | :--- |
| Application Launcher | rofi, bemenu, wmenu, fuzzel |
| Terminal Emulator | foot, wezterm, alacritty, kitty, ghostty |
| Status Bar | waybar, eww, quickshell, ags |
| Desktop Shell | Noctalia, DankMaterialShell |
| Wallpaper Setup | awww(swww), swaybg |
| Notification Daemon | swaync, dunst, mako |
| Desktop Portal | xdg-desktop-portal, xdg-desktop-portal-wlr, xdg-desktop-portal-gtk |
| Clipboard | wl-clipboard, wl-clip-persist, cliphist |
| Gamma Control / Night Light | wlsunset, gammastep |
| Miscellaneous | xfce-polkit, wlogout |

## Example Configuration

Check out the [example configuration](https://github.com/DreamMaoMao/mango-config) by the creator of acwm, including complete setups for acwm, Waybar, Rofi, and more.

```bash
git clone https://github.com/DreamMaoMao/mango-config.git ~/.config/acwm
```

## Next Steps

Now that you are up and running, dive deeper into customizing acwm:

- [Configure Monitors](/docs/configuration/monitors) — Set up resolution, scaling, and multi-monitor layouts.
- [Window Rules](/docs/window-management/rules#window-rules) — Define how specific applications should behave.
- [Appearance](/docs/visuals/theming) — Customize colors, borders, gaps, and effects.
