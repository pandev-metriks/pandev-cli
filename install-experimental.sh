#!/bin/bash
# =============================================================================
#  PanDev CLI — install bootstrap (both channels)
#
#  Single-command install entry point, designed to be run via
#    curl -fsSL <url> | bash
#  Rendered copies live in the pandev-metriks/pandev-cli repo:
#    install.sh               — Stable channel
#    install-experimental.sh  — Beta channel
#
#  Source-of-truth is release/install-experimental.sh in the CLI source repo
#  (GitLab). The release workflows render it on every release and commit the
#  result next to the Formula/ directory in pandev-metriks/pandev-cli. Never
#  edit the rendered copies by hand.
#
#  Tokens replaced by the publish step (do NOT pre-fill them here):
#    2.5.17               — semantic version, e.g. 2.5.0
#    v2.5.17-beta                   — release tag hosting the assets, e.g. v2.5.0-beta
#    Beta               — human-readable channel name: Beta | Stable
#    pandev-cli-plugin-beta               — formula name: pandev-cli-plugin[-beta]
#    3603e30fe77b5aa4c20770bbb8a88c9529cb049d9623d8114e1c0a3f12c04980  — checksum of the Windows .zip asset
#  macOS/Linux SHAs are enforced by the Homebrew Formula at install time.
# =============================================================================
set -e

VERSION="2.5.17"
TAG="v2.5.17-beta"
CHANNEL="Beta"
FORMULA_NAME="pandev-cli-plugin-beta"

# All public artifacts (releases, formulas, installers) live in this repo.
REPO="pandev-metriks/pandev-cli"
TAP="pandev-metriks/pandev-cli"
TAP_URL="https://github.com/pandev-metriks/pandev-cli"
FORMULA="$TAP/$FORMULA_NAME"

# Legacy taps from the pre-consolidation era. We untap them so old installs
# can't shadow the new one. The legacy stable tap shares the short name
# pandev-metriks/pandev-cli with the new tap (it pointed at the repo
# homebrew-pandev-cli) — untapping by name removes whichever is present,
# and we re-tap from the explicit URL below.
LEGACY_BETA_TAP="pandev-metriks/pandev-cli-beta"

INSTALL_DIR="$HOME/.pandev"
BIN_DIR="$HOME/.local/bin"
BIN_LINK="$BIN_DIR/pandev"

# Windows-only: SHA256 of the .zip asset. Used to verify the download in the
# `curl | bash` path where there's no Homebrew Formula to do it for us.
WINDOWS_AMD64_SHA256="3603e30fe77b5aa4c20770bbb8a88c9529cb049d9623d8114e1c0a3f12c04980"

# `curl ... | bash -s -- --uninstall` removes PanDev instead of installing it.
MODE="install"
for arg in "$@"; do
    if [ "$arg" = "--uninstall" ]; then
        MODE="uninstall"
    fi
done

# Where the watcher keeps its temp files. Overridable only so that tests leave the real ones alone.
PANDEV_TMP="${PANDEV_TMP:-/tmp}"

# -------------------------------------------------------
# 1. Root check (skipped on Windows — Git Bash has no real "root")
# -------------------------------------------------------
if command -v id >/dev/null 2>&1 && [ "$(id -u 2>/dev/null || echo 1000)" -eq 0 ]; then
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) : ;;  # MSYS reports uid 0 inside Git Bash; harmless
        *) echo "ERROR: Do not run this script as root."; exit 1 ;;
    esac
fi

# -------------------------------------------------------
# 2. Detect OS and architecture
# -------------------------------------------------------
OS=$(uname -s)
ARCH=$(uname -m)

case "$ARCH" in
    x86_64|amd64) ARCH_NAME="amd64" ;;
    arm64|aarch64) ARCH_NAME="arm64" ;;
    *) echo "ERROR: Unsupported architecture: $ARCH"; exit 1 ;;
esac

