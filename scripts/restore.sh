#!/usr/bin/env bash
#
# restore.sh — install this repository's Fedora Sway Atomic desktop
# configuration into the user's XDG config directory.
#
# Modes:
#   --dry-run   Preview every action without making changes (DEFAULT).
#               Creates no files, no backups, and changes nothing.
#   --apply     Apply changes. Missing files are installed; files that
#               already match are skipped; files that DIFFER from the
#               repository are reported as conflicts and left untouched
#               unless --force is given.
#   --check     Pre-flight check. Verifies the system, external assets,
#               and configuration conflicts without making changes.
#               Exits 1 if anything needs attention, 0 if all is well.
#
# Modifiers:
#   --force     Only meaningful with --apply: back up existing files that
#               differ from the repository, then replace them. Without
#               --force, differing files are never overwritten.
#
# Backups:
#   Replacement only happens with --apply --force. Before a file is
#   replaced, the previous version is copied to
#     $XDG_CONFIG_HOME/fedora-sway-restore-backups/<timestamp>-<pid>/
#   together with a manifest.txt. Recover with:
#     scripts/recover.sh <backup-directory>
#   See docs/RESTORE.md for details.
#
# Environment overrides (used by tests/run_tests.sh):
#   OS_RELEASE_FILE  path to os-release      (default: /etc/os-release)
#   SWAY_BIN         path to sway binary     (default: found via PATH)
#
# This script only writes under $XDG_CONFIG_HOME (default ~/.config).
# It never modifies system files, installs packages, downloads assets,
# touches SDDM, or restarts services. It refuses to run as root.

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

MODE="dry-run"
FORCE=0

usage() {
    cat <<'EOF'
Usage: scripts/restore.sh [--dry-run | --apply | --check] [--force]

  --dry-run   Preview all actions without making changes (default)
  --apply     Install missing files; skip matching files; report conflicts
  --check     Pre-flight check; exits 1 if anything needs attention
  --force     With --apply: back up and replace differing files
  -h, --help  Show this help

See docs/RESTORE.md for full documentation.
EOF
}

for arg in "$@"; do
    case $arg in
        --dry-run) MODE="dry-run" ;;
        --apply)   MODE="apply" ;;
        --check)   MODE="check" ;;
        --force)   FORCE=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            printf 'restore.sh: unknown argument: %s\n\n' "$arg" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ "$(id -u)" -eq 0 ]; then
    printf 'restore.sh: refusing to run as root — this script only writes user configuration\n' >&2
    exit 1
fi

if [ -z "${XDG_CONFIG_HOME:-}" ]; then
    printf 'restore.sh: XDG_CONFIG_HOME is not set; refusing to guess a destination\n' >&2
    exit 1
