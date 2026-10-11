# Fedora Sway Atomic — Tokyo Night Desktop

A version-controlled record of the Tokyo Night desktop customizations applied to
Fedora Sway Atomic 44.1.7.

## Repository structure

```text
Fedora-start-customization/
├── README.md                          This file
├── configs/
│   ├── sway/
│   │   └── config.d/                  Sway configuration fragments
│   │       ├── 10-wallpaper.conf
│   │       ├── 20-terminal.conf
│   │       ├── 70-window-spacing.conf
│   │       ├── 80-tokyonight-borders.conf
│   │       ├── 85-rofi-launcher.conf
│   │       ├── 90-terminal.conf
│   │       └── 95-lockscreen.conf
│   ├── alacritty/
│   │   └── alacritty.toml
│   ├── waybar/
│   │   ├── config.jsonc
│   │   └── style.css
│   ├── rofi/
│   │   ├── config.rasi
│   │   └── tokyonight.rasi
│   ├── dunst/
│   │   └── dunstrc
│   └── swaylock/
│       └── config
└── system/
    └── sddm/
        └── README.md                  SDDM theme documentation
```

## What is version-controlled

All files under `copies/` are copies of the active user configuration files.
They are safe to restore by copying back to `~/.config/`.

| Repository path | Restore target |
|-----------------|----------------|
| `configs/sway/config.d/*.conf` | `~/.config/sway/config.d/` |
| `configs/alacritty/alacritty.toml` | `~/.config/alacritty/alacritty.toml` |
| `configs/waybar/config.jsonc` | `~/.config/waybar/config.jsonc` |
| `configs/waybar/style.css` | `~/.config/waybar/style.css` |
| `configs/rofi/config.rasi` | `~/.config/rofi/config.rasi` |
| `configs/rofi/tokyonight.rasi` | `~/.config/rofi/tokyonight.rasi` |
| `configs/dunst/dunstrc` | `~/.config/dunst/dunstrc` |
| `configs/swaylock/config` | `~/.config/swaylock/config` |

## What is documented separately (not version-controlled)

The SDDM login theme lives under `/usr/local/` and `/etc/` — these are system
paths requiring root privileges. See [system/sddm/README.md](system/sddm/README.md)
for full documentation, preview instructions, and revert procedures.

Key system paths:

- `/etc/sddm.conf.d/99-tokyonight.conf` — theme selection override
- `/usr/local/share/sddm/themes/TokyoNight/` — custom theme directory
- `/usr/local/share/backgrounds/tokyonight-login.png` — login wallpaper

## Fedora's layered-include mechanism

Fedora's Sway configuration uses a layered-include system. The system
configuration at `/usr/share/sway/config` (or `/etc/sway/config`) ends with:

```
include '$(/usr/libexec/sway/layered-include \
  "/usr/share/sway/config.d/*.conf" \
  "/etc/sway/config.d/*.conf" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/sway/config.d/*.conf")'
```

The `/usr/libexec/sway/layered-include` script expands each glob pattern,
collects matching files, and layers them so that **files with the same name in
later directories override earlier ones**. The load order is:

1. `/usr/share/sway/config.d/*.conf` — Fedora packaged defaults
2. `/etc/sway/config.d/*.conf` — system-wide overrides
3. `~/.config/sway/config.d/*.conf` — user overrides (highest precedence)

This means a user file like `~/.config/sway/config.d/20-swayidle.conf` will
always be loaded instead of `/usr/share/sway/config.d/20-swayidle.conf` or
`/etc/sway/config.d/20-swayidle.conf`.

All custom Sway configuration lives in `~/.config/sway/config.d/` as numbered
fragments. The numbers control load order — later fragments can override
settings from earlier ones.

## Sway configuration fragments

### 10-wallpaper.conf

Sets the desktop wallpaper:

```
output * bg ~/.local/share/backgrounds/wallpaper.png fill
```