case "$OS" in
    Darwin)               OS_NAME="macOS" ;;
    Linux)                OS_NAME="Linux" ;;
    # Git for Windows (MINGW64/MINGW32), MSYS2, and Cygwin all report a
    # platform string starting with one of these prefixes. WSL reports
    # "Linux" and is handled above — the WSL flow is the regular Linux flow.
    MINGW*|MSYS*|CYGWIN*) OS_NAME="Windows"; ARCH_NAME="amd64" ;;
    *) echo "ERROR: Unsupported OS: $OS"; exit 1 ;;
esac

if [[ "$MODE" == "uninstall" ]]; then
    echo "PanDev CLI uninstaller"
else
    echo "PanDev CLI installer — $CHANNEL channel, v$VERSION"
fi
echo "Platform detected: $OS_NAME / $ARCH_NAME"

# -------------------------------------------------------
# Removal — shared by the install cleanup and by --uninstall
# -------------------------------------------------------
# brew, npm and MSIX never run our code when they remove a package, and the program's own
# `pandev --uninstall` is only as good as the installed version: older ones left a running
# watcher and the program itself behind, and a client who followed the old docs no longer
# has the program at all. This script is always the current one, so it removes any version
# of any era, with or without the program still present (PDM-4862).

# The team watcher's service (LaunchAgent / systemd user unit) and any watcher started
# outside it — the no-systemd fallback, or by hand. Credentials are not touched here.
stop_team_watcher() {
    if [[ "$OS" == "Darwin" ]]; then
        launchctl bootout "gui/$(id -u)/io.pandev.watcher" 2>/dev/null || true
        rm -f "$HOME/Library/LaunchAgents/io.pandev.watcher.plist"
    elif command -v systemctl &>/dev/null; then
        systemctl --user disable --now pandev-watcher.service 2>/dev/null || true
        rm -f "$HOME/.config/systemd/user/pandev-watcher.service"
        systemctl --user daemon-reload 2>/dev/null || true
    fi
    pkill -u "$(id -u)" -f 'pandev-myapp\.jar --watcher' 2>/dev/null || true
}

# Both formulas, whatever tap they came from, and the taps themselves.
remove_homebrew_install() {
    command -v brew &>/dev/null || return 0
    brew unlink pandev-cli-plugin 2>/dev/null || true
    brew unlink pandev-cli-plugin-beta 2>/dev/null || true
    # --force + the BARE formula name removes EVERY installed version/keg of
    # the formula, whatever tap it came from, and works even if that tap is
    # already gone. Tap-qualified uninstall silently no-ops once the tap is
    # untapped and leaves a stale keg that makes the reinstall below a no-op.
    brew uninstall --force pandev-cli-plugin 2>/dev/null || true
    brew uninstall --force pandev-cli-plugin-beta 2>/dev/null || true
    # Untap both the legacy taps and the current one (re-tapped below). The
    # legacy stable tap shares the pandev-metriks/pandev-cli short name.
    brew untap "$LEGACY_BETA_TAP" 2>/dev/null || true
    brew untap "$TAP" 2>/dev/null || true
    brew cleanup pandev-cli-plugin 2>/dev/null || true
    brew cleanup pandev-cli-plugin-beta 2>/dev/null || true
}

UNINSTALL_CLEAN=1
UNINSTALL_REPORTED=0
report_ok() {
    UNINSTALL_REPORTED=1
    echo "  ✓ $1"
}
report_fail() {
    UNINSTALL_CLEAN=0
    UNINSTALL_REPORTED=1
    echo "  ✗ $1"
    if [ -n "${2:-}" ]; then
        echo "      $2"
    fi
}
report_note() {
    UNINSTALL_REPORTED=1
    echo "  · $1"
}
# $HOME/x → ~/x, for the report
pretty() {
    case "$1" in
        "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
        *) printf '%s' "$1" ;;
    esac
}

