#!/usr/bin/env bash
#
# run_tests.sh — test suite for scripts/restore.sh and scripts/recover.sh
#
# Tests run in isolated temporary directories. No test touches the real
# home directory or system configuration.
#
# Usage:
#   tests/run_tests.sh            Run all tests
#   tests/run_tests.sh -v         Run with verbose output
#
# Exit code: 0 if all tests pass, 1 if any test fails.

set -uo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

VERBOSE=0
if [ "${1:-}" = "-v" ] || [ "${1:-}" = "--verbose" ]; then
    VERBOSE=1
fi

# ---------------------------------------------------------------------------
# Test infrastructure
# ---------------------------------------------------------------------------

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

PASS() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf '  PASS: %s\n' "$1"
}

FAIL() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$1")
    printf '  FAIL: %s\n' "$1"
    if [ "$#" -ge 2 ] && [ -n "$2" ]; then
        printf '        %s\n' "$2"
    fi
}

# assert_equals <description> <expected> <actual>
assert_equals() {
    if [ "$2" = "$3" ]; then
        PASS "$1"
    else
        FAIL "$1" "expected: [$2]  actual: [$3]"
    fi
}

# assert_exit_code <description> <expected> <actual>
assert_exit_code() {
    if [ "$2" = "$3" ]; then
        PASS "$1"
    else
        FAIL "$1" "expected exit code: $2, actual: $3"
    fi
}

# assert_file_exists <description> <path>
assert_file_exists() {
    if [ -f "$2" ]; then
        PASS "$1"
    else
        FAIL "$1" "file not found: $2"
    fi
}

# assert_file_not_exists <description> <path>
assert_file_not_exists() {
    if [ ! -e "$2" ]; then
        PASS "$1"
    else
        FAIL "$1" "file exists but should not: $2"
    fi
}

# assert_file_contains <description> <path> <pattern>
assert_file_contains() {
    if [ -f "$2" ] && grep -q "$3" "$2"; then
        PASS "$1"
    else
        FAIL "$1" "file $2 does not contain [$3]"
    fi
}

# assert_dir_exists <description> <path>
assert_dir_exists() {
    if [ -d "$2" ]; then
        PASS "$1"
    else
        FAIL "$1" "directory not found: $2"
    fi
}

# ---------------------------------------------------------------------------
# Setup: create isolated test environment
# ---------------------------------------------------------------------------

TEST_DIR=""

setup_test_env() {
    TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fedora-sway-test-XXXXXX")

    XDG_CONFIG_HOME="$TEST_DIR/config"
    XDG_DATA_HOME="$TEST_DIR/data"
    HOME="$TEST_DIR/home"
    OS_RELEASE_FILE="$TEST_DIR/os-release"
    SWAY_BIN="$TEST_DIR/bin/sway"
    export XDG_CONFIG_HOME XDG_DATA_HOME HOME OS_RELEASE_FILE SWAY_BIN TEST_DIR

    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$HOME" "$(dirname "$SWAY_BIN")"

    # Fake os-release for Fedora
    cat > "$OS_RELEASE_FILE" <<'EOF'
ID=fedora
NAME="Fedora Linux"
VERSION_ID="44"
EOF

    # Fake sway binary
    cat > "$SWAY_BIN" <<'EOF'
#!/usr/bin/env bash
echo "sway 1.11"
EOF
    chmod +x "$SWAY_BIN"
}

# Run restore.sh with the test environment, capturing output and exit code.
# Usage: run_restore <mode> [extra args...]
run_restore() {
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    SWAY_BIN="$SWAY_BIN" \
    "$REPO_ROOT/scripts/restore.sh" "$@"
}

# Run recover.sh with the test environment, capturing output and exit code.
run_recover() {
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    "$REPO_ROOT/scripts/recover.sh" "$@"
}

# ---------------------------------------------------------------------------
# Test 1: Dry-run makes no filesystem changes
# ---------------------------------------------------------------------------

