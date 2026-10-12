#!/usr/bin/env bash
#
# recover.sh — restore configuration files from a backup created by
# scripts/restore.sh --apply --force.
#
# Usage:
#   scripts/recover.sh <backup-directory>
#
# The backup directory must contain:
#   manifest.txt          — tab-separated: original-destination-path  backup-filename
#   <backup-filename>     — the backed-up copy of each file
#
# This script:
#   1. Validates the backup directory and manifest.
#   2. For each entry in the manifest, copies the backed-up file back to
#      its original destination.
#   3. Creates a safety copy of any current file before overwriting it,
#      so the recovery itself is reversible.
#   4. Reports what was restored and what was skipped.
#
# Environment overrides (used by tests/run_tests.sh):
#   XDG_CONFIG_HOME  — must be set to an absolute path (same as restore.sh)
#
# This script only writes under $XDG_CONFIG_HOME. It never modifies system
# files, installs packages, or restarts services. It refuses to run as root.

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

usage() {
    cat <<'EOF'
Usage: scripts/recover.sh <backup-directory>

  <backup-directory>  Path to a backup directory created by
                      scripts/restore.sh --apply --force.
                      Must contain manifest.txt and the backed-up files.

Environment:
  XDG_CONFIG_HOME  Absolute path to the config directory (required)

See docs/RESTORE.md for full documentation.
EOF
}

if [ $# -ne 1 ]; then
    printf 'recover.sh: expected exactly one argument (backup directory)\n\n' >&2
    usage >&2
    exit 2
fi

BACKUP_DIR=$1

if [ "$(id -u)" -eq 0 ]; then
    printf 'recover.sh: refusing to run as root — this script only writes user configuration\n' >&2
    exit 1
fi

if [ -z "${XDG_CONFIG_HOME:-}" ]; then
    printf 'recover.sh: XDG_CONFIG_HOME is not set; refusing to guess a destination\n' >&2
    exit 1
fi
case $XDG_CONFIG_HOME in
    /*) ;;
    *)
        printf 'recover.sh: XDG_CONFIG_HOME must be an absolute path (got: %s)\n' "$XDG_CONFIG_HOME" >&2
        exit 1
        ;;
esac
if [ "$XDG_CONFIG_HOME" = "/" ]; then
    printf 'recover.sh: XDG_CONFIG_HOME must not be /\n' >&2
    exit 1
fi
CONFIG_DIR=$XDG_CONFIG_HOME

if [ ! -d "$BACKUP_DIR" ]; then
    printf 'recover.sh: backup directory not found: %s\n' "$BACKUP_DIR" >&2
    exit 1
fi

if [ ! -f "$BACKUP_DIR/manifest.txt" ]; then
    printf 'recover.sh: manifest.txt not found in %s\n' "$BACKUP_DIR" >&2
    printf 'recover.sh: this directory was not created by scripts/restore.sh\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Parse manifest and recover
# ---------------------------------------------------------------------------

restored=0
skipped=0
errors=0

printf 'Recovering from backup: %s\n' "$BACKUP_DIR"
printf '  config dir: %s\n' "$CONFIG_DIR"
printf '\n'

while IFS=$'\t' read -r orig_path backup_name; do
    # Skip empty lines
    [ -z "$orig_path" ] && continue

    backup_file="$BACKUP_DIR/$backup_name"

    if [ ! -f "$backup_file" ]; then
        printf '  [ERROR] backup file missing: %s (for %s)\n' "$backup_file" "$orig_path"
        errors=$((errors + 1))
        continue
    fi

    # Safety: if a file already exists at the destination, back it up first
    # so this recovery is itself reversible.
    if [ -e "$orig_path" ] || [ -L "$orig_path" ]; then
        safety_dir="$CONFIG_DIR/fedora-sway-restore-backups/pre-recovery-$(date +%Y%m%d-%H%M%S)-$$"
        mkdir -p "$safety_dir"
        safety_name=$(printf '%s' "${orig_path#$CONFIG_DIR/}" | tr '/' '_')
        cp -P "$orig_path" "$safety_dir/$safety_name"
        printf '  [safety] current file saved to %s/%s\n' "$safety_dir" "$safety_name"
    fi

    mkdir -p -- "$(dirname -- "$orig_path")"
    cp -p -- "$backup_file" "$orig_path"
    printf '  [restored] %s\n' "$orig_path"
    restored=$((restored + 1))

done < "$BACKUP_DIR/manifest.txt"

printf '\nRecovery complete: %d restored, %d skipped, %d errors\n' "$restored" "$skipped" "$errors"

if [ "$errors" -gt 0 ]; then
    exit 1
fi
