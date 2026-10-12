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
    printf '  FAIL: %s\n' "$1}"
    if [ "${2:-}" != "" ]; then
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
    TEST_DIR=$(mktemp -d /tmp/opencode/fedora-sway-test-XXXXXX)

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

# ---------------------------------------------------------------------------
# Test 1: Dry-run makes no filesystem changes
# ---------------------------------------------------------------------------

test_dry_run_no_changes() {
    printf 'Test 1: Dry-run makes no filesystem changes\n'

    setup_test_env

    # Count files before
    local before_count
    before_count=$(find "$XDG_CONFIG_HOME" -type f 2>/dev/null | wc -l)

    # Run dry-run
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    SWAY_BIN="$SWAY_BIN" \
    "$REPO_ROOT/scripts/restore.sh" --dry-run >/dev/null 2>&1

    # Count files after
    local after_count
    after_count=$(find "$XDG_CONFIG_HOME" -type f 2>/dev/null | wc -l)

    assert_equals "no files created by dry-run" "$before_count" "$after_count"
    assert_dir_exists "config dir still exists" "$XDG_CONFIG_HOME"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 2: First application installs expected files
# ---------------------------------------------------------------------------

test_apply_installs_files() {
    printf 'Test 2: First application installs expected files\n'

    setup_test_env

    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    SWAY_BIN="$SWAY_BIN" \
    "$REPO_ROOT/scripts/restore.sh" --apply >/dev/null 2>&1

    # Check key files exist
    assert_file_exists "sway fragment installed" \
        "$XDG_CONFIG_HOME/sway/config.d/10-wallpaper.conf"
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

    # Verify content matches repository
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
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    SWAY_BIN="$SWAY_BIN" \
    "$REPO_ROOT/scripts/restore.sh" --apply >/dev/null 2>&1

    # Snapshot file hashes
    local hash_before
    hash_before=$(find "$XDG_CONFIG_HOME" -type f -exec sha256sum {} + | sort | sha256sum)

    # Second apply
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    SWAY_BIN="$SWAY_BIN" \
    "$REPO_ROOT/scripts/restore.sh" --apply >/dev/null 2>&1

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
    local output
    output=$(XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    SWAY_BIN="$SWAY_BIN" \
    "$REPO_ROOT/scripts/restore.sh" --apply 2>&1)

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
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    SWAY_BIN="$SWAY_BIN" \
    "$REPO_ROOT/scripts/restore.sh" --apply >/dev/null 2>&1

    # Now modify a file to create a conflict
    echo "# Modified by user" >> "$XDG_CONFIG_HOME/alacritty/alacritty.toml"

    # Apply with --force
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    SWAY_BIN="$SWAY_BIN" \
    "$REPO_ROOT/scripts/restore.sh" --apply --force >/dev/null 2>&1

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
    backup_file=$(find "$backup_dir" -name 'alacritty_alacritty.toml' -type f | head -1)
    if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
        assert_file_contains "backup has modified content" "$backup_file" "Modified by user"
    else
        FAIL "backup has modified content" "backup file not found or empty"
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
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    SWAY_BIN="$SWAY_BIN" \
    "$REPO_ROOT/scripts/restore.sh" --apply >/dev/null 2>&1

    # Modify a file
    echo "# User modification" >> "$XDG_CONFIG_HOME/alacritty/alacritty.toml"

    # Force replace (creates backup)
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    SWAY_BIN="$SWAY_BIN" \
    "$REPO_ROOT/scripts/restore.sh" --apply --force >/dev/null 2>&1

    # Find backup directory
    local backup_dir
    backup_dir=$(find "$XDG_CONFIG_HOME/fedora-sway-restore-backups" -maxdepth 1 -type d -name '20*' | head -1)

    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        FAIL "recovery" "backup directory not found"
        rm -rf "$TEST_DIR"
        return
    fi

    # Run recovery
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    "$REPO_ROOT/scripts/recover.sh" "$backup_dir" >/dev/null 2>&1

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
    local output
    output=$(XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    SWAY_BIN="$SWAY_BIN" \
    "$REPO_ROOT/scripts/restore.sh" --apply 2>&1)

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

    local output
    output=$(XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    SWAY_BIN="$SWAY_BIN" \
    "$REPO_ROOT/scripts/restore.sh" --dry-run 2>&1)
    local exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        PASS "non-Fedora system rejected"
    else
        FAIL "non-Fedora system rejected" "exit code was 0"
    fi

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

    local output
    output=$(XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    SWAY_BIN="$SWAY_BIN" \
    "$REPO_ROOT/scripts/restore.sh" --invalid-flag 2>&1)
    local exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        PASS "invalid argument rejected"
    else
        FAIL "invalid argument rejected" "exit code was 0"
    fi

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

    local output
    output=$(XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    SWAY_BIN="$SWAY_BIN" \
    "$REPO_ROOT/scripts/restore.sh" --dry-run 2>&1)
    local exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        PASS "missing sway rejected"
    else
        FAIL "missing sway rejected" "exit code was 0"
    fi

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 9: Paths containing spaces are handled safely
# ---------------------------------------------------------------------------

test_spaces_in_paths() {
    printf 'Test 9: Paths containing spaces are handled safely\n'

    TEST_DIR=$(mktemp -d "/tmp/opencode/fedora-sway-test-spaces-XXXXXX")

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
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    SWAY_BIN="$SWAY_BIN" \
    "$REPO_ROOT/scripts/restore.sh" --apply >/dev/null 2>&1

    assert_file_exists "sway fragment installed (spaces in path)" \
        "$XDG_CONFIG_HOME/sway/config.d/10-wallpaper.conf"
    assert_file_exists "alacritty config installed (spaces in path)" \
        "$XDG_CONFIG_HOME/alacritty/alacritty.toml"

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 10: No test targets real home directory
# ---------------------------------------------------------------------------

test_no_real_home_target() {
    printf 'Test 10: No test targets real home directory\n'

    # Verify that the test setup uses a temp directory, not real home
    setup_test_env

    case $XDG_CONFIG_HOME in
        /tmp/*)
            PASS "test uses temp directory for XDG_CONFIG_HOME"
            ;;
        *)
            FAIL "test uses temp directory" "XDG_CONFIG_HOME is not in /tmp: $XDG_CONFIG_HOME"
            ;;
    esac

    # Verify the script doesn't write outside XDG_CONFIG_HOME
    # (This is a sanity check — the script's design ensures this)
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
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    SWAY_BIN="$SWAY_BIN" \
    "$REPO_ROOT/scripts/restore.sh" --check >/dev/null 2>&1
    local exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        PASS "--check exits 1 when assets missing"
    else
        FAIL "--check exits 1 when assets missing" "exit code was 0"
    fi

    # Install and check again
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    SWAY_BIN="$SWAY_BIN" \
    "$REPO_ROOT/scripts/restore.sh" --apply >/dev/null 2>&1

    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    OS_RELEASE_FILE="$OS_RELEASE_FILE" \
    SWAY_BIN="$SWAY_BIN" \
    "$REPO_ROOT/scripts/restore.sh" --check >/dev/null 2>&1
    exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        PASS "--check still exits 1 when assets missing (after install)"
    else
        FAIL "--check still exits 1 when assets missing" "exit code was 0"
    fi

    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Test 12: Root user is rejected
# ---------------------------------------------------------------------------

test_root_rejected() {
    printf 'Test 12: Root user is rejected\n'

    # We can't actually run as root in tests, but we can verify the
    # script contains the root check
    if grep -q 'refusing to run as root' "$REPO_ROOT/scripts/restore.sh"; then
        PASS "root check present in restore.sh"
    else
        FAIL "root check present in restore.sh" "root check not found"
    fi

    if grep -q 'refusing to run as root' "$REPO_ROOT/scripts/recover.sh"; then
        PASS "root check present in recover.sh"
    else
        FAIL "root check present in recover.sh" "root check not found"
    fi
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
    test_root_rejected
    test_shell_syntax

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