### 20-terminal.conf

Sets the `$term` variable to `alacritty`:

```
set $term alacritty
```

### 70-window-spacing.conf

Sets initial gap values:

```
gaps inner 6
gaps outer 3
```

### 80-tokyonight-borders.conf

Sets Tokyo Night window border colors and **overrides** the gap values from
`70-window-spacing.conf`:

```
default_border pixel 2
default_floating_border pixel 2

client.focused          #7aa2f7 #1a1b26 #c0caf5 #7aa2f7 #7aa2f7
client.unfocused        #414868 #1a1b26 #a9b1d6 #414868 #414868
client.focused_inactive #414868 #1a1b26 #a9b1d6 #414868 #414868
client.urgent           #f7768e #1a1b26 #c0caf5 #f7768e #f7768e

gaps outer 0
gaps inner 0
smart_gaps on
hide_edge_borders smart
```

**Effective gap configuration** (after both fragments are loaded):

| Setting | Value | Source |
|---------|-------|--------|
| `gaps inner` | `0` | Overridden by `80-tokyonight-borders.conf` |
| `gaps outer` | `0` | Overridden by `80-tokyonight-borders.conf` |
| `smart_gaps` | `on` | Set in `80-tokyonight-borders.conf` |
| `hide_edge_borders` | `smart` | Set in `80-tokyonight-borders.conf` |

**What this means in practice:**

- `smart_gaps on` — when there is only one window on a workspace, inner gaps
  are removed entirely so the window fills the full screen. When multiple
  windows are present, the configured inner gap applies.
- With `gaps inner 0` and `gaps outer 0`, windows touch each other and the
  screen edges with no spacing.
- `hide_edge_borders smart` — window borders are hidden when there is only one
  window on a workspace or when using stacked/tabbed layouts, reducing visual
  clutter.

This is a deliberate choice to maximize screen real estate. The `70-window-spacing.conf`
fragment is kept because it documents the initial spacing intent and may be
useful as a reference, but its gap values are overridden by `80-tokyonight-borders.conf`.

### 85-rofi-launcher.conf

Rebinds `$mod+d` from the default combi launcher to `rofi -show drun`:

```
unbindsym $mod+d
bindsym $mod+d exec rofi -show drun
```

### 90-terminal.conf

Rebinds `$mod+Return` from the default terminal to `alacritty`:

```
unbindsym $mod+Return
bindsym $mod+Return exec alacritty
```

### 95-lockscreen.conf

Binds `$mod+Escape` to Swaylock:

```
bindsym $mod+Escape exec swaylock --config ~/.config/swaylock/config
```

## Other application configurations

### Alacritty

`configs/alacritty/alacritty.toml` configures:

- Background opacity `0.75`
- Window padding `12` horizontal, `10` vertical
- JetBrainsMono Nerd Font at size `12`
- Blinking beam cursor (interval `550ms`)
- Tokyo Night color palette

### Waybar

`configs/waybar/config.jsonc` and `configs/waybar/style.css` configure:

- Bar position: bottom, height `32`
- Left: Sway workspaces
- Center: Clock
- Right: PulseAudio, Network, Battery, Tray
- Tokyo Night color scheme throughout

### Rofi

`configs/rofi/tokyonight.rasi` is a Tokyo Night color theme for Rofi.
`configs/rofi/config.rasi` points to it via `@theme`.

### Dunst

`configs/dunst/dunstrc` configures:

- Tokyo Night colors for background, foreground, and frame
- Urgency levels: low (5s timeout), normal (8s), critical (persistent)
- JetBrainsMono Nerd Font at size `10`
- Position: top-right with 12px offset

### Swaylock

`configs/swaylock/config` configures:

- Dark background `#1a1b26`
- Tokyo Night accent colors for ring, line, and text states
- JetBrainsMono Nerd Font at size `18`
- Failed attempt count display

