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
#   2. Validates every manifest entry before writing any files.
#   3. For each valid entry, copies the backed-up file back to its
#      original destination.
#   4. Creates a safety copy of any current file before overwriting it,
#      so the recovery itself is reversible.
#   5. Reports what was restored and what was skipped.
#
# Security:
#   - Destination paths must be relative to $XDG_CONFIG_HOME and must
#     not contain traversal components or symlinks that escape the
#     config directory.
#   - Backup filenames must be simple filenames (no path components,
#     no traversal).
#   - The entire manifest is validated before any files are written.
#   - Malformed or duplicate entries are rejected.
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
# Manifest validation
# ---------------------------------------------------------------------------

# Validate a destination path:
# - must not be empty
# - must not be absolute
# - must not contain .. components
# - must not contain symlinks that escape CONFIG_DIR
# - must resolve to a path inside CONFIG_DIR
validate_dest() {
    local dest=$1

    if [ -z "$dest" ]; then
        printf 'recover.sh: manifest error: empty destination path\n' >&2
        return 1
    fi

    case $dest in
        /*)
            printf 'recover.sh: manifest error: destination path must not be absolute: %s\n' "$dest" >&2
            return 1
            ;;
    esac

    # Check for .. components
    local IFS=/
    local -a parts=($dest)
    local part
    for part in "${parts[@]}"; do
        if [ "$part" = ".." ]; then
            printf 'recover.sh: manifest error: destination path must not contain ..: %s\n' "$dest" >&2
            return 1
        fi
    done

    # Check for symlinks in the path that could escape CONFIG_DIR
    local check_path=$CONFIG_DIR
    for part in "${parts[@]}"; do
        if [ "$part" = "." ] || [ "$part" = "" ]; then
            continue
        fi
        check_path="$check_path/$part"
        if [ -L "$check_path" ]; then
            local link_target
            link_target=$(readlink -f "$check_path" 2>/dev/null) || {
                printf 'recover.sh: manifest error: cannot resolve symlink: %s\n' "$check_path" >&2
                return 1
            }
            case $link_target in
                "$CONFIG_DIR"/*) ;;
                *)
                    printf 'recover.sh: manifest error: symlink escapes config directory: %s -> %s\n' "$check_path" "$link_target" >&2
                    return 1
                    ;;
            esac
        fi
    done

    # Check that the resolved path is inside CONFIG_DIR
    local resolved
    resolved=$(cd "$CONFIG_DIR" 2>/dev/null && realpath -m "$dest" 2>/dev/null) || {
        printf 'recover.sh: manifest error: cannot resolve destination path: %s\n' "$dest" >&2
        return 1
    }

    case $resolved in
        "$CONFIG_DIR"/*) ;;
        *)
            printf 'recover.sh: manifest error: destination path escapes config directory: %s\n' "$dest" >&2
            return 1
            ;;
    esac

    return 0
}

# Validate a backup filename:
# - must not be empty
# - must not be absolute
# - must not contain path components (/)
# - must not be . or ..
validate_backup_name() {
    local name=$1

    if [ -z "$name" ]; then
        printf 'recover.sh: manifest error: empty backup filename\n' >&2
        return 1
    fi

    case $name in
        /*)
            printf 'recover.sh: manifest error: backup filename must not be absolute: %s\n' "$name" >&2
            return 1
            ;;
    esac

    case $name in
        */*)
            printf 'recover.sh: manifest error: backup filename must not contain path components: %s\n' "$name" >&2
            return 1
            ;;
    esac

    if [ "$name" = ".." ] || [ "$name" = "." ]; then
        printf 'recover.sh: manifest error: backup filename must not be . or ..: %s\n' "$name" >&2
        return 1
    fi

    return 0
}

# Parse and validate the entire manifest before writing any files.
# Sets VALIDATED_DESTS and VALIDATED_BACKUP_NAMES arrays.
declare -a VALIDATED_DESTS=()
declare -a VALIDATED_BACKUP_NAMES=()
declare -A SEEN_DESTS=()