test_dry_run_no_changes() {
    printf 'Test 1: Dry-run makes no filesystem changes\n'

    setup_test_env

    # Create a pre-existing file to verify it is not touched
    mkdir -p "$XDG_CONFIG_HOME/alacritty"
    echo "pre-existing" > "$XDG_CONFIG_HOME/alacritty/alacritty.toml"

    # Snapshot before
    local before_hashes before_dir before_meta
    before_hashes=$(find "$XDG_CONFIG_HOME" -type f -exec sha256sum {} + 2>/dev/null | sort | sha256sum)
    before_dir=$(find "$XDG_CONFIG_HOME" -type d 2>/dev/null | sort)
    before_meta=$(find "$XDG_CONFIG_HOME" -exec stat -c '%n %s %Y %a' {} + 2>/dev/null | sort)

    # Run dry-run
    local output exit_code
    output=$(run_restore --dry-run 2>&1)
    exit_code=$?

    assert_exit_code "dry-run exits 0" "0" "$exit_code"

    # Snapshot after
    local after_hashes after_dir after_meta
    after_hashes=$(find "$XDG_CONFIG_HOME" -type f -exec sha256sum {} + 2>/dev/null | sort | sha256sum)
    after_dir=$(find "$XDG_CONFIG_HOME" -type d 2>/dev/null | sort)
    after_meta=$(find "$XDG_CONFIG_HOME" -exec stat -c '%n %s %Y %a' {} + 2>/dev/null | sort)

    assert_equals "dry-run: no file content changes" "$before_hashes" "$after_hashes"
    assert_equals "dry-run: no directory structure changes" "$before_dir" "$after_dir"
    assert_equals "dry-run: no metadata changes" "$before_meta" "$after_meta"

    # Verify pre-existing file is untouched
    assert_file_contains "pre-existing file untouched by dry-run" \
        "$XDG_CONFIG_HOME/alacritty/alacritty.toml" "pre-existing"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 2: First application installs expected files
# ---------------------------------------------------------------------------

test_apply_installs_files() {
    printf 'Test 2: First application installs expected files\n'

    setup_test_env

    local exit_code
    run_restore --apply >/dev/null 2>&1
    exit_code=$?

    assert_exit_code "apply exits 0" "0" "$exit_code"

    # Check all Sway fragments
    local f
    for f in "$REPO_ROOT/configs/sway/config.d"/*.conf; do
        local base
        base=$(basename "$f")
        assert_file_exists "sway fragment installed: $base" \
            "$XDG_CONFIG_HOME/sway/config.d/$base"
    done

    # Check all config files
    assert_file_exists "alacritty config installed" \
        "$XDG_CONFIG_HOME/alacritty/alacritty.toml"
    assert_file_exists "waybar config installed" \
        "$XDG_CONFIG_HOME/waybar/config.jsonc"
    assert_file_exists "waybar stylesheet installed" \
        "$XDG_CONFIG_HOME/waybar/style.css"
    assert_file_exists "rofi config installed" \
        "$XDG_CONFIG_HOME/rofi/config.rasi"
    assert_file_exists "rofi theme installed" \
        "$XDG_CONFIG_HOME/rofi/tokyonight.rasi"
    assert_file_exists "dunst config installed" \
        "$XDG_CONFIG_HOME/dunst/dunstrc"
    assert_file_exists "swaylock config installed" \
        "$XDG_CONFIG_HOME/swaylock/config"
    assert_file_exists "gtk-3 settings installed" \
        "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
    assert_file_exists "gtk-4 settings installed" \
        "$XDG_CONFIG_HOME/gtk-4.0/settings.ini"

    # Verify content matches repository for key files
    assert_equals "sway fragment content matches" \
        "$(cat "$REPO_ROOT/configs/sway/config.d/10-wallpaper.conf")" \
        "$(cat "$XDG_CONFIG_HOME/sway/config.d/10-wallpaper.conf")"

    assert_equals "alacritty content matches" \
        "$(cat "$REPO_ROOT/configs/alacritty/alacritty.toml")" \
        "$(cat "$XDG_CONFIG_HOME/alacritty/alacritty.toml")"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 3: Second application is idempotent
# ---------------------------------------------------------------------------

test_apply_idempotent() {
    printf 'Test 3: Second application is idempotent\n'

    setup_test_env

    # First apply
    run_restore --apply >/dev/null 2>&1

    # Snapshot file hashes
    local hash_before
    hash_before=$(find "$XDG_CONFIG_HOME" -type f -exec sha256sum {} + | sort | sha256sum)

    # Second apply
    run_restore --apply >/dev/null 2>&1

    # Snapshot file hashes again
    local hash_after
    hash_after=$(find "$XDG_CONFIG_HOME" -type f -exec sha256sum {} + | sort | sha256sum)

    assert_equals "no changes on second apply" "$hash_before" "$hash_after"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 4: Conflicting files are preserved and reported
# ---------------------------------------------------------------------------

test_conflicts_preserved() {
    printf 'Test 4: Conflicting files are preserved and reported\n'

    setup_test_env

    # Create a conflicting alacritty config
    mkdir -p "$XDG_CONFIG_HOME/alacritty"
    echo "# User's custom config" > "$XDG_CONFIG_HOME/alacritty/alacritty.toml"

    # Run apply without --force
    local output exit_code
    output=$(run_restore --apply 2>&1)
    exit_code=$?

    assert_exit_code "apply without --force exits 0" "0" "$exit_code"

    # File should be preserved
    assert_file_contains "conflicting file preserved" \
        "$XDG_CONFIG_HOME/alacritty/alacritty.toml" "User's custom config"

    # Should be reported as conflict
    if echo "$output" | grep -q '\[conflict\]'; then
        PASS "conflict reported in output"
    else
        FAIL "conflict reported in output" "no [conflict] tag found"
    fi

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 5: Backups created before replacement with --force
# ---------------------------------------------------------------------------

test_backups_created() {
    printf 'Test 5: Backups created before replacement with --force\n'

    setup_test_env

    # First, install the correct config
    run_restore --apply >/dev/null 2>&1

    # Now modify a file to create a conflict
    echo "# Modified by user" >> "$XDG_CONFIG_HOME/alacritty/alacritty.toml"

    # Apply with --force
    run_restore --apply --force >/dev/null 2>&1

    # Find the backup directory
    local backup_dir
    backup_dir=$(find "$XDG_CONFIG_HOME/fedora-sway-restore-backups" -maxdepth 1 -type d -name '20*' | head -1)

    if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
        PASS "backup directory created"
    else
        FAIL "backup directory created" "no backup dir found"
        rm -rf "$TEST_DIR"
        return
    fi

    assert_file_exists "manifest.txt exists" "$backup_dir/manifest.txt"
    assert_file_contains "manifest has alacritty entry" \
        "$backup_dir/manifest.txt" "alacritty.toml"

    # Verify the backed-up file has the original modified content
    local backup_file
    backup_file=$(find "$backup_dir" -name 'alacritty_alacritty.toml-*' -type f | head -1)
    if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
        assert_file_contains "backup has modified content" "$backup_file" "Modified by user"
    else
        FAIL "backup has modified content" "backup file not found"
    fi

    # Verify the active file now matches the repository
    assert_equals "active file matches repository after force" \
        "$(cat "$REPO_ROOT/configs/alacritty/alacritty.toml")" \
        "$(cat "$XDG_CONFIG_HOME/alacritty/alacritty.toml")"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 6: Recovery restores from backups
# ---------------------------------------------------------------------------

test_recovery() {
    printf 'Test 6: Recovery restores from backups\n'

    setup_test_env

    # Install correct config
    run_restore --apply >/dev/null 2>&1

    # Modify a file
    echo "# User modification" >> "$XDG_CONFIG_HOME/alacritty/alacritty.toml"

    # Force replace (creates backup)
    run_restore --apply --force >/dev/null 2>&1

    # Find backup directory
    local backup_dir
    backup_dir=$(find "$XDG_CONFIG_HOME/fedora-sway-restore-backups" -maxdepth 1 -type d -name '20*' | head -1)

    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        FAIL "recovery" "backup directory not found"
        rm -rf "$TEST_DIR"
        return
    fi

    # Run recovery
    local exit_code
    run_recover "$backup_dir" >/dev/null 2>&1
    exit_code=$?

    assert_exit_code "recovery exits 0" "0" "$exit_code"

    # Verify the file was restored to the modified version
    assert_file_contains "recovery restored modified content" \
        "$XDG_CONFIG_HOME/alacritty/alacritty.toml" "User modification"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 7: Missing assets reported without corrupting configuration
# ---------------------------------------------------------------------------

test_missing_assets_reported() {
    printf 'Test 7: Missing assets reported without corrupting configuration\n'

    setup_test_env

    # Run apply (no assets installed)
    local output exit_code
    output=$(run_restore --apply 2>&1)
    exit_code=$?

    assert_exit_code "apply exits 0 despite missing assets" "0" "$exit_code"

    # Should report missing assets
    if echo "$output" | grep -q '\[WARN\]'; then
        PASS "missing assets reported"
    else
        FAIL "missing assets reported" "no [WARN] found in output"
    fi

    # Configuration should still be installed correctly
    assert_file_exists "config installed despite missing assets" \
        "$XDG_CONFIG_HOME/sway/config.d/10-wallpaper.conf"
    assert_file_exists "alacritty config installed" \
        "$XDG_CONFIG_HOME/alacritty/alacritty.toml"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 8: Unsupported systems or invalid arguments fail clearly
# ---------------------------------------------------------------------------

test_unsupported_system() {
    printf 'Test 8a: Unsupported system fails clearly\n'

    setup_test_env

    # Modify os-release to be non-Fedora
    echo 'ID=ubuntu' > "$OS_RELEASE_FILE"

    local output exit_code
    output=$(run_restore --dry-run 2>&1)
    exit_code=$?

    assert_exit_code "non-Fedora system rejected" "1" "$exit_code"

    if echo "$output" | grep -q 'unsupported system'; then
        PASS "clear error message for unsupported system"
    else
        FAIL "clear error message" "no 'unsupported system' message"
    fi

    rm -rf "$TEST_DIR"
}

test_invalid_arguments() {
    printf 'Test 8b: Invalid arguments fail clearly\n'

    setup_test_env

    local output exit_code
    output=$(run_restore --invalid-flag 2>&1)
    exit_code=$?

    assert_exit_code "invalid argument rejected" "2" "$exit_code"

    if echo "$output" | grep -q 'unknown argument'; then
        PASS "clear error message for invalid argument"
    else
        FAIL "clear error message" "no 'unknown argument' message"
    fi

    rm -rf "$TEST_DIR"
}

test_missing_sway() {
    printf 'Test 8c: Missing sway binary fails clearly\n'

    setup_test_env

    # Remove sway binary
    rm -f "$SWAY_BIN"

    local output exit_code
    output=$(run_restore --dry-run 2>&1)
    exit_code=$?

    assert_exit_code "missing sway rejected" "1" "$exit_code"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 9: Paths containing spaces are handled safely
# ---------------------------------------------------------------------------

test_spaces_in_paths() {
    printf 'Test 9: Paths containing spaces are handled safely\n'

    TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fedora-sway-test-spaces-XXXXXX")

    XDG_CONFIG_HOME="$TEST_DIR/config dir"
    XDG_DATA_HOME="$TEST_DIR/data dir"
    HOME="$TEST_DIR/home dir"
    OS_RELEASE_FILE="$TEST_DIR/os-release"
    SWAY_BIN="$TEST_DIR/bin/sway"
    export XDG_CONFIG_HOME XDG_DATA_HOME HOME OS_RELEASE_FILE SWAY_BIN TEST_DIR

    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$HOME" "$(dirname "$SWAY_BIN")"

    cat > "$OS_RELEASE_FILE" <<'EOF'
ID=fedora
NAME="Fedora Linux"
VERSION_ID="44"
EOF

    cat > "$SWAY_BIN" <<'EOF'
#!/usr/bin/env bash
echo "sway 1.11"
EOF
    chmod +x "$SWAY_BIN"

    # Apply
    local exit_code
    run_restore --apply >/dev/null 2>&1
    exit_code=$?

    assert_exit_code "apply with spaces exits 0" "0" "$exit_code"

    assert_file_exists "sway fragment installed (spaces in path)" \
        "$XDG_CONFIG_HOME/sway/config.d/10-wallpaper.conf"
    assert_file_exists "alacritty config installed (spaces in path)" \
        "$XDG_CONFIG_HOME/alacritty/alacritty.toml"

    # Modify a file and force replace to create backup
    echo "# Modified" >> "$XDG_CONFIG_HOME/alacritty/alacritty.toml"
    run_restore --apply --force >/dev/null 2>&1

    # Find backup directory
    local backup_dir
    backup_dir=$(find "$XDG_CONFIG_HOME/fedora-sway-restore-backups" -maxdepth 1 -type d -name '20*' | head -1)

    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        FAIL "recovery with spaces" "backup directory not found"
        rm -rf "$TEST_DIR"
        return
    fi

    # Run recovery with spaces in path
    run_recover "$backup_dir" >/dev/null 2>&1
    exit_code=$?

    assert_exit_code "recovery with spaces exits 0" "0" "$exit_code"

    assert_file_contains "recovery restored content (spaces in path)" \
        "$XDG_CONFIG_HOME/alacritty/alacritty.toml" "Modified"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 10: No test targets real home directory
# ---------------------------------------------------------------------------

test_no_real_home_target() {
    printf 'Test 10: No test targets real home directory\n'

    setup_test_env

    case $XDG_CONFIG_HOME in
        "${TMPDIR:-/tmp}"/*)
            PASS "test uses temp directory for XDG_CONFIG_HOME"
            ;;
        *)
            FAIL "test uses temp directory" "XDG_CONFIG_HOME is not in temp: $XDG_CONFIG_HOME"
            ;;
    esac

    assert_equals "HOME is set to test dir" "$TEST_DIR/home" "$HOME"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 11: Check mode behavior
# ---------------------------------------------------------------------------

test_check_mode() {
    printf 'Test 11: --check mode reports status correctly\n'

    setup_test_env

    # Check with missing assets should exit 1
    local exit_code
    run_restore --check >/dev/null 2>&1
    exit_code=$?

    assert_exit_code "--check exits 1 when assets missing" "1" "$exit_code"

    # Install and check again — still exits 1 because assets are missing
    run_restore --apply >/dev/null 2>&1

    run_restore --check >/dev/null 2>&1
    exit_code=$?

    assert_exit_code "--check still exits 1 when assets missing (after install)" "1" "$exit_code"

    rm -rf "$TEST_DIR"
}

test_check_mode_all_assets() {
    printf 'Test 11b: --check exits 0 when all assets present\n'

    setup_test_env

    # Create all required assets
    mkdir -p "$HOME/.local/share/backgrounds"
    echo "fake wallpaper" > "$HOME/.local/share/backgrounds/wallpaper.png"

    mkdir -p "$HOME/.themes/Tokyonight-BL-MB-Dark-Moon"

    mkdir -p "$HOME/.local/share/icons/Papirus-Dark"

    # Create a fake fc-list that reports the font
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/fc-list" <<'EOF'
#!/usr/bin/env bash
echo "/usr/share/fonts/jetbrains-mono/JetBrainsMonoNerdFont-Regular.ttf: JetBrainsMono Nerd Font:style=Regular"
EOF
    chmod +x "$TEST_DIR/bin/fc-list"
    export PATH="$TEST_DIR/bin:$PATH"

    # Install config first
    run_restore --apply >/dev/null 2>&1

    # Check should now exit 0
    local exit_code
    run_restore --check >/dev/null 2>&1
    exit_code=$?

    assert_exit_code "--check exits 0 when all assets present" "0" "$exit_code"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 12: Root user is rejected (behavioral test)
# ---------------------------------------------------------------------------

test_root_rejected() {
    printf 'Test 12: Root user is rejected\n'

    setup_test_env

    # Use unshare to create a user namespace where we appear as root
    local output exit_code
    output=$(unshare --user --map-root-user -- bash -c \
        "XDG_CONFIG_HOME='$XDG_CONFIG_HOME' OS_RELEASE_FILE='$OS_RELEASE_FILE' SWAY_BIN='$SWAY_BIN' '$REPO_ROOT/scripts/restore.sh' --dry-run" 2>&1)
    exit_code=$?

    assert_exit_code "restore.sh rejects root" "1" "$exit_code"

    if echo "$output" | grep -q 'refusing to run as root'; then
        PASS "restore.sh root rejection message"
    else
        FAIL "restore.sh root rejection message" "no 'refusing to run as root' message"
    fi

    # Test recover.sh root rejection
    output=$(unshare --user --map-root-user -- bash -c \
        "XDG_CONFIG_HOME='$XDG_CONFIG_HOME' '$REPO_ROOT/scripts/recover.sh' /tmp/nonexistent" 2>&1)
    exit_code=$?

    assert_exit_code "recover.sh rejects root" "1" "$exit_code"

    if echo "$output" | grep -q 'refusing to run as root'; then
        PASS "recover.sh root rejection message"
    else
        FAIL "recover.sh root rejection message" "no 'refusing to run as root' message"
    fi

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 13: Shell syntax validation
# ---------------------------------------------------------------------------

test_shell_syntax() {
    printf 'Test 13: Shell syntax validation\n'

    if bash -n "$REPO_ROOT/scripts/restore.sh" 2>/dev/null; then
        PASS "restore.sh syntax valid"
    else
        FAIL "restore.sh syntax valid" "syntax error detected"
    fi

    if bash -n "$REPO_ROOT/scripts/recover.sh" 2>/dev/null; then
        PASS "recover.sh syntax valid"
    else
        FAIL "recover.sh syntax valid" "syntax error detected"
    fi

    if bash -n "$REPO_ROOT/tests/run_tests.sh" 2>/dev/null; then
        PASS "run_tests.sh syntax valid"
    else
        FAIL "run_tests.sh syntax valid" "syntax error detected"
    fi
}

# ---------------------------------------------------------------------------
# Test 14: Recovery refuses malicious manifests
# ---------------------------------------------------------------------------

test_recovery_malicious_manifests() {
    printf 'Test 14: Recovery refuses malicious manifests\n'

    setup_test_env

    # Create a valid backup first
    run_restore --apply >/dev/null 2>&1
    echo "# Modified" >> "$XDG_CONFIG_HOME/alacritty/alacritty.toml"
    run_restore --apply --force >/dev/null 2>&1

    local backup_dir
    backup_dir=$(find "$XDG_CONFIG_HOME/fedora-sway-restore-backups" -maxdepth 1 -type d -name '20*' | head -1)

    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        FAIL "malicious manifest tests" "backup directory not found"
        rm -rf "$TEST_DIR"
        return
    fi

    # Test 14a: Absolute destination path targeting /etc/passwd
    local malicious_dir="$TEST_DIR/malicious-etc"
    mkdir -p "$malicious_dir"
    echo "malicious" > "$malicious_dir/backup.txt"
    printf '/etc/passwd\tbackup.txt\n' > "$malicious_dir/manifest.txt"

    local output exit_code
    output=$(run_recover "$malicious_dir" 2>&1)
    exit_code=$?

    assert_exit_code "absolute destination /etc/passwd rejected" "1" "$exit_code"
    if echo "$output" | grep -qi 'must not be absolute'; then
        PASS "absolute destination rejection message"
    else
        FAIL "absolute destination rejection message" "no 'must not be absolute' message"
    fi

    # Test 14b: Traversal destination path
    malicious_dir="$TEST_DIR/malicious-traversal"
    mkdir -p "$malicious_dir"
    echo "malicious" > "$malicious_dir/backup.txt"
    printf '../../../etc/passwd\tbackup.txt\n' > "$malicious_dir/manifest.txt"

    output=$(run_recover "$malicious_dir" 2>&1)
    exit_code=$?

    assert_exit_code "traversal destination rejected" "1" "$exit_code"
    if echo "$output" | grep -qi 'must not contain'; then
        PASS "traversal destination rejection message"
    else
        FAIL "traversal destination rejection message" "no 'must not contain' message"
    fi

    # Test 14c: Backup filename with path components
    malicious_dir="$TEST_DIR/malicious-backup-path"
    mkdir -p "$malicious_dir"
    echo "malicious" > "$malicious_dir/backup.txt"
    printf 'alacritty/alacritty.toml\t../../etc/shadow\n' > "$malicious_dir/manifest.txt"

    output=$(run_recover "$malicious_dir" 2>&1)
    exit_code=$?

    assert_exit_code "backup filename with path components rejected" "1" "$exit_code"
    if echo "$output" | grep -qi 'must not contain path components'; then
        PASS "backup filename path components rejection message"
    else
        FAIL "backup filename path components rejection message" "no 'must not contain path components' message"
    fi

    # Test 14d: Backup filename with absolute path
    malicious_dir="$TEST_DIR/malicious-backup-abs"
    mkdir -p "$malicious_dir"
    echo "malicious" > "$malicious_dir/backup.txt"
    printf 'alacritty/alacritty.toml\t/etc/shadow\n' > "$malicious_dir/manifest.txt"

    output=$(run_recover "$malicious_dir" 2>&1)
    exit_code=$?

    assert_exit_code "absolute backup filename rejected" "1" "$exit_code"

    # Test 14e: Symlink escaping config dir
    malicious_dir="$TEST_DIR/malicious-symlink"
    mkdir -p "$malicious_dir"
    echo "malicious" > "$malicious_dir/backup.txt"
    # Create a symlink inside config dir pointing outside
    ln -s /tmp "$XDG_CONFIG_HOME/evil-link"
    printf 'evil-link/escape.txt\tbackup.txt\n' > "$malicious_dir/manifest.txt"

    output=$(run_recover "$malicious_dir" 2>&1)
    exit_code=$?

    assert_exit_code "symlink escaping config dir rejected" "1" "$exit_code"
    if echo "$output" | grep -qi 'symlink escapes'; then
        PASS "symlink escape rejection message"
    else
        FAIL "symlink escape rejection message" "no 'symlink escapes' message"
    fi

    # Clean up symlink
    rm -f "$XDG_CONFIG_HOME/evil-link"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 15: Recovery refuses malformed manifests
# ---------------------------------------------------------------------------

test_recovery_malformed_manifests() {
    printf 'Test 15: Recovery refuses malformed manifests\n'

    setup_test_env

    # Create a valid backup first
    run_restore --apply >/dev/null 2>&1
    echo "# Modified" >> "$XDG_CONFIG_HOME/alacritty/alacritty.toml"
    run_restore --apply --force >/dev/null 2>&1

    local backup_dir
    backup_dir=$(find "$XDG_CONFIG_HOME/fedora-sway-restore-backups" -maxdepth 1 -type d -name '20*' | head -1)

    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        FAIL "malformed manifest tests" "backup directory not found"
        rm -rf "$TEST_DIR"
        return
    fi

    # Test 15a: Missing backup filename (no tab)
    local malformed_dir="$TEST_DIR/malformed-no-tab"
    mkdir -p "$malformed_dir"
    echo "data" > "$malformed_dir/backup.txt"
    printf 'alacritty/alacritty.toml\n' > "$malformed_dir/manifest.txt"

    local output exit_code
    output=$(run_recover "$malformed_dir" 2>&1)
    exit_code=$?

    assert_exit_code "manifest without tab rejected" "1" "$exit_code"
    if echo "$output" | grep -qi 'missing backup filename'; then
        PASS "missing backup filename rejection message"
    else
        FAIL "missing backup filename rejection message" "no 'missing backup filename' message"
    fi

    # Test 15b: Duplicate entries
    malformed_dir="$TEST_DIR/malformed-duplicate"
    mkdir -p "$malformed_dir"
    echo "data" > "$malformed_dir/backup.txt"
    printf 'alacritty/alacritty.toml\tbackup.txt\nalacritty/alacritty.toml\tbackup.txt\n' > "$malformed_dir/manifest.txt"

    output=$(run_recover "$malformed_dir" 2>&1)
    exit_code=$?

    assert_exit_code "duplicate entries rejected" "1" "$exit_code"
    if echo "$output" | grep -qi 'duplicate'; then
        PASS "duplicate entries rejection message"
    else
        FAIL "duplicate entries rejection message" "no 'duplicate' message"
    fi

    # Test 15c: Missing backup file
    malformed_dir="$TEST_DIR/malformed-missing-file"
    mkdir -p "$malformed_dir"
    printf 'alacritty/alacritty.toml\tnonexistent.txt\n' > "$malformed_dir/manifest.txt"

    output=$(run_recover "$malformed_dir" 2>&1)
    exit_code=$?

    assert_exit_code "missing backup file rejected" "1" "$exit_code"
    if echo "$output" | grep -qi 'backup file not found'; then
        PASS "missing backup file rejection message"
    else
        FAIL "missing backup file rejection message" "no 'backup file not found' message"
    fi

    # Test 15d: Empty manifest
    malformed_dir="$TEST_DIR/malformed-empty"
    mkdir -p "$malformed_dir"
    : > "$malformed_dir/manifest.txt"

    output=$(run_recover "$malformed_dir" 2>&1)
    exit_code=$?

    assert_exit_code "empty manifest rejected" "1" "$exit_code"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 16: SDDM theme is never installed
# ---------------------------------------------------------------------------

test_sddm_not_installed() {
    printf 'Test 16: SDDM theme is never installed\n'

    setup_test_env

    # Run apply
    run_restore --apply >/dev/null 2>&1

    # Verify no SDDM theme directory was created in config
    assert_file_not_exists "no SDDM theme in config dir" \
        "$XDG_CONFIG_HOME/sddm"
    assert_file_not_exists "no SDDM themes dir in config" \
        "$XDG_CONFIG_HOME/themes"

    # Verify the script only wrote within the config directory
    # by checking that no files were created in the test dir outside config
    local outside_files
    outside_files=$(find "$TEST_DIR" -type f \
        ! -path "$XDG_CONFIG_HOME/*" \
        ! -path "$TEST_DIR/home/*" \
        ! -path "$TEST_DIR/bin/*" \
        ! -path "$TEST_DIR/data/*" \
        ! -path "$OS_RELEASE_FILE" \
        2>/dev/null | wc -l)
    assert_equals "no files written outside config dir" "0" "$outside_files"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 17: Backup filename collisions are handled
# ---------------------------------------------------------------------------

test_backup_collision() {
    printf 'Test 17: Backup filename collisions are handled\n'

    setup_test_env

    # Install config
    run_restore --apply >/dev/null 2>&1

    # Create two files that would collide with the old tr '/' '_' scheme:
    # "a/b" and "a_b" both map to "a_b"
    # We test by modifying two files and forcing replacement
    echo "# Modified alacritty" >> "$XDG_CONFIG_HOME/alacritty/alacritty.toml"
    echo "# Modified waybar" >> "$XDG_CONFIG_HOME/waybar/config.jsonc"

    # Force replace both
    run_restore --apply --force >/dev/null 2>&1

    # Find backup directory
    local backup_dir
    backup_dir=$(find "$XDG_CONFIG_HOME/fedora-sway-restore-backups" -maxdepth 1 -type d -name '20*' | head -1)

    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        FAIL "backup collision" "backup directory not found"
        rm -rf "$TEST_DIR"
        return
    fi

    # Count backup files — should have 2 distinct files
    local backup_count
    backup_count=$(find "$backup_dir" -maxdepth 1 -type f ! -name 'manifest.txt' | wc -l)

    assert_equals "two distinct backup files created" "2" "$backup_count"

    # Verify both backups have different content
    local alacritty_backup waybar_backup
    alacritty_backup=$(find "$backup_dir" -name 'alacritty_alacritty.toml-*' -type f | head -1)
    waybar_backup=$(find "$backup_dir" -name 'waybar_config.jsonc-*' -type f | head -1)

    if [ -n "$alacritty_backup" ] && [ -n "$waybar_backup" ]; then
        PASS "both backup files exist"
    else
        FAIL "both backup files exist" "one or more backup files missing"
    fi

    # Verify manifest has 2 entries
    local manifest_entries
    manifest_entries=$(grep -c $'\t' "$backup_dir/manifest.txt" 2>/dev/null || echo 0)
    assert_equals "manifest has 2 entries" "2" "$manifest_entries"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 18: Recovery refuses backup files that are symlinks
# ---------------------------------------------------------------------------

test_recovery_backup_symlink() {
    printf 'Test 18: Recovery refuses backup files that are symlinks\n'

    setup_test_env

    # Create a backup dir with a symlink as the backup file
    local malicious_dir="$TEST_DIR/malicious-symlink"
    mkdir -p "$malicious_dir"
    echo "malicious content" > "$TEST_DIR/real-target.txt"
    ln -s "$TEST_DIR/real-target.txt" "$malicious_dir/backup.txt"
    printf 'alacritty/alacritty.toml\tbackup.txt\n' > "$malicious_dir/manifest.txt"

    local output exit_code
    output=$(run_recover "$malicious_dir" 2>&1)
    exit_code=$?

    assert_exit_code "backup symlink rejected" "1" "$exit_code"
    if echo "$output" | grep -qi 'not a regular file'; then
        PASS "backup symlink rejection message"
    else
        FAIL "backup symlink rejection message" "no 'not a regular file' message"
    fi

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 19: Recovery refuses backup files that are directories
# ---------------------------------------------------------------------------

test_recovery_backup_directory() {
    printf 'Test 19: Recovery refuses backup files that are directories\n'

    setup_test_env

    # Create a backup dir with a directory as the backup file
    local malicious_dir="$TEST_DIR/malicious-dir"
    mkdir -p "$malicious_dir/backup.txt"
    printf 'alacritty/alacritty.toml\tbackup.txt\n' > "$malicious_dir/manifest.txt"

    local output exit_code
    output=$(run_recover "$malicious_dir" 2>&1)
    exit_code=$?

    assert_exit_code "backup directory rejected" "1" "$exit_code"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 20: Complete multi-file apply-force → recover cycle
# ---------------------------------------------------------------------------

test_complete_cycle_multiple_files() {
    printf 'Test 20: Complete multi-file apply-force → recover cycle\n'

    setup_test_env

    # Install config
    run_restore --apply >/dev/null 2>&1

    # Modify multiple files
    echo "# User alacritty" >> "$XDG_CONFIG_HOME/alacritty/alacritty.toml"
    echo "# User waybar" >> "$XDG_CONFIG_HOME/waybar/config.jsonc"
    echo "# User rofi" >> "$XDG_CONFIG_HOME/rofi/config.rasi"

    # Force replace all
    run_restore --apply --force >/dev/null 2>&1

    # Find backup directory
    local backup_dir
    backup_dir=$(find "$XDG_CONFIG_HOME/fedora-sway-restore-backups" -maxdepth 1 -type d -name '20*' | head -1)

    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        FAIL "complete cycle" "backup directory not found"
        rm -rf "$TEST_DIR"
        return
    fi

    # Verify all 3 files were backed up
    local backup_count
    backup_count=$(find "$backup_dir" -maxdepth 1 -type f ! -name 'manifest.txt' | wc -l)
    assert_equals "three backup files created" "3" "$backup_count"

    # Run recovery
    local exit_code
    run_recover "$backup_dir" >/dev/null 2>&1
    exit_code=$?

    assert_exit_code "recovery exits 0" "0" "$exit_code"

    # Verify all files restored to user-modified versions
    assert_file_contains "alacritty restored" \
        "$XDG_CONFIG_HOME/alacritty/alacritty.toml" "User alacritty"
    assert_file_contains "waybar restored" \
        "$XDG_CONFIG_HOME/waybar/config.jsonc" "User waybar"
    assert_file_contains "rofi restored" \
        "$XDG_CONFIG_HOME/rofi/config.rasi" "User rofi"

    # Verify no files written outside config dir
    local outside_files
    outside_files=$(find "$TEST_DIR" -type f \
        ! -path "$XDG_CONFIG_HOME/*" \
        ! -path "$TEST_DIR/home/*" \
        ! -path "$TEST_DIR/bin/*" \
        ! -path "$TEST_DIR/data/*" \
        ! -path "$OS_RELEASE_FILE" \
        2>/dev/null | wc -l)
    assert_equals "no files written outside config dir" "0" "$outside_files"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 21: Recovery when destination does not exist
# ---------------------------------------------------------------------------

test_recovery_destination_missing() {
    printf 'Test 21: Recovery when destination does not exist\n'

    setup_test_env

    # Create a backup manually (without running restore first)
    local backup_dir="$TEST_DIR/manual-backup"
    mkdir -p "$backup_dir"
    echo "original content" > "$backup_dir/original.txt"
    printf 'alacritty/alacritty.toml\toriginal.txt\n' > "$backup_dir/manifest.txt"

    # Run recovery — destination doesn't exist yet
    local exit_code
    run_recover "$backup_dir" >/dev/null 2>&1
    exit_code=$?

    assert_exit_code "recovery exits 0" "0" "$exit_code"

    # Verify file was created with original content
    assert_file_contains "file created with original content" \
        "$XDG_CONFIG_HOME/alacritty/alacritty.toml" "original content"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 22: Safety-backup filename collision prevention
# ---------------------------------------------------------------------------

test_safety_backup_collision() {
    printf 'Test 22: Safety-backup filename collision prevention\n'

    setup_test_env

    # Create two destinations whose paths collide under tr '/' '_':
    #   "a/b" and "a_b" both map to "a_b"
    mkdir -p "$XDG_CONFIG_HOME/a"
    echo "content for a/b" > "$XDG_CONFIG_HOME/a/b"
    echo "content for a_b" > "$XDG_CONFIG_HOME/a_b"

    # Create a backup that will overwrite both destinations
    local backup_dir="$TEST_DIR/collision-backup"
    mkdir -p "$backup_dir"
    echo "restored a/b" > "$backup_dir/backup1.txt"
    echo "restored a_b" > "$backup_dir/backup2.txt"
    printf 'a/b\tbackup1.txt\na_b\tbackup2.txt\n' > "$backup_dir/manifest.txt"

    # Run recovery — both destinations exist, so safety backups are created
    local exit_code
    run_recover "$backup_dir" >/dev/null 2>&1
    exit_code=$?

    assert_exit_code "recovery exits 0" "0" "$exit_code"

    # Verify both destinations were overwritten with backup content
    assert_file_contains "a/b restored" "$XDG_CONFIG_HOME/a/b" "restored a/b"
    assert_file_contains "a_b restored" "$XDG_CONFIG_HOME/a_b" "restored a_b"

    # Verify safety backups were created with distinct names
    local safety_dir
    safety_dir=$(find "$XDG_CONFIG_HOME/fedora-sway-restore-backups" -maxdepth 1 -type d -name 'pre-recovery-*' | head -1)

    if [ -z "$safety_dir" ] || [ ! -d "$safety_dir" ]; then
        FAIL "safety backup dir created" "no pre-recovery dir found"
        rm -rf "$TEST_DIR"
        return
    fi

    # Count safety backup files — should be 2 distinct files
    local safety_count
    safety_count=$(find "$safety_dir" -maxdepth 1 -type f | wc -l)
    assert_equals "two distinct safety backup files" "2" "$safety_count"

    # Verify safety backups have different content (no collision/overwrite)
    local safety_files
    safety_files=$(find "$safety_dir" -maxdepth 1 -type f | sort)
    local file1 file2
    file1=$(echo "$safety_files" | head -1)
    file2=$(echo "$safety_files" | tail -1)

    if [ -n "$file1" ] && [ -n "$file2" ] && [ "$file1" != "$file2" ]; then
        PASS "safety backup files have distinct paths"
    else
        FAIL "safety backup files have distinct paths" "files are the same or missing"
    fi

    # Verify one safety backup has "content for a/b" and the other "content for a_b"
    local has_ab has_underscore_ab
    has_ab=$(grep -rl "content for a/b" "$safety_dir" 2>/dev/null | wc -l)
    has_underscore_ab=$(grep -rl "content for a_b" "$safety_dir" 2>/dev/null | wc -l)
    assert_equals "safety backup for a/b preserved" "1" "$has_ab"
    assert_equals "safety backup for a_b preserved" "1" "$has_underscore_ab"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    printf 'Fedora Sway Atomic — restoration test suite\n'
    printf 'Repository: %s\n' "$REPO_ROOT"
    printf '\n'

    test_dry_run_no_changes
    test_apply_installs_files
    test_apply_idempotent
    test_conflicts_preserved
    test_backups_created
    test_recovery
    test_missing_assets_reported
    test_unsupported_system
    test_invalid_arguments
    test_missing_sway
    test_spaces_in_paths
    test_no_real_home_target
    test_check_mode
    test_check_mode_all_assets
    test_root_rejected
    test_shell_syntax
    test_recovery_malicious_manifests
    test_recovery_malformed_manifests
    test_sddm_not_installed
    test_backup_collision
    test_recovery_backup_symlink
    test_recovery_backup_directory
    test_complete_cycle_multiple_files
    test_recovery_destination_missing
    test_safety_backup_collision

    printf '\n'
    printf 'Results: %d passed, %d failed, %d total\n' "$TESTS_PASSED" "$TESTS_FAILED" "$TESTS_RUN"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        printf '\nFailed tests:\n'
        for t in "${FAILED_TESTS[@]}"; do
            printf '  - %s\n' "$t"
        done
        return 1
    fi

    printf '\nAll tests passed.\n'
    return 0
}

main