fi
case $XDG_CONFIG_HOME in
    /*) ;;
    *)
        printf 'restore.sh: XDG_CONFIG_HOME must be an absolute path (got: %s)\n' "$XDG_CONFIG_HOME" >&2
        exit 1
        ;;
esac
if [ "$XDG_CONFIG_HOME" = "/" ]; then
    printf 'restore.sh: XDG_CONFIG_HOME must not be /\n' >&2
    exit 1
fi
CONFIG_DIR=$XDG_CONFIG_HOME

# ---------------------------------------------------------------------------
# System checks
# ---------------------------------------------------------------------------

os_release_file=${OS_RELEASE_FILE:-/etc/os-release}
if [ ! -r "$os_release_file" ]; then
    printf 'restore.sh: cannot read %s\n' "$os_release_file" >&2
    exit 1
fi
if ! grep -qx 'ID=fedora' "$os_release_file"; then
    printf 'restore.sh: unsupported system: %s (expected ID=fedora)\n' "$os_release_file" >&2
    printf 'restore.sh: this repository targets Fedora Sway Atomic\n' >&2
    exit 1
fi

sway_bin=${SWAY_BIN:-$(command -v sway || true)}
if [ -z "${sway_bin:-}" ] || [ ! -x "$sway_bin" ]; then
    printf 'restore.sh: sway was not found — this repository configures a Sway desktop\n' >&2
    printf 'restore.sh: install sway (e.g. rpm-ostree install sway) and retry\n' >&2
    exit 1
fi

for dir in \
    "$REPO_ROOT/configs/sway/config.d" \
    "$REPO_ROOT/configs/alacritty" \
    "$REPO_ROOT/configs/waybar" \
    "$REPO_ROOT/configs/rofi" \
    "$REPO_ROOT/configs/dunst" \
    "$REPO_ROOT/configs/swaylock" \
    "$REPO_ROOT/configs/gtk" \
    "$REPO_ROOT/system/sddm/TokyoNight"
do
    if [ ! -d "$dir" ]; then
        printf 'restore.sh: repository component missing: %s\n' "$dir" >&2
        printf 'restore.sh: run this script from a checkout of Fedora-start-customization\n' >&2
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# External asset checks (never fatal for install; fatal in --check mode)
# ---------------------------------------------------------------------------

asset_problems=0

warn_missing() {
    printf '  [WARN] %s\n' "$1"
    asset_problems=$((asset_problems + 1))
}

check_assets() {
    local xdg_data_home=${XDG_DATA_HOME:-$HOME/.local/share}

    if [ ! -f "$HOME/.local/share/backgrounds/wallpaper.png" ]; then
        warn_missing "wallpaper not found: $HOME/.local/share/backgrounds/wallpaper.png (referenced by configs/sway/config.d/10-wallpaper.conf) — see docs/assets.md section 1"
    fi

    local theme_found=0
    for d in "$HOME/.themes/Tokyonight-BL-MB-Dark-Moon" "$xdg_data_home/themes/Tokyonight-BL-MB-Dark-Moon"; do
        [ -d "$d" ] && theme_found=1
    done
    if [ "$theme_found" -eq 0 ]; then
        warn_missing "GTK theme not found: Tokyonight-BL-MB-Dark-Moon (looked in ~/.themes and \$XDG_DATA_HOME/themes) — see docs/assets.md section 3"
    fi

    local icon_found=0
    for d in "$HOME/.local/share/icons/Papirus-Dark" "$xdg_data_home/icons/Papirus-Dark"; do
        [ -d "$d" ] && icon_found=1
    done
    if [ "$icon_found" -eq 0 ]; then
        warn_missing "icon theme not found: Papirus-Dark (looked in ~/.local/share/icons and \$XDG_DATA_HOME/icons) — see docs/assets.md section 4"
    fi

    if command -v fc-list >/dev/null 2>&1; then
        if ! fc-list | grep -qi 'JetBrainsMono Nerd Font'; then
            warn_missing "font not resolvable: JetBrainsMono Nerd Font — terminal, waybar, dunst, and swaylock expect it (see docs/assets.md section 2)"
        fi
    else
        warn_missing "fc-list not available; could not verify the JetBrainsMono Nerd Font installation"
    fi

    # SDDM is a documented manual component — informational only.
    if [ -d /usr/local/share/sddm/themes/TokyoNight ]; then
        printf '  [INFO] SDDM TokyoNight theme found (manual component, not managed by this script)\n'
    else
        printf '  [INFO] SDDM TokyoNight theme not installed — manual install required, see system/sddm/README.md\n'
    fi
}

# ---------------------------------------------------------------------------
# Component table
# ---------------------------------------------------------------------------
# Repository-relative source path -> CONFIG_DIR-relative destination path.
COMPONENTS=(
    "configs/alacritty/alacritty.toml|alacritty/alacritty.toml"
    "configs/waybar/config.jsonc|waybar/config.jsonc"
    "configs/waybar/style.css|waybar/style.css"
    "configs/rofi/config.rasi|rofi/config.rasi"
    "configs/rofi/tokyonight.rasi|rofi/tokyonight.rasi"
    "configs/dunst/dunstrc|dunst/dunstrc"
    "configs/swaylock/config|swaylock/config"
    "configs/gtk/gtk-3.0/settings.ini|gtk-3.0/settings.ini"
    "configs/gtk/gtk-4.0/settings.ini|gtk-4.0/settings.ini"
)

# ---------------------------------------------------------------------------
# Evaluation
# ---------------------------------------------------------------------------

# decide_action <src> <dst> -> prints: missing | identical | differs | directory
decide_action() {
    local src=$1 dst=$2
    if [ -d "$dst" ]; then
        printf 'directory'
    return
    fi
    if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
        printf 'missing'
        return
    fi
    if cmp -s "$src" "$dst"; then
        printf 'identical'
    else
        printf 'differs'
    fi
}

count_missing=0
count_identical=0
count_conflicts=0
count_replaced=0
count_errors=0
declare -a PLAN_OPS=()   # human-readable plan lines
declare -a EXEC_SRC=()   # files to act on in pass 2
declare -a EXEC_DST=()
declare -a EXEC_OP=()    # "install" | "replace"

evaluate_components() {
    local entry src_rel dst_rel src dst action
    for entry in "${COMPONENTS[@]}"; do
        src_rel=${entry%%|*}
        dst_rel=${entry#*|}
        src="$REPO_ROOT/$src_rel"
        dst="$CONFIG_DIR/$dst_rel"
        action=$(decide_action "$src" "$dst")
        record_action "$src_rel" "$dst_rel" "$action" "$dst"
    done

    # Sway fragments (glob, preserving repository load order)
    local f base
    for f in "$REPO_ROOT/configs/sway/config.d"/*.conf; do
        [ -e "$f" ] || continue
        base=$(basename "$f")
        action=$(decide_action "$f" "$CONFIG_DIR/sway/config.d/$base")
        record_action "configs/sway/config.d/$base" "sway/config.d/$base" "$action" "$CONFIG_DIR/sway/config.d/$base"
    done
}

record_action() {
    local src_rel=$1 dst_rel=$2 action=$3 dst=$4
    case $action in
        missing)
            count_missing=$((count_missing + 1))
            PLAN_OPS+=("[install]     $dst_rel (does not exist yet)")
            if [ "$MODE" = "apply" ]; then
                EXEC_SRC+=("$REPO_ROOT/$src_rel")
                EXEC_DST+=("$dst")
                EXEC_OP+=("install")
            fi
            ;;
        identical)
            count_identical=$((count_identical + 1))
            PLAN_OPS+=("[up-to-date]  $dst_rel (identical to repository)")
            ;;
        differs)
            if [ "$MODE" = "apply" ] && [ "$FORCE" -eq 1 ]; then
                count_replaced=$((count_replaced + 1))
                PLAN_OPS+=("[replace]     $dst_rel (differs — will be backed up first)")
                EXEC_SRC+=("$REPO_ROOT/$src_rel")
                EXEC_DST+=("$dst")
                EXEC_OP+=("replace")
            else
                count_conflicts=$((count_conflicts + 1))
                PLAN_OPS+=("[conflict]    $dst_rel differs from repository — left untouched; needs manual review (use --force to replace after backup)")
            fi
            ;;
        directory)
            count_errors=$((count_errors + 1))
            PLAN_OPS+=("[error]       $dst_rel exists as a directory — manual intervention required")
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Execution (apply mode only)
# ---------------------------------------------------------------------------
#
# Partial-application limitation: if the script is interrupted (e.g. SIGINT,
# SIGTERM, or a disk-full error) after some files have been installed but
# before others, the configuration directory will be in a partially-applied
# state. Re-running the script will complete the installation — files that
# already match are skipped, and missing files are installed. Backups are
# only created for files that are replaced with --force.

backup_dir=""

# Generate a unique backup filename for a destination path.
# Uses a hash of the path to avoid collisions between different destination
# paths that would map to the same name after tr '/' '_'.
backup_filename() {
    local dst=$1
    local rel=${dst#$CONFIG_DIR/}
    local hash
    hash=$(printf '%s' "$rel" | sha256sum | cut -c1-16)
    local base
    base=$(printf '%s' "$rel" | tr '/' '_')
    printf '%s-%s' "$base" "$hash"
}

execute_plan() {
    local i src dst op backup_name
    for i in "${!EXEC_SRC[@]}"; do
        src=${EXEC_SRC[$i]}
        dst=${EXEC_DST[$i]}
        op=${EXEC_OP[$i]}
        if [ "$op" = "replace" ]; then
            if [ -z "$backup_dir" ]; then
                backup_dir="$CONFIG_DIR/fedora-sway-restore-backups/$(date +%Y%m%d-%H%M%S)-$$"
                mkdir -p "$backup_dir"
                : > "$backup_dir/manifest.txt"
            fi
            backup_name=$(backup_filename "$dst")
            # Verify backup succeeds before removing the original
            if ! cp -P "$dst" "$backup_dir/$backup_name"; then
                printf 'restore.sh: backup failed for %s — skipping replacement\n' "$dst" >&2
                count_errors=$((count_errors + 1))
                continue
            fi
            # Verify the backup file exists and is non-empty
            if [ ! -s "$backup_dir/$backup_name" ]; then
                printf 'restore.sh: backup verification failed for %s — skipping replacement\n' "$dst" >&2
                count_errors=$((count_errors + 1))
                continue
            fi
            printf '%s\t%s\n' "${dst#$CONFIG_DIR/}" "$backup_name" >> "$backup_dir/manifest.txt"
            rm -f -- "$dst"
        fi
        mkdir -p -- "$(dirname -- "$dst")"
        cp -p -- "$src" "$dst"
        printf '  [done] %s -> %s\n' "$op" "$dst"
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

printf 'Fedora Sway Atomic configuration restore\n'
printf '  repository : %s\n' "$REPO_ROOT"
printf '  config dir : %s\n' "$CONFIG_DIR"
printf '  mode       : %s%s\n' "$MODE" "$([ "$FORCE" -eq 1 ] && printf ' --force' || true)"
printf '\n'

check_assets
printf '\n'

evaluate_components

if [ "$MODE" = "check" ]; then
    printf 'Check results:\n'
    for line in "${PLAN_OPS[@]}"; do
        printf '  %s\n' "$line"
    done
    printf '\n'
    check_failures=$((asset_problems + count_conflicts + count_errors))
    if [ "$check_failures" -gt 0 ]; then
        printf 'CHECK FAILED: %d missing asset(s), %d conflict(s), %d error(s)\n' \
            "$asset_problems" "$count_conflicts" "$count_errors"
        printf 'See docs/assets.md for external assets and docs/RESTORE.md for conflicts.\n'
        exit 1
    fi
    printf 'CHECK PASSED: %d file(s) up to date, %d file(s) to install, no conflicts, no missing assets.\n' \
        "$count_identical" "$count_missing"
    exit 0
fi

printf 'Planned actions (%d to install, %d up to date, %d conflict(s) skipped, %d to replace, %d error(s)):\n' \
    "$count_missing" "$count_identical" "$count_conflicts" "$count_replaced" "$count_errors"
for line in "${PLAN_OPS[@]}"; do
    printf '  %s\n' "$line"
done
printf '\n'

if [ "$MODE" = "apply" ]; then
    execute_plan
    printf '\nSummary: installed %d, up-to-date %d, replaced %d (backed up), conflicts skipped %d, errors %d\n' \
        "$count_missing" "$count_identical" "$count_replaced" "$count_conflicts" "$count_errors"
    if [ -n "$backup_dir" ]; then
        printf 'Backups: %s (recover with: scripts/recover.sh %s)\n' "$backup_dir" "$backup_dir"
    fi
    if [ "$count_conflicts" -gt 0 ]; then
        printf 'Conflicts need manual review — re-run with --force to replace them (backups are created).\n'
    fi
    if [ "$asset_problems" -gt 0 ]; then
        printf 'Warning: %d external asset(s) missing — some configuration may not render as expected (docs/assets.md).\n' "$asset_problems"
    fi
    if [ "$count_errors" -gt 0 ]; then
        exit 1
    fi
else
    printf 'Dry run — no changes were made. Re-run with --apply to install.\n'
    if [ "$count_conflicts" -gt 0 ]; then
        printf 'Conflicts need manual review — use --apply --force to replace them (backups are created).\n'
    fi
fi