validate_manifest() {
    local line_num=0
    local orig_path backup_name

    while IFS=$'\t' read -r orig_path backup_name || [ -n "$orig_path" ]; do
        line_num=$((line_num + 1))

        # Skip empty lines
        [ -z "$orig_path" ] && continue

        # Check for malformed lines (missing backup_name)
        if [ -z "$backup_name" ]; then
            printf 'recover.sh: manifest error line %d: missing backup filename\n' "$line_num" >&2
            return 1
        fi

        # Validate destination path
        if ! validate_dest "$orig_path"; then
            printf 'recover.sh: manifest error line %d: invalid destination: %s\n' "$line_num" "$orig_path" >&2
            return 1
        fi

        # Validate backup filename
        if ! validate_backup_name "$backup_name"; then
            printf 'recover.sh: manifest error line %d: invalid backup filename: %s\n' "$line_num" "$backup_name" >&2
            return 1
        fi

        # Check for duplicate destinations
        if [ -n "${SEEN_DESTS[$orig_path]:-}" ]; then
            printf 'recover.sh: manifest error line %d: duplicate destination: %s\n' "$line_num" "$orig_path" >&2
            return 1
        fi
        SEEN_DESTS[$orig_path]=1

        # Check that the backup file exists and is a regular file (not a symlink)
        if [ ! -f "$BACKUP_DIR/$backup_name" ] || [ -L "$BACKUP_DIR/$backup_name" ]; then
            printf 'recover.sh: manifest error line %d: backup file not found or not a regular file: %s\n' "$line_num" "$backup_name" >&2
            return 1
        fi

        VALIDATED_DESTS+=("$orig_path")
        VALIDATED_BACKUP_NAMES+=("$backup_name")
    done < "$BACKUP_DIR/manifest.txt"

    if [ ${#VALIDATED_DESTS[@]} -eq 0 ]; then
        printf 'recover.sh: manifest error: no valid entries found\n' >&2
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Recovery
# ---------------------------------------------------------------------------

restored=0
skipped=0
errors=0

printf 'Recovering from backup: %s\n' "$BACKUP_DIR"
printf '  config dir: %s\n' "$CONFIG_DIR"
printf '\n'

# Validate manifest first — no files are written if validation fails
if ! validate_manifest; then
    printf 'recover.sh: manifest validation failed — no files were written\n' >&2
    exit 1
fi

# Now perform recovery using only validated entries
for i in "${!VALIDATED_DESTS[@]}"; do
    orig_path=${VALIDATED_DESTS[$i]}
    backup_name=${VALIDATED_BACKUP_NAMES[$i]}
    backup_file="$BACKUP_DIR/$backup_name"
    dest="$CONFIG_DIR/$orig_path"

    # Safety: if a file already exists at the destination, back it up first
    # so this recovery is itself reversible.
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        safety_dir="$CONFIG_DIR/fedora-sway-restore-backups/pre-recovery-$(date +%Y%m%d-%H%M%S)-$$"
        mkdir -p "$safety_dir"
        # Use hash-suffixed name to prevent collisions between distinct paths
        # that would map to the same name after tr '/' '_' (e.g. a/b and a_b).
        safety_hash=$(printf '%s' "$orig_path" | sha256sum | cut -c1-16)
        safety_base=$(printf '%s' "$orig_path" | tr '/' '_')
        safety_name="${safety_base}-${safety_hash}"
        cp -P "$dest" "$safety_dir/$safety_name"
        printf '  [safety] current file saved to %s/%s\n' "$safety_dir" "$safety_name"
    fi

    mkdir -p -- "$(dirname -- "$dest")"
    cp -p -- "$backup_file" "$dest"
    printf '  [restored] %s\n' "$dest"
    restored=$((restored + 1))
done

printf '\nRecovery complete: %d restored, %d skipped, %d errors\n' "$restored" "$skipped" "$errors"

if [ "$errors" -gt 0 ]; then
    exit 1
fi
