# SDDM Tokyo Night theme

## Overview

The SDDM login screen uses a custom Tokyo Night theme installed under
`/usr/local/share/sddm/themes/TokyoNight/`.

The theme is a **derivative work**: Fedora's `03-sway-fedora` theme (shipped
on Fedora Sway Atomic at `/usr/share/sddm/themes/03-sway-fedora`, upstream:
<https://gitlab.com/fedora/sigs/sway/sway-config-fedora>) was copied, not
edited in place, and then customized with Tokyo Night colors, a custom login
wallpaper, and a dark rounded-rectangle panel positioned near the lower-right
corner of the screen.

## License and attribution

The upstream `03-sway-fedora` theme metadata states:

- **Author:** Fedora Sway SIG
- **Copyright:** (c) 2024, Fedora Sway SIG
- **License:** CC-BY-SA-3.0 AND MIT
- **Based on:** the Maldives SDDM theme by Abdurrahman AVCI and other SDDM
  contributors
- **Additional credits:** chevron icons extracted from Font Awesome by Dave
  Gandy; `rectangle.png` from the KDM ariya theme

A `LICENSE` file containing the CC BY-SA 3.0 text ships in the theme
directory. The customized `Main.qml` is the owner's own modification of the
upstream theme.

The custom `Main.qml` and `theme.conf` are version-controlled in this repository
under `system/sddm/TokyoNight/`, with full attribution in
`system/sddm/TokyoNight/ATTRIBUTION.md`. The upstream theme is open source
(CC-BY-SA-3.0 AND MIT), so the derivative work can be redistributed.

## Customizations applied to the upstream theme

The custom `Main.qml` differs from `/usr/share/sddm/themes/03-sway-fedora/Main.qml`
in the following ways:

- Clock: Tokyo Night foreground `#c0caf5`, font `JetBrainsMono Nerd Font`.
- Login panel: replaced the upstream `Image` rectangle with a `Rectangle`
  colored `#1a1b26`, `radius: 12`, `border.color: #414868`,
  `border.width: 1`, anchored to the right/bottom edges with 60 px margins.
- Text colors throughout: Tokyo Night palette (`#c0caf5` foreground,
  `#1a1b26` panel fill).
- Buttons: `color: #24283b`, `textColor: #c0caf5`, `borderColor: #414868`,
  `activeColor: #3d59a1`, `pressedColor: #1a1b26`, `radius: 7`.
- `theme.conf`: `background=/usr/local/share/backgrounds/tokyonight-login.png`
  (upstream uses `/usr/share/backgrounds/default.jxl`).

`metadata.desktop`, `theme.conf.in`, and the image assets are unchanged from
upstream.

## System paths

| Path | Purpose |
|------|---------|
| `/etc/sddm.conf.d/99-tokyonight.conf` | SDDM override selecting the TokyoNight theme |
| `/usr/local/share/sddm/themes/TokyoNight/` | Custom theme directory |
| `/usr/local/share/sddm/themes/TokyoNight/theme.conf` | Theme configuration (sets login wallpaper) |
| `/usr/local/share/sddm/themes/TokyoNight/Main.qml` | Custom greeter QML |
| `/usr/local/share/sddm/themes/TokyoNight/metadata.desktop` | Theme metadata (from upstream) |
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
- **JetBrainsMono Nerd Font** — used by the clock and login panel text. Must
  be installed system-wide or in a location visible to the SDDM greeter
  (see [docs/assets.md](../docs/assets.md)).
- **QtQuick 2.0** and **SDDMComponents 2.0** — provided by the SDDM greeter.

## Manual installation (requires root)

Everything in this section requires administrator privileges and modifies
system paths. The restoration script (`scripts/restore.sh`) never touches
these files; perform these steps by hand.

> **Prerequisite:** the custom theme files (`Main.qml`, `theme.conf`,
> `metadata.desktop`) and the login wallpaper exist only on the machine where
> the theme was created. Copy them from there first:
>
> ```bash
> # On the original machine:
> tar czf tokyonight-sddm.tar.gz \
>     -C /usr/local/share/sddm/themes TokyoNight \
>     -C /usr/local/share/backgrounds tokyonight-login.png
> ```
>
> (Alternatively, start from Fedora's upstream theme at
> `/usr/share/sddm/themes/03-sway-fedora` and re-apply the customizations
> listed above.)

```bash
# 1. Copy the theme directory (skip the .bak/.before-* files)
sudo mkdir -p /usr/local/share/sddm/themes
sudo cp -a /path/to/TokyoNight /usr/local/share/sddm/themes/

# 2. Copy the login wallpaper
sudo mkdir -p /usr/local/share/backgrounds
sudo cp /path/to/tokyonight-login.png /usr/local/share/backgrounds/

# 3. Create the SDDM override
sudo tee /etc/sddm.conf.d/99-tokyonight.conf > /dev/null <<'EOF'
[Theme]
ThemeDir=/usr/local/share/sddm/themes
Current=TokyoNight
EOF

# 4. (Re)build the font cache so SDDM can find JetBrainsMono Nerd Font
sudo fc-cache -f
```

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

The following backup files exist in the theme directory on the machine where
the theme was created:

| File | Description |
|------|-------------|
| `Main.qml.bak` | Backup of Main.qml before customizations |
| `Main.qml.before-buttons` | Intermediate backup before button styling |

These backups were created at different stages and may not both represent the
final state. They are kept for reference and have not been deleted.

## Repository policy

The SDDM theme lives under `/usr/local/` and `/etc/` — system paths, not user
configuration. The restoration script (`scripts/restore.sh`) never installs
SDDM theme files.

The custom `Main.qml` and `theme.conf` are version-controlled in this repository
under `system/sddm/TokyoNight/`. To install them on a new system, copy from the
repository rather than from the original host:

```bash
sudo mkdir -p /usr/local/share/sddm/themes
sudo cp -a system/sddm/TokyoNight /usr/local/share/sddm/themes/
```

The upstream image assets (`03-sway-fedora.jpg`, `rectangle.png`,
`angle-down.png`) and `metadata.desktop` are not version-controlled; copy them
from `/usr/share/sddm/themes/03-sway-fedora/` on any Fedora Sway Atomic system.
The login wallpaper (`tokyonight-login.png`) is user-provided and must be
copied from the original host — see [docs/assets.md](../docs/assets.md) section 6.
