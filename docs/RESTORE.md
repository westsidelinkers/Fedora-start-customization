# Restoration guide

This document describes the safe restoration workflow for the user-level
desktop configuration in this repository. It covers the restoration script,
backup and recovery procedures, conflict handling, and known limitations.

## Overview

The restoration script (`scripts/restore.sh`) installs the repository's
configuration files into the user's XDG config directory
(`~/.config` by default). It is designed to be:

- **Safe** — never overwrites files without explicit `--force`.
- **Idempotent** — rerunning it produces no unnecessary changes.
- **Auditable** — every action is reported before and after execution.
- **Non-destructive** — backups are created before any replacement.
- **Non-privileged** — runs as a regular user, refuses root, never touches
  system files.

## Prerequisites

- Fedora Sway Atomic (the script checks `ID=fedora` in `/etc/os-release`).
- Sway installed and available on `PATH`.
- `XDG_CONFIG_HOME` set to an absolute path (defaults to `~/.config` if
  unset, but the script requires it to be explicitly set or defaults
  correctly — see note below).

> **Note:** If `XDG_CONFIG_HOME` is unset, the script refuses to run rather
> than guessing. Set it explicitly:
> ```bash
> export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
> ```

## Modes

### `--dry-run` (default)

Previews every action without making any changes. Creates no files, no
backups, and modifies nothing. This is the default mode.

```bash
scripts/restore.sh --dry-run
```

### `--check`

Pre-flight check. Verifies the system, external assets, and configuration
conflicts without making changes. Exits 1 if anything needs attention
(missing assets, conflicts, or errors), 0 if all is well.

```bash
scripts/restore.sh --check
```

### `--apply`

Installs missing files, skips files that already match the repository, and
reports files that differ as conflicts (left untouched). Use `--force` to
back up and replace conflicting files.

```bash
scripts/restore.sh --apply
```

### `--apply --force`

Backs up existing files that differ from the repository, then replaces them.
Backups are created under:

```
$XDG_CONFIG_HOME/fedora-sway-restore-backups/<timestamp>-<pid>/
```

Each backup directory contains:
- `manifest.txt` — tab-separated list of original paths and backup filenames
- The backed-up files themselves

```bash
scripts/restore.sh --apply --force
```

## What gets installed

| Repository path | Destination |
|-----------------|-------------|
| `configs/sway/config.d/*.conf` | `~/.config/sway/config.d/` |
| `configs/alacritty/alacritty.toml` | `~/.config/alacritty/alacritty.toml` |
| `configs/waybar/config.jsonc` | `~/.config/waybar/config.jsonc` |
| `configs/waybar/style.css` | `~/.config/waybar/style.css` |
| `configs/rofi/config.rasi` | `~/.config/rofi/config.rasi` |
| `configs/rofi/tokyonight.rasi` | `~/.config/rofi/tokyonight.rasi` |
| `configs/dunst/dunstrc` | `~/.config/dunst/dunstrc` |
| `configs/swaylock/config` | `~/.config/swaylock/config` |
| `configs/gtk/gtk-3.0/settings.ini` | `~/.config/gtk-3.0/settings.ini` |
| `configs/gtk/gtk-4.0/settings.ini` | `~/.config/gtk-4.0/settings.ini` |

Sway fragments are installed into the user-level layered-include directory
(`~/.config/sway/config.d/`), preserving Fedora's layered-include mechanism.
The main system Sway configuration is never modified.

## Conflict handling

When a file at the destination differs from the repository version:

1. **Without `--force`:** the file is reported as a conflict and left
   untouched. The script continues with other files.
2. **With `--force`:** the existing file is backed up, then replaced with
   the repository version.

Conflicts are reported in the output with the `[conflict]` tag. Review them
before using `--force`.

## Recovery

To restore files from a backup created by `--apply --force`:

```bash
scripts/recover.sh <backup-directory>
```

For example:

```bash
scripts/recover.sh ~/.config/fedora-sway-restore-backups/20261012-143022-12345
```

The recovery script:
1. Validates the backup directory and manifest.
2. For each entry, copies the backed-up file to its original destination.
3. Creates a safety copy of any current file before overwriting it, so the
   recovery is itself reversible.
4. Reports what was restored.

## External assets

The restoration script checks for external assets (wallpaper, fonts, GTK
theme, icon theme) and reports warnings if any are missing. These assets are
**not** installed by the script. See [docs/assets.md](assets.md) for the
complete inventory and manual installation instructions.

Key points:
- **Wallpaper** (`~/.local/share/backgrounds/wallpaper.png`) — manual placement.
- **JetBrainsMono Nerd Font** — download from the official Nerd Fonts release.
- **GTK theme** (`Tokyonight-BL-MB-Dark-Moon`) — manual install to `~/.themes/`.
- **Papirus-Dark icons** — install as a package (`rpm-ostree install papirus-icon-theme`).

## SDDM (manual, root-required)

The SDDM login theme is a system-level component that requires root
privileges. The restoration script **never** touches SDDM configuration.
See [system/sddm/README.md](../system/sddm/README.md) for the complete
manual installation procedure.

## Testing

The test suite verifies the restoration script's behavior using temporary
directories and fixture configurations. See [tests/run_tests.sh](../tests/run_tests.sh).

Run tests with:

```bash
tests/run_tests.sh
```

Tests verify:
1. Dry-run mode makes no filesystem changes.
2. First application installs expected files.
3. Second application is idempotent.
4. Conflicting files are preserved and reported.
5. Backups are created before replacement.
6. Recovery restores from backups.
7. Missing assets are reported without corrupting configuration.
8. Unsupported systems or invalid arguments fail clearly.
9. Paths containing spaces are handled safely.
10. No test targets the real home directory or system configuration.

## Known limitations

- **Sway configuration validation:** The script does not run `swaymsg` or
  reload Sway. Syntax checking Sway configuration requires a running session
  or could change the live desktop. Validate manually with `swaymsg -t get_config`
  after reloading.
- **Application reload:** The script does not restart Waybar, Dunst, or any
  other application. Restart individual applications after restoration if
  changes do not appear.
- **GTK theme assets:** The GTK theme and icon theme are external assets.
  The script warns if they are missing but does not install them.
- **SDDM:** Entirely manual. The script only reports whether the theme
  directory exists.
- **Font installation:** The script checks font availability but does not
  install fonts.
- **Qt/KDE applications:** Not covered by this repository. Qt applications
  use their own theming stack (`qt6ct`, `kvantum`).