# npx pandev is a SEPARATE PRODUCT: its own install command, its own uninstall (PDM-4862).
# This script removes the team edition and never takes the npx edition with it. These are the
# names npx owns inside the two directories the products share.
NPX_CONFIG_FILES="b2c-dashboard.sh b2c-dashboard-open.sh b2c-dashboard.cmd b2c-dashboard-open.cmd \
b2c-dashboard.vbs b2c-dashboard-open.vbs b2c-dashboard.log b2c.firstrun autostart.off \
dashboard.token budget.json budget.state.json cache zcode-workspace"
NPX_HOME_FILES="profile-cache.json profile-domains.json profile-portrait.json profile.html"

# Any trace is enough: a service without its shim and a shim without its service both mean
# "the npx edition lives here".
npx_present() {
    for npx_mark in "$HOME/Library/LaunchAgents/io.pandev.b2c.dashboard.plist" \
                    "$HOME/Library/LaunchAgents/io.pandev.b2c.dashboard-open.plist" \
                    "$HOME/.config/systemd/user/pandev-b2c-dashboard.service" \
                    "$HOME/.config/systemd/user/pandev-b2c-dashboard-open.service" \
                    "$HOME/.config/pandev/b2c-dashboard.sh" \
                    "$HOME/.config/pandev/b2c.firstrun" \
                    "$HOME/.config/pandev/autostart.off"; do
        if [ -e "$npx_mark" ]; then
            return 0
        fi
    done
    return 1
}

