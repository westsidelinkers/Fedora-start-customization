# Fedora Sway Atomic — Tokyo Night Desktop Setup

A record of the desktop customization work performed on Fedora Sway Atomic 44 using Sway, Waybar, Alacritty, Rofi, Dunst, Swaylock, GTK, and SDDM.

> **Documentation note:** This README is based on the changes and command outputs captured during setup. The verification section distinguishes checks observed at the time from checks to repeat after future edits; it is not a claim that every component was retested after the final change.

## Contents

- [Environment](#environment)
- [Customization summary](#customization-summary)
- [Configuration locations](#configuration-locations)
- [Verification and tests](#verification-and-tests)
- [Reloading and persistence](#reloading-and-persistence)
- [Troubleshooting and recovery](#troubleshooting-and-recovery)

## Environment

| Component | Recorded version or detail |
|---|---|
| Operating system | Fedora Sway Atomic 44 |
| Window manager | Sway `1.11-3.fc44.x86_64` |
| Status bar | Waybar `0.15.0-1.fc44.x86_64` |
| Terminal | Alacritty `0.17.0-1.fc44.x86_64` |
| Launcher | Rofi |
| Wallpaper utility | `swaybg` |
| Login manager | SDDM |
| Development environment | Fedora Toolbox; Podman preferred over Docker |

Versions were captured during setup and may differ after updates.

## Customization summary

### Wallpaper

- Chose a dark wallpaper featuring an animal coding.
- Stored it at `~/.local/share/backgrounds/wallpaper.png`.
- Added a Sway config fragment to fill the display with this wallpaper.

### Alacritty

- Created `~/.config/alacritty/alacritty.toml`.
- Set background opacity to `0.75` and configured window padding.
- Set **JetBrainsMono Nerd Font** at size `12`.
- Configured a blinking beam cursor.
- Applied a Tokyo Night-inspired color palette.
- Font files were installed under `~/.local/share/fonts/JetBrainsMono`.

### Waybar

- Created a user-owned configuration and stylesheet based on the system defaults.
- Applied Tokyo Night-inspired styling.
- Set the bar to the bottom of the screen at height `32`.
- Kept workspace and mode indicators on the left, with audio, network, battery, clock, and tray modules on the right.

Files: `~/.config/waybar/config.jsonc` and `~/.config/waybar/style.css`.

### Sway appearance and keybindings

- Added Tokyo Night-inspired window border colors.
- Set inner gaps to `6` and outer gaps to `3`.
- Configured `Super+D` to open Rofi.
- Configured `Super+Escape` to lock the screen using Swaylock.
- Kept user overrides in the home directory rather than editing Fedora's packaged defaults.

Relevant files:

- `~/.config/sway/config.d/10-wallpaper.conf`
- `~/.config/sway/config.d/70-window-spacing.conf`
- `~/.config/sway/config.d/80-tokyonight-borders.conf`

### GTK theme and icons

- Applied the **Tokyonight-BL-MB-Dark-Moon** GTK theme.
- Enabled the GTK dark preference.
- Installed and selected **Papirus-Dark** icons.

### Rofi and notifications

- Styled Rofi with `~/.config/rofi/tokyonight.rasi`.
- Configured Dunst with `~/.config/dunst/dunstrc` using Tokyo Night-inspired colors.

### Swaylock and idle behavior

- Created `~/.config/swaylock/config` with a matching dark theme.
- Kept Fedora's default Sway idle policy unchanged. The inspected configuration locks after 300 seconds and turns the screen off 60 seconds after locking.

### SDDM login screen

Created a separate Tokyo Night-inspired SDDM theme while leaving the packaged Fedora theme untouched.

- Copied the packaged Sway/Fedora theme to `/usr/local/share/sddm/themes/TokyoNight`.
- Selected it through `/etc/sddm.conf.d/99-tokyonight.conf`.
- Copied the wallpaper to `/usr/local/share/backgrounds/tokyonight-login.png` so the greeter can read it without traversing a private home directory.
- Updated the custom theme's `theme.conf` and `Main.qml`.
- Styled the login panel as a dark rounded rectangle near the lower-right corner.
- Changed clock, labels, prompts, and input text to light Tokyo Night colors.
- Made username and password input backgrounds transparent.
- Styled Login, Shutdown, and Reboot buttons with a consistent dark fill, light text, and subdued border.

Relevant system-level paths:

- `/etc/sddm.conf.d/99-tokyonight.conf`
- `/usr/local/share/sddm/themes/TokyoNight/theme.conf`
- `/usr/local/share/sddm/themes/TokyoNight/Main.qml`
- `/usr/local/share/backgrounds/tokyonight-login.png`

Backups created during editing included `Main.qml.bak` and `Main.qml.before-buttons` in the custom theme directory. They were created at different stages and may not both represent the final state.

## Configuration locations

```text
~/.config/
├── alacritty/alacritty.toml
├── dunst/dunstrc
├── rofi/tokyonight.rasi
├── sway/config.d/
│   ├── 10-wallpaper.conf
│   ├── 70-window-spacing.conf
│   └── 80-tokyonight-borders.conf
├── swaylock/config
└── waybar/
    ├── config.jsonc
    └── style.css

~/.local/share/backgrounds/wallpaper.png
~/.local/share/fonts/JetBrainsMono/

/etc/sddm.conf.d/99-tokyonight.conf
/usr/local/share/sddm/themes/TokyoNight/
/usr/local/share/backgrounds/tokyonight-login.png
```

## Verification and tests

These are desktop configuration and runtime checks, not an automated unit-test suite.

### Checks observed during setup

| Check | Recorded result |
|---|---|
| Desktop binaries | Sway, Waybar, Alacritty, Swaybg, and Rofi binaries were present. |
| Waybar | The user reported that an earlier customization was working correctly. |
| SDDM service | SDDM was active and enabled during inspection. |
| SDDM configuration | The custom theme selection was written to `/etc/sddm.conf.d/99-tokyonight.conf`. |
| SDDM preview | `/usr/bin/sddm-greeter-qt6 --test-mode --theme /usr/local/share/sddm/themes/TokyoNight` opened a preview successfully. |
| Original SDDM theme | The packaged Fedora theme was copied, not edited in place. |
| Overall appearance | The user reported that the desktop and login-screen changes looked good. |

The Nerd Font was installed locally and selected in Alacritty. Use `fc-match` below to verify font resolution on the current system.

### Re-run checks after significant edits

Run these commands from a terminal in the Sway session. They inspect configuration and runtime state; they do not change the setup.

```bash
# Sway version and loaded configuration
sway --version
swaymsg -t get_config

# Reload the Sway configuration
swaymsg reload

# List relevant user configuration files
find ~/.config/sway/config.d ~/.config/waybar ~/.config/alacritty \
  ~/.config/rofi ~/.config/dunst ~/.config/swaylock \
  -maxdepth 2 -type f -print

# Confirm the font is resolvable
fc-match "JetBrainsMono Nerd Font"

# Check whether Waybar is running
pgrep -a waybar

# Check SDDM service state
systemctl is-enabled sddm
systemctl is-active sddm

# Inspect SDDM theme selection and theme configuration
cat /etc/sddm.conf.d/99-tokyonight.conf
cat /usr/local/share/sddm/themes/TokyoNight/theme.conf

# Confirm the custom login wallpaper and QML file exist
ls -l /usr/local/share/backgrounds/tokyonight-login.png
ls -l /usr/local/share/sddm/themes/TokyoNight/Main.qml
```

To preview the SDDM theme without logging out:

```bash
/usr/bin/sddm-greeter-qt6 --test-mode \
  --theme /usr/local/share/sddm/themes/TokyoNight
```

Close the preview with **Alt+F4**, or press **Ctrl+C** in the terminal that launched it. A preview checks appearance but does not replace testing a real login.

### Manual acceptance checklist

- [ ] Wallpaper appears and fills the display.
- [ ] Alacritty uses the expected font, opacity, padding, cursor, and palette.
- [ ] Waybar appears at the bottom with the expected modules and colors.
- [ ] Window borders and gaps match the chosen style.
- [ ] `Super+D` opens Rofi.
- [ ] Dunst notifications use the custom theme.
- [ ] `Super+Escape` locks the screen using Swaylock.
- [ ] GTK applications use the dark theme and Papirus-Dark icons.
- [ ] SDDM preview shows the wallpaper, lower-right panel, readable text, and consistent buttons.
- [ ] A normal logout/login works before relying on the custom SDDM theme.
- [ ] The configuration still works after a reboot.

## Reloading and persistence

- **Sway:** `swaymsg reload` reloads Sway configuration files. It does not necessarily restart applications or reload each application's own stylesheet.
- **Waybar:** restart or signal Waybar if edits do not appear automatically.
- **Alacritty:** open a new terminal window to verify changes; some settings apply to newly launched windows.
- **Rofi, Dunst, and Swaylock:** test each application after changing its configuration.
- **SDDM:** its configuration and theme are system-level files and persist through ordinary reboots. Use the greeter preview to inspect changes without restarting SDDM from the active desktop.
- **Fedora Atomic:** `/etc` and `/usr/local` are intended for local configuration and normally persist through ordinary reboots and OS deployments. A system reset, reinstall, or disk replacement can remove them, so keep a separate backup.

**Do not restart SDDM from the active graphical session as a routine test.** Restarting the display manager can terminate the current desktop session.

## Troubleshooting and recovery

1. **A style change does not appear:** check that the application is reading the intended user configuration, then restart the relevant application. `swaymsg reload` does not reload every application's configuration.
2. **The font looks wrong:** run `fc-match "JetBrainsMono Nerd Font"` and check the files under `~/.local/share/fonts/JetBrainsMono`.
3. **The SDDM wallpaper is missing:** check `/usr/local/share/backgrounds/tokyonight-login.png` and verify it is readable by the greeter.
4. **The SDDM preview fails:** verify the theme directory and `Main.qml` exist, and review QML edits before attempting an actual logout.
5. **Revert SDDM:** set `Current` in `/etc/sddm.conf.d/99-tokyonight.conf` back to the packaged theme `03-sway-fedora`, or temporarily move the custom override file aside. Keep the custom theme and backups until the fallback has been tested.

## Notes

- This README summarizes the setup as captured in the conversation; it does not include every terminal command or intermediate experiment.
- Re-run the checks above on the current machine before treating the checklist as a fresh test report.
- Store this file as `README.md` in the repository where you keep your desktop configuration files, then commit it alongside the files you choose to version.
- Review configs for private paths, machine-specific details, and secrets before publishing. This setup should not require passwords or API keys in configuration files.
