# GTK theme and icon settings

This directory captures the GTK 3 and GTK 4 settings that reproduce the
Tokyo Night look of GTK applications on this desktop.

The GTK theme (`Tokyonight-BL-MB-Dark-Moon`) is derived from
[Fausto-Korpsvart/Tokyonight-GTK-Theme](https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme)
(GPL-3.0). See [docs/assets.md](../docs/assets.md) section 3 for download
and installation instructions.

## What is captured

Only the values that are **explicitly configured** in the active environment:

| Key | Value | Mechanism in active environment |
|-----|-------|---------------------------------|
| `gtk-theme-name` | `Tokyonight-BL-MB-Dark-Moon` | dconf (`org.gnome.desktop.interface gtk-theme`) |
| `gtk-icon-theme-name` | `Papirus-Dark` | dconf (`org.gnome.desktop.interface icon-theme`) |
| `gtk-application-prefer-dark-theme` | `1` | dconf `color-scheme='prefer-dark'` and `~/.config/gtk-3.0/settings.ini` |

These two files are installed by the restoration script
(`scripts/restore.sh`) to:

- `~/.config/gtk-3.0/settings.ini` (GTK 3)
- `~/.config/gtk-4.0/settings.ini` (GTK 4)

## What is NOT captured, and why

The following are **not explicitly configured** — GTK resolves them from
dconf schema defaults. They are documented here so the defaults are visible,
but no configuration files are created for them:

- **Cursor theme** — `Adwaita` (dconf default). Note that the
  `Tokyonight-BL-MB-Dark-Moon` theme's `index.theme` references
  `CursorTheme=Tokyonight-BL-MB-cursors`, but that cursor theme is not
  installed, so the Adwaita default applies.
- **GTK font** — `Adwaita Sans 11` (dconf default). Application fonts are set
  per application (JetBrainsMono Nerd Font in the Alacritty, Waybar, Dunst,
  and Swaylock configurations).

## Configuration mechanism and precedence

GTK resolves settings from two places, in this order:

1. **XDG `settings.ini`** (`~/.config/gtk-3.0/settings.ini`,
   `~/.config/gtk-4.0/settings.ini`) — takes precedence over dconf for every
   key it defines.
2. **dconf** (the database behind `gsettings`, keys under
   `org.gnome.desktop.interface`) — used for any key not present in
   `settings.ini`.

In the current environment both mechanisms hold the same values, so
installing these files does not change behavior — it makes the setup
independent of dconf and therefore easier to reproduce on a fresh system.
Do not set the same key in both places with different values; the
`settings.ini` value wins and the dconf value becomes invisible, which makes
the effective configuration confusing to audit.

The wallpaper is **not** a GTK setting. It is set by the Sway fragment
`configs/sway/config.d/10-wallpaper.conf` and applied by `swaybg`.

## Scope and limitations

- These settings affect **GTK 3 and GTK 4 applications only** (e.g. Firefox,
  GNOME apps, file choosers). They do not affect:
  - **Qt / KDE applications**, which use their own configuration
    (`~/.config/kdeglobals`, `~/.config/Trolltech.conf`) and the
    `qt6ct`/`kvantum` theming stack if installed.
  - **Terminal, Waybar, Dunst, Swaylock, and SDDM**, which embed their own
    fonts and colors in their respective configuration files.
  - **Sway itself** (window borders, gaps), which is configured by the
    Sway fragments.
- The dark-theme preference is per-toolkit. An application using a different
  toolkit or a built-in theme (e.g. Alacritty) follows its own configuration.

## Verification

Compare the captured values with the active environment:

```bash
# Active GTK theme, icon theme, and color scheme (dconf/gsettings)
gsettings get org.gnome.desktop.interface gtk-theme
gsettings get org.gnome.desktop.interface icon-theme
gsettings get org.gnome.desktop.interface color-scheme

# Equivalent dconf reads
dconf read /org/gnome/desktop/interface/gtk-theme
dconf read /org/gnome/desktop/interface/icon-theme
dconf read /org/gnome/desktop/interface/color-scheme

# Effective XDG settings (after restoration)
cat ~/.config/gtk-3.0/settings.ini
cat ~/.config/gtk-4.0/settings.ini

# Theme and icon theme assets are installed
ls -d ~/.themes/Tokyonight-BL-MB-Dark-Moon
ls -d ~/.local/share/icons/Papirus-Dark
```

Expected values:

```
'Tokyonight-BL-MB-Dark-Moon'
'Papirus-Dark'
'prefer-dark'
```

`color-scheme='prefer-dark'` corresponds to
`gtk-application-prefer-dark-theme=1` in `settings.ini`; both mechanisms
express the same preference.

To confirm the settings are actually applied to a GTK application, open any
GTK 3/4 application and check that it renders with the Tokyo Night dark theme
and Papirus-Dark icons.