# Deletes everything in a directory except the names in $3, then the directory if it is empty.
# "All but this list", not "my own list": that is what also clears the leftovers of versions
# this script knows nothing about.
remove_dir_except() {
    if [ ! -e "$1" ]; then
        return 0
    fi
    if [ -z "$3" ]; then
        remove_path "$1" "$2"
        return 0
    fi
    dir_removed=0
    for entry in "$1"/* "$1"/.[!.]*; do
        if [ ! -e "$entry" ] && [ ! -L "$entry" ]; then
            continue
        fi
        entry_keep=0
        for keep_name in $3; do
            if [ "$(basename "$entry")" = "$keep_name" ]; then
                entry_keep=1
            fi
        done
        if [ "$entry_keep" = 0 ]; then
            rm -rf "$entry" 2>/dev/null || true
            dir_removed=1
        fi
    done
    rmdir "$1" 2>/dev/null || true
    if [ "$dir_removed" = 1 ]; then
        report_ok "$2"
    fi
    return 0
}

# Processes of the TEAM edition only. The npx daemon runs the same jar, so it is told apart by
# what only it has: its autostart shim, the npx cache in its path, or `dashboard --serve`.
team_pids() {
    pgrep -u "$uid" -f 'pandev-myapp\.jar|/pandev/bin/watcher\.sh' 2>/dev/null | while read -r pid; do
        case "$(ps -o command= -p "$pid" 2>/dev/null || true)" in
            *b2c-dashboard*|*_npx*|*"dashboard --serve"*) ;;
            *) printf '%s ' "$pid" ;;
        esac
    done
}

# Deletes a file or a directory tree; reports it only if it was there.
remove_path() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        rm -rf "$1" 2>/dev/null || true
        if [ -e "$1" ] || [ -L "$1" ]; then
            report_fail "$2 — could not remove $(pretty "$1")" "Delete it by hand."
        else
            report_ok "$2"
        fi
    fi
}

# A link in ~/.local/bin goes only if it leads into one of our directories:
# a `pandev` there may just as well be npm's.
remove_our_link() {
    [ -L "$1" ] || return 0
    case "$(readlink "$1" 2>/dev/null || true)" in
        */.pandev/*|*/.local/share/pandev/*|*/pandev-cli-plugin/*)
            remove_path "$1" "Command link removed ($(pretty "$1"))" ;;
    esac
}

# Each "# --- PANDEV <X> START ---" pairs only with its own END, and the blank line the
# program put before the block goes with it. A START without an END leaves the file as it
# was: cutting somebody's .zshrc to the end would be worse than a leftover hook.
remove_shell_hooks() {
    local rc tmp
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.profile"; do
        [ -f "$rc" ] || continue
        grep -q '^# --- PANDEV .* START ---$' "$rc" 2>/dev/null || continue
        tmp="$rc.pandev-uninstall.$$"
        if awk '
            {
                if (!inblock && $0 ~ /^# --- PANDEV .* START ---$/) {
                    name = substr($0, 1, length($0) - length(" START ---"))
                    inblock = 1; held = $0; heldblank = blank; blank = 0; next
                }
                if (inblock) {
                    held = held "\n" $0
                    if ($0 == name " END ---") { inblock = 0; held = ""; heldblank = 0 }
                    next
                }
                if (blank) { print ""; blank = 0 }
                if ($0 == "") { blank = 1; next }
                print
            }
            END {
                if (inblock) { if (heldblank) print ""; print held }
                if (blank) print ""
            }' "$rc" > "$tmp"; then
            # cat, not mv: keeps the owner, the mode and a dotfiles-manager symlink intact
            cat "$tmp" > "$rc"
        fi
        rm -f "$tmp"
        if grep -q '^# --- PANDEV .* START ---$' "$rc" 2>/dev/null; then
            report_fail "Shell hook is still in $(pretty "$rc")" "Delete the lines from '# --- PANDEV ... START ---' to its END."
        else
            report_ok "Shell hook removed from $(pretty "$rc")"
        fi
    done
}

run_uninstall() {
    local uid pattern had_service had_dashboard had_processes had_brew i round label pid_list
    uid="$(id -u)"
    echo ""

    # The npx edition stays whatever we find: separate product, separate uninstall.
    npx_stays=0
    if npx_present; then
        npx_stays=1
    fi
    had_service=0
    if [[ "$OS" == "Darwin" ]]; then
        if [ -e "$HOME/Library/LaunchAgents/io.pandev.watcher.plist" ]; then
            had_service=1
        fi
    elif [ -e "$HOME/.config/systemd/user/pandev-watcher.service" ]; then
        had_service=1
    fi
    had_processes=0
    if [ -n "$(team_pids)" ]; then
        had_processes=1
    fi

    # 1. The service first, so that nothing restarts what is stopped below.
    stop_team_watcher
    if [ "$had_service" = 1 ]; then
        report_ok "Background service removed"
    fi

    # 2. Whatever still runs: SIGTERM first — the watcher flushes its queue to disk — then SIGKILL.
    #    The sweep repeats until a round finds nothing: a supervisor that is still loaded brings
    #    a killed process back within seconds, and one sweep would call it stopped.
    round=0
    while [ "$round" -lt 3 ] && [ -n "$(team_pids)" ]; do
        kill -TERM $(team_pids) 2>/dev/null || true
        i=0
        while [ "$i" -lt 10 ] && [ -n "$(team_pids)" ]; do
            sleep 0.5
            i=$((i + 1))
        done
        kill -KILL $(team_pids) 2>/dev/null || true
        sleep 1.5
        round=$((round + 1))
    done
    pid_list="$(team_pids)"
    if [ -n "$pid_list" ]; then
        report_fail "PanDev processes are still running (PID $pid_list)" "Run: kill -9 $pid_list"
    elif [ "$had_processes" = 1 ]; then
        report_ok "PanDev processes stopped"
    fi

    # 3. Hooks, settings, data, the program.
    remove_shell_hooks
    keep_config=""
    keep_home=""
    config_label="Settings and credentials removed (~/.config/pandev)"
    if [ "$npx_stays" = 1 ]; then
        keep_config="$NPX_CONFIG_FILES"
        keep_home="$NPX_HOME_FILES"
        config_label="Settings and credentials removed; the npx edition's files kept (~/.config/pandev)"
    fi
    remove_dir_except "$HOME/.config/pandev" "$config_label" "$keep_config"
    remove_path "$HOME/.local/share/pandev" "Program data removed (~/.local/share/pandev)"
    remove_path "$HOME/Library/Application Support/pandev" "Program data removed (~/Library/Application Support/pandev)"
    remove_path "$HOME/.local/share/pandev-cli-plugin" "Old program files removed (~/.local/share/pandev-cli-plugin)"
    remove_path "$HOME/Library/Application Support/pandev-cli-plugin" "Old program files removed (~/Library/Application Support/pandev-cli-plugin)"
    remove_our_link "$BIN_LINK"
    remove_our_link "$BIN_DIR/pandev-cli-plugin"
    remove_path "$BIN_DIR/pandev-mcp" "MCP server shim removed (~/.local/bin/pandev-mcp)"
    remove_dir_except "$INSTALL_DIR" "Program files and local data removed (~/.pandev)" "$keep_home"
    if [ "$npx_stays" = 0 ]; then
        # Both pages are rebuilt by whoever runs `cost web`; ~/pandev-cost.html holds prompt
        # texts, so it goes as soon as nobody is left to rebuild it.
        remove_path "$HOME/pandev-open.html" "Dashboard jump page removed"
        remove_path "$HOME/pandev-cost.html" "Dashboard page removed (~/pandev-cost.html)"
    fi
    for f in "$PANDEV_TMP"/pandev_*; do
        if [ -O "$f" ]; then
            rm -rf "$f" 2>/dev/null || true
        fi
    done

    had_brew=0
    if command -v brew &>/dev/null \
            && brew list --formula 2>/dev/null | grep -qE '^pandev-cli-plugin(-beta)?$'; then
        had_brew=1
    fi
    remove_homebrew_install
    if [ "$had_brew" = 1 ]; then
        if brew list --formula 2>/dev/null | grep -qE '^pandev-cli-plugin(-beta)?$'; then
            report_fail "The program is still installed by Homebrew" "Run: brew uninstall --force pandev-cli-plugin pandev-cli-plugin-beta"
        else
            report_ok "Program removed (Homebrew)"
        fi
    fi

    if [ "$npx_stays" = 1 ]; then
        report_note "npx pandev stays — it is a separate product: remove it with  npx pandev uninstall"
    elif command -v npm &>/dev/null && npm ls -g --depth=0 pandev >/dev/null 2>&1; then
        report_note "The npx edition is installed globally (npm i -g pandev) — remove it with  npx pandev uninstall"
    fi

    # A system daemon of an early macOS version; only root can remove it, and we do not sudo.
    if [ -e /Library/LaunchDaemons/io.pandev.bpf-permissions.plist ]; then
        report_fail "A system service from an old version is still installed (io.pandev.bpf-permissions)" \
            "Run: sudo launchctl bootout system/io.pandev.bpf-permissions && sudo rm /Library/LaunchDaemons/io.pandev.bpf-permissions.plist"
    fi

    # 4. Check, don't assume.
    if [[ "$OS" == "Darwin" ]]; then
        for label in io.pandev.watcher; do
            if launchctl print "gui/$uid/$label" >/dev/null 2>&1; then
                report_fail "Service $label is still loaded" "Run: launchctl bootout gui/$uid/$label"
            fi
        done
    elif command -v systemctl &>/dev/null; then
        for label in pandev-watcher; do
            if systemctl --user is-active --quiet "$label.service" 2>/dev/null; then
                report_fail "Service $label is still running" "Run: systemctl --user disable --now $label.service"
            fi
        done
    fi
    hash -r 2>/dev/null || true
    if command -v pandev &>/dev/null; then
        found_pandev="$(command -v pandev)"
        case "$found_pandev$(readlink "$found_pandev" 2>/dev/null || true)" in
            *node_modules*)
                report_note "The npx edition answers \`pandev\` here ($found_pandev) — it is removed by: npx pandev uninstall" ;;
            *)
                report_fail "A pandev command is still on PATH: $found_pandev" "It was not installed by these installers; remove it by hand if it is PanDev." ;;
        esac
    fi

    if [ "$UNINSTALL_REPORTED" = 0 ]; then
        echo "  · Nothing of PanDev was found for this user."
    fi
    echo ""
    if [ "$UNINSTALL_CLEAN" = 1 ]; then
        if [ "$npx_stays" = 1 ]; then
            echo "✅ The PanDev CLI Plugin is removed."
        else
            echo "✅ PanDev is fully removed."
        fi
        return 0
    fi
    echo "❌ Some parts of PanDev are still here — see ✗ above."
    return 1
}

if [[ "$MODE" == "uninstall" ]]; then
    if [[ "$OS_NAME" == "Windows" ]]; then
        echo ""
        echo "On Windows, remove PanDev from PowerShell:"
        echo "  pandev uninstall-hooks"
        echo "  Stop-Process -Name pandev-watcher, pandev -Force -ErrorAction SilentlyContinue"
        echo "  Get-AppxPackage PandevInc.PandevCLIPlugin | Remove-AppxPackage"
        exit 1
    fi
    if run_uninstall; then
        exit 0
    fi
    exit 1
fi

# -------------------------------------------------------
# 3. macOS Command Line Tools check
# -------------------------------------------------------
if [[ "$OS" == "Darwin" ]]; then
    if ! xcode-select -p &>/dev/null; then
        echo "Command Line Tools not found."
        sudo xcode-select --install
        echo ""
        echo "Please complete installation and re-run this script."
        exit 0
    fi
fi

# -------------------------------------------------------
# 4. Windows — delegate to install-pandev.ps1 and exit
# -------------------------------------------------------
# On Windows there is no Homebrew, no ~/.local/bin convention, and no
# `pandev --install` post-install hook — MSIX install handles everything via
# Add-AppxPackage + the windows.startupTask manifest extension. Keep the
# Windows path completely separate from the macOS/Linux flow below.
if [[ "$OS_NAME" == "Windows" ]]; then
    if ! command -v powershell.exe >/dev/null 2>&1; then
        echo "ERROR: powershell.exe not on PATH."
        echo "       Run this script from Git Bash, MSYS2, or Cygwin on a host"
        echo "       where Windows PowerShell is available (default since Win 7)."
        exit 1
    fi

    # Detect un-templated state by SHA *shape* (64 lowercase hex chars),
    # NOT by literal token equality. The publish step's str.replace runs
    # over THE WHOLE FILE - including any literal token in this very
    # check - so a comparison like "$X == @TOKEN@" would always be true
    # after templating because both sides got rewritten to the same hash.
    # Length+regex check is immune to that self-replace.
    if ! [[ "$WINDOWS_AMD64_SHA256" =~ ^[a-f0-9]{64}$ ]]; then
        echo "ERROR: Windows installer is not available for v${VERSION}."
        echo "       The CI build for Windows failed for this release."
        echo "       Try a newer version once it lands, or contact the team."
        exit 1
    fi

    ASSET="pandev-cli-plugin_${VERSION}_Windows_amd64.zip"
    DOWNLOAD_URL="https://github.com/$REPO/releases/download/${TAG}/$ASSET"

    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    echo "Downloading $ASSET..."
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 30 --max-time 600 \
         "$DOWNLOAD_URL" -o "$TMP_DIR/$ASSET"

    echo "Verifying checksum..."
    ACTUAL_SHA=$(sha256sum "$TMP_DIR/$ASSET" | awk '{print $1}')
    if [[ "$ACTUAL_SHA" != "$WINDOWS_AMD64_SHA256" ]]; then
        echo "ERROR: SHA256 mismatch for $ASSET."
        echo "       expected: $WINDOWS_AMD64_SHA256"
        echo "       actual:   $ACTUAL_SHA"
        exit 1
    fi

    echo "Extracting..."
    if command -v unzip >/dev/null 2>&1; then
        unzip -q -o "$TMP_DIR/$ASSET" -d "$TMP_DIR"
    else
        # Git for Windows historically shipped unzip; fall back to PowerShell
        # Expand-Archive when it's absent (slim MSYS installs).
        powershell.exe -NoProfile -NonInteractive -Command \
            "Expand-Archive -Path '$(cygpath -w "$TMP_DIR/$ASSET")' -DestinationPath '$(cygpath -w "$TMP_DIR")' -Force"
    fi

    PS_SCRIPT_UNIX="$TMP_DIR/install-pandev.ps1"
    if [[ ! -f "$PS_SCRIPT_UNIX" ]]; then
        echo "ERROR: install-pandev.ps1 missing from $ASSET. Aborting."
        exit 1
    fi

    # Translate UNIX-style paths from MSYS/Cygwin to Windows-style so PowerShell
    # can resolve them. `cygpath -w` is provided by Git Bash, MSYS2, and Cygwin.
    PS_SCRIPT_WIN=$(cygpath -w "$PS_SCRIPT_UNIX")

    # Hand off to PowerShell. install-pandev.ps1 self-elevates via UAC,
    # imports the MSIX signing cert into LocalMachine\TrustedPeople, and runs
    # Add-AppxPackage. -NonInteractive skips the final "press any key" pause
    # so the curl|bash flow terminates cleanly.
    echo "Launching Windows installer (UAC prompt will appear)..."
    if ! powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT_WIN" -NonInteractive; then
        echo "ERROR: install-pandev.ps1 exited with a non-zero code." >&2
        exit 1
    fi

    echo ""
    echo "Installation complete!"
    echo ""
    echo "Open a NEW PowerShell window (so the 'pandev' appExecutionAlias resolves),"
    echo "then run: pandev login"
    echo ""
    exit 0
fi

# -------------------------------------------------------
# 5. Remove any existing installation (all channels, all eras, brew + direct)
# -------------------------------------------------------
echo "Removing existing installation (if any)..."

# Stop the running watcher first. The program goes right below, and a failed install used to
# leave the old LaunchAgent / unit behind, restarting a watcher whose program was gone, while
# the already running one kept sending until reboot (PDM-4862). `pandev --install` at the end
# registers the service again; credentials in ~/.config/pandev are not touched.
stop_team_watcher
remove_homebrew_install

# Remove a previous direct-install: drop only the unpacked app payload and the
# bin symlinks. Credentials/config live alongside the payload under ~/.pandev
# (e.g. ~/.pandev/credentials) — do NOT wipe the whole dir, or every reinstall
# logs the user out. Deleting just the payload dirs keeps the login intact.
rm -rf "$INSTALL_DIR/bin" "$INSTALL_DIR/lib" "$INSTALL_DIR/runtime" "$INSTALL_DIR/scripts"
rm -f "$BIN_LINK" "$BIN_DIR/pandev-cli-plugin"

echo "Cleanup complete."

# -------------------------------------------------------
# 6. Install (Homebrew on macOS, direct GitHub release otherwise)
# -------------------------------------------------------
if [[ "$OS" == "Darwin" ]] && command -v brew &>/dev/null; then
    echo "Homebrew detected: $(brew --version | head -1)"
    # The tap is the pandev-cli repo itself, addressed by explicit URL (the
    # repo intentionally has no homebrew- prefix). The short tap name stays
    # pandev-metriks/pandev-cli — the same name clients have always had.
    echo "Tapping $TAP from $TAP_URL..."
    brew tap "$TAP" "$TAP_URL" </dev/null
    # Homebrew 6.0+ refuses formulas from a tap nobody has trusted (PDM-4862). Running this
    # installer is asking for exactly this formula, so trust that one formula — not the whole
    # tap, as Homebrew recommends. Older brew has no `trust` command: nothing to do there.
    if brew trust --help &>/dev/null; then
        brew trust --formula "$FORMULA" </dev/null \
            || echo "WARNING: could not mark $FORMULA as trusted; Homebrew may refuse to install it."
    fi
    echo "Installing via Homebrew..."
    # Redirect stdin from /dev/null so brew install can't consume bytes from
    # the script itself when invoked via `curl ... | bash` (which would make
    # bash hit EOF early and silently skip the post-install steps).
    if ! brew install "$FORMULA" </dev/null; then
        echo ""
        echo "ERROR: Homebrew could not install $FORMULA (see the message above)."
        echo "  If it says the tap or a formula is not trusted, run:"
        echo "    brew trust --formula $FORMULA"
        echo "  and start this installer again."
        exit 1
    fi
else
    echo "Using direct GitHub release installation."
    echo "Version: $VERSION"

    ASSET="pandev-cli-plugin_${VERSION}_${OS_NAME}_${ARCH_NAME}.tar.gz"
    DOWNLOAD_URL="https://github.com/$REPO/releases/download/${TAG}/$ASSET"

    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    echo "Downloading $ASSET..."
    curl -fsSL "$DOWNLOAD_URL" -o "$TMP_DIR/$ASSET"

    echo "Extracting..."
    mkdir -p "$INSTALL_DIR"
    tar -xzf "$TMP_DIR/$ASSET" -C "$INSTALL_DIR"

    chmod +x "$INSTALL_DIR/bin/pandev" "$INSTALL_DIR/bin/pandev-cli-plugin"

    mkdir -p "$BIN_DIR"

    ln -sf "$INSTALL_DIR/bin/pandev" "$BIN_LINK"
    ln -sf "$INSTALL_DIR/bin/pandev-cli-plugin" "$BIN_DIR/pandev-cli-plugin"
fi

# -------------------------------------------------------
# 7. Add ~/.local/bin to PATH permanently
# -------------------------------------------------------

detect_profile() {
    if [ -n "$ZSH_VERSION" ]; then
        echo "$HOME/.zshrc"
    elif [ -n "$BASH_VERSION" ]; then
        if [[ "$OS" == "Darwin" ]]; then
            echo "$HOME/.bash_profile"
        else
            echo "$HOME/.bashrc"
        fi
    else
        echo "$HOME/.profile"
    fi
}

PROFILE_FILE=$(detect_profile)

add_path_if_missing() {
    if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$PROFILE_FILE" 2>/dev/null; then
        echo "" >> "$PROFILE_FILE"
        echo "# pandev-cli" >> "$PROFILE_FILE"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$PROFILE_FILE"
        echo "Added ~/.local/bin to PATH in $PROFILE_FILE"
    fi
}

if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    add_path_if_missing
    export PATH="$HOME/.local/bin:$PATH"
fi

# -------------------------------------------------------
# 8. Activate watchers (must run after install — important!)
# -------------------------------------------------------
echo ""
echo "Installation complete!"
echo ""

# Make freshly installed binaries findable in this shell session:
#  - brew shellenv adds Homebrew bin to PATH (covers fresh-PATH script invocation)
#  - hash -r drops bash's command-path cache so symlinks created during this run resolve
if command -v brew &>/dev/null; then
    eval "$(brew shellenv 2>/dev/null)" || true
fi
hash -r 2>/dev/null || true

# Locate pandev binary (PATH first, then brew prefix, then direct-install symlink)
PANDEV_BIN=""
if command -v pandev &>/dev/null; then
    PANDEV_BIN=$(command -v pandev)
elif command -v brew &>/dev/null; then
    BREW_PREFIX_BIN="$(brew --prefix 2>/dev/null)/bin/pandev"
    [ -x "$BREW_PREFIX_BIN" ] && PANDEV_BIN="$BREW_PREFIX_BIN"
fi
if [ -z "$PANDEV_BIN" ] && [ -x "$BIN_LINK" ]; then
    PANDEV_BIN="$BIN_LINK"
fi

if [ -n "$PANDEV_BIN" ]; then
    echo "Activating watchers via '$PANDEV_BIN --install'..."
    # Провал активации — это провал установки: программа лежит, а вотчер не запущен и
    # данные не собираются. Раньше скрипт печатал предупреждение и тут же объявлял
    # готовность с кодом 0, и `curl | bash` выглядел успешным.
    if "$PANDEV_BIN" --install; then
        echo ""
        echo "pandev is ready to use."
        echo "Try: pandev --version"
    else
        echo ""
        echo "ERROR: '$PANDEV_BIN --install' failed - the watcher is NOT running."
        echo "  The program itself is installed. Fix the cause, then run: $PANDEV_BIN --install"
        echo "  Details: $HOME/.local/share/pandev/logs/cli-error.log"
        exit 1
    fi
else
    echo "WARNING: pandev binary not found after install."
    echo "Restart your terminal and run: pandev --install"
fi

echo ""