## Restoring from this repository

To restore all version-controlled configuration files:

```bash
# Sway fragments
cp configs/sway/config.d/*.conf ~/.config/sway/config.d/

# Alacritty
cp configs/alacritty/alacritty.toml ~/.config/alacritty/

# Waybar
cp configs/waybar/config.jsonc ~/.config/waybar/
cp configs/waybar/style.css ~/.config/waybar/

# Rofi
cp configs/rofi/config.rasi ~/.config/rofi/
cp configs/rofi/tokyonight.rasi ~/.config/rofi/

# Dunst
cp configs/dunst/dunstrc ~/.config/dunst/

# Swaylock
cp configs/swaylock/config ~/.config/swaylock/
```

After restoring, reload Sway:

```bash
swaymsg reload
```

Note: `swaymsg reload` reloads Sway configuration but does not necessarily reload
each application's own stylesheet. Restart individual applications if changes
do not appear.

## Verification

### Checks performed during repository creation

| Check | Result |
|-------|--------|
| All 7 Sway fragments present in `~/.config/sway/config.d/` | Confirmed |
| Alacritty config present | Confirmed |
| Waybar config and stylesheet present | Confirmed |
| Rofi theme and config present | Confirmed |
| Dunst config present | Confirmed |
| Swaylock config present | Confirmed |
| SDDM override file present at `/etc/sddm.conf.d/99-tokyonight.conf` | Confirmed |
| SDDM theme directory present at `/usr/local/share/sddm/themes/TokyoNight/` | Confirmed |
| Login wallpaper present at `/usr/local/share/backgrounds/tokyonight-login.png` | Confirmed |
| Layered-include mechanism present at `/usr/libexec/sway/layered-include` | Confirmed |
| No private paths in copied files | Confirmed |
| Backup files excluded from snapshot | Confirmed |

### Checks to perform after restoring

Run these commands from a terminal in the Sway session:

```bash
# Sway version and loaded configuration
sway --version
swaymsg -t get_config

# Confirm the font is resolvable
fc-match "JetBrainsMono Nerd Font"

# Check whether Waybar is running
pgrep -a waybar

# Check SDDM service state
systemctl is-enabled sddm
systemctl is-active sddm

# Inspect SDDM theme selection
cat /etc/sddm.conf.d/99-tokyonight.conf
```

To preview the SDDM theme without logging out:

```bash
/usr/bin/sddm-greeter-qt6 --test-mode \
  --theme /usr/local/share/sddm/themes/TokyoNight
```

### Manual acceptance checklist

- [ ] Wallpaper appears and fills the display
- [ ] Alacritty uses the expected font, opacity, padding, cursor, and palette
- [ ] Waybar appears at the bottom with the expected modules and colors
- [ ] Window borders use Tokyo Night colors (focused: blue, unfocused: slate, urgent: red)
- [ ] Single window fills the screen with no gaps
- [ ] Multiple windows have no spacing between them or screen edges
- [ ] `Super+D` opens Rofi
- [ ] `Super+Return` opens Alacritty
- [ ] Dunst notifications use the custom theme
- [ ] `Super+Escape` locks the screen using Swaylock
- [ ] GTK applications use the dark theme and Papirus-Dark icons
- [ ] SDDM preview shows the wallpaper, lower-right panel, readable text, and consistent buttons
- [ ] A normal logout/login works before relying on the custom SDDM theme
- [ ] The configuration still works after a reboot

## Notes

- This repository does not include an installer script. Restoration is manual.
- The SDDM theme is documented separately under `system/sddm/` and requires
  root privileges to install.
- Backup files (`.bak`, `.before-*`) were excluded from this snapshot but
  remain on the host system.
- The `70-window-spacing.conf` fragment is kept even though its gap values are
  overridden by `80-tokyonight-borders.conf`. This is intentional — it documents
  the initial spacing configuration and the override relationship between
  fragments.
