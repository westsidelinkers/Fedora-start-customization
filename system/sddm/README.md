# SDDM Tokyo Night Theme

## Overview

The SDDM login screen uses a custom Tokyo Night theme installed under
`/usr/local/share/sddm/themes/TokyoNight/`. This theme is based on Fedora's
packaged `03-sway-fedora` theme but has been customized with Tokyo Night colors,
a custom login wallpaper, and a dark rounded-rectangle panel positioned near the
lower-right corner of the screen.

The packaged Fedora theme was **copied, not edited in place**. The original
`/usr/local/share/sddm/themes/03-sway-fedora/` directory (or the system-packaged
location) remains untouched.

## System paths

| Path | Purpose |
|------|---------|
| `/etc/sddm.conf.d/99-tokyonight.conf` | SDDM override selecting the TokyoNight theme |
| `/usr/local/share/sddm/themes/TokyoNight/` | Custom theme directory |
| `/usr/local/share/sddm/themes/TokyoNight/theme.conf` | Theme configuration (sets login wallpaper) |
| `/usr/local/share/sddm/themes/TokyoNight/Main.qml` | Custom greeter QML |
| `/usr/local/share/sddm/themes/TokyoNight/metadata.desktop` | Theme metadata |
| `/usr/local/share/backgrounds/tokyonight-login.png` | Login screen wallpaper |

### SDDM override file

`/etc/sddm.conf.d/99-tokyonight.conf` contains:

```ini
[Theme]
ThemeDir=/usr/local/share/sddm/themes
Current=TokyoNight
```

### Theme configuration

`/usr/local/share/sddm/themes/TokyoNight/theme.conf` contains:

```ini
[General]
background=/usr/local/share/backgrounds/tokyonight-login.png
```

## Dependencies

- **SDDM** with Qt6 greeter (`sddm-greeter-qt6`)
- **JetBrainsMono Nerd Font** — used by the clock and login panel text. Must be
  installed system-wide or in a location visible to the SDDM greeter.
- **QtQuick 2.0** and **SDDMComponents 2.0** — provided by the SDDM greeter.

## Previewing the theme

To preview the theme without logging out or restarting SDDM:

```bash
/usr/bin/sddm-greeter-qt6 --test-mode \
  --theme /usr/local/share/sddm/themes/TokyoNight
```

Close the preview with **Alt+F4**, or press **Ctrl+C** in the terminal that
launched it.

A preview checks appearance but does not replace testing a real login.

## Reverting to the packaged Fedora theme

To temporarily revert to Fedora's packaged `03-sway-fedora` theme:

```bash
# Option A: Edit the override file
sudo sed -i 's/Current=TokyoNight/Current=03-sway-fedora/' /etc/sddm.conf.d/99-tokyonight.conf

# Option B: Move the override file aside
sudo mv /etc/sddm.conf.d/99-tokyonight.conf /etc/sddm.conf.d/99-tokyonight.conf.disabled
```

To re-enable the Tokyo Night theme:

```bash
# If you used Option A
sudo sed -i 's/Current=03-sway-fedora/Current=TokyoNight/' /etc/sddm.conf.d/99-tokyonight.conf

# If you used Option B
sudo mv /etc/sddm.conf.d/99-tokyonight.conf.disabled /etc/sddm.conf.d/99-tokyonight.conf
```

## Backup files

The following backup files exist in the theme directory:

| File | Description |
|------|-------------|
| `/usr/local/share/sddm/themes/TokyoNight/Main.qml.bak` | Backup of Main.qml before customizations |
| `/usr/local/share/sddm/themes/TokyoNight/Main.qml.before-buttons` | Intermediate backup before button styling |

These backups were created at different stages and may not both represent the
final state. They are kept for reference and have not been deleted.

## What is NOT version-controlled

The SDDM theme files live under `/usr/local/` and `/etc/` — these are system
paths, not user configuration. They are **documented here** but are not copied
into this repository. The theme requires root privileges to install and cannot
be managed purely through version-controlled user files.

To replicate the SDDM theme on another machine:

1. Copy the `TokyoNight` theme directory to `/usr/local/share/sddm/themes/`
2. Copy the login wallpaper to `/usr/local/share/backgrounds/`
3. Create `/etc/sddm.conf.d/99-tokyonight.conf` with the content shown above
4. Preview with `sddm-greeter-qt6 --test-mode`
