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
#    2.5.24               — semantic version, e.g. 2.5.0
#    v2.5.24-beta                   — release tag hosting the assets, e.g. v2.5.0-beta
#    Beta               — human-readable channel name: Beta | Stable
#    pandev-cli-plugin-beta               — formula name: pandev-cli-plugin[-beta]
#    826b811f5eb19a57180c54e1e1a11973a91184072a4313a3e78294ecca265512  — checksum of the Windows .zip asset
#    13f8f6cc500b4b1c643f68e11ef4fdd18bec97856c99dc940cf9f26ac556c654 / 683b4dbef434d811335135e8a6f9741191455ea3d3150a592e7d2bd28b49dd05 / 44248e5c07218af60df15a6ccbd9b8981b1884f9dc9d29a379dcfede366b9b23
#                            — checksums of the tar.gz assets (the same tokens the
#                              Formula uses); the direct install and the Homebrew
#                              pre-check verify the download against them (PDM-5479)
#
#  Usage:
#    install.sh                 install or update from the release this copy names
#    install.sh --from <dir>    install the direct (non-Homebrew) package from an
#                               already unpacked and verified release archive; no
#                               download (used by the updater, PDM-5478)
#    install.sh --uninstall     remove PanDev of any version
#
#  Order of an update (PDM-5479): everything that can fail for outside reasons —
#  download, checksum, unpacking, a test run of the new program — happens BEFORE
#  the installed version is touched. If any of it fails, the installed version
#  keeps running. If the new version cannot be activated, the previous one is put
#  back and activated again.
# =============================================================================
set -e

VERSION="2.5.24"
TAG="v2.5.24-beta"
CHANNEL="Beta"
FORMULA_NAME="pandev-cli-plugin-beta"

# The channel as the receipt and the updater name it (install.json, PDM-5479).
case "$CHANNEL" in
    Stable) CHANNEL_ID="prod" ;;
    Beta)   CHANNEL_ID="beta" ;;
    *)      CHANNEL_ID="" ;;
esac

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
WINDOWS_AMD64_SHA256="826b811f5eb19a57180c54e1e1a11973a91184072a4313a3e78294ecca265512"

# macOS/Linux: SHA256 of the tar.gz assets. The Formula verifies its own download, but the
# direct install had no check at all (PDM-5479), and the Homebrew path now downloads the
# archive once before anything is removed.
LINUX_AMD64_SHA256="13f8f6cc500b4b1c643f68e11ef4fdd18bec97856c99dc940cf9f26ac556c654"
MACOS_ARM64_SHA256="683b4dbef434d811335135e8a6f9741191455ea3d3150a592e7d2bd28b49dd05"
MACOS_AMD64_SHA256="44248e5c07218af60df15a6ccbd9b8981b1884f9dc9d29a379dcfede366b9b23"

# `curl ... | bash -s -- --uninstall` removes PanDev instead of installing it.
MODE="install"
FROM_DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --uninstall) MODE="uninstall" ;;
        --from)
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                echo "ERROR: --from needs the directory of an unpacked release archive."
                exit 1
            fi
            FROM_DIR="$2"
            shift
            ;;
        --from=*)
            FROM_DIR="${1#--from=}"
            if [ -z "$FROM_DIR" ]; then
                echo "ERROR: --from needs the directory of an unpacked release archive."
                exit 1
            fi
            ;;
        *)
            # An unknown option used to be ignored, and the script went on to a full network
            # install — exactly what the caller did not ask for (PDM-5479).
            echo "ERROR: unknown option: $1"
            echo "Usage: install.sh [--from <unpacked release dir>] | install.sh --uninstall"
            exit 1
            ;;
    esac
    shift
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
        # Юнит снят с диска, но systemd помнит его как failed: служба падает от нашего же
        # SIGTERM, и запись остаётся в `systemctl --user --failed` до перезагрузки.
        systemctl --user reset-failed pandev-watcher.service 2>/dev/null || true
    fi
    pkill -u "$(id -u)" -f 'pandev-myapp\.jar --watcher' 2>/dev/null || true
}

# PanDev changes nothing in Homebrew but its own formulas. Unasked, brew install and uninstall
# would also update Homebrew and every tap, upgrade the outdated dependents of whatever they
# upgraded, clean old versions of every formula once in 30 days and remove the dependencies
# nothing needs any more (a git someone uses every day, pulled in by an older PanDev formula).
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 \
    HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_AUTOREMOVE=1

# Both formulas, whatever tap they came from.
remove_homebrew_formulas() {
    command -v brew &>/dev/null || return 0
    brew unlink pandev-cli-plugin 2>/dev/null || true
    brew unlink pandev-cli-plugin-beta 2>/dev/null || true
    # --force + the BARE formula name removes EVERY installed version/keg of
    # the formula, whatever tap it came from, and works even if that tap is
    # already gone. Tap-qualified uninstall silently no-ops once the tap is
    # untapped and leaves a stale keg that makes the reinstall below a no-op.
    brew uninstall --force pandev-cli-plugin 2>/dev/null || true
    brew uninstall --force pandev-cli-plugin-beta 2>/dev/null || true
    brew cleanup pandev-cli-plugin 2>/dev/null || true
    brew cleanup pandev-cli-plugin-beta 2>/dev/null || true
}

# Both formulas, whatever tap they came from, and the taps themselves.
remove_homebrew_install() {
    command -v brew &>/dev/null || return 0
    remove_homebrew_formulas
    # Untap both the legacy taps and the current one (re-tapped below). The
    # legacy stable tap shares the pandev-metriks/pandev-cli short name.
    brew untap "$LEGACY_BETA_TAP" 2>/dev/null || true
    brew untap "$TAP" 2>/dev/null || true
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
b2c-dashboard.vbs b2c-dashboard-open.vbs b2c-dashboard.log b2c.firstrun b2c.present autostart.off \
autostart.unavailable dashboard.token budget.json budget.state.json cache zcode-workspace gemini-no-tools.toml gemini-workspace opencode-workspace \
codex-catalog.json codex-workspace claude-workspace"
NPX_HOME_FILES="profile-cache.json profile-domains.json profile-portrait.json profile.html"

# Any trace that the npx edition's own uninstall removes is enough: a service without its shim
# and a shim without its service both mean "the npx edition lives here". Whoever never took the
# autostart still has b2c.present, written by every npx run. npx's cache (~/.npm/_npx) is no
# sign: any `npx pandev` creates it, `npx pandev uninstall` too, and npm never clears it.
npx_traces_present() {
    for npx_mark in "$HOME/Library/LaunchAgents/io.pandev.b2c.dashboard.plist" \
                    "$HOME/Library/LaunchAgents/io.pandev.b2c.dashboard-open.plist" \
                    "$HOME/.config/systemd/user/pandev-b2c-dashboard.service" \
                    "$HOME/.config/systemd/user/pandev-b2c-dashboard-open.service" \
                    "$HOME/.config/pandev/b2c-dashboard.sh" \
                    "$HOME/.config/pandev/b2c.firstrun" \
                    "$HOME/.config/pandev/b2c.present" \
                    "$HOME/.config/pandev/autostart.off"; do
        if [ -e "$npx_mark" ]; then
            return 0
        fi
    done
    return 1
}

# installed globally: only npm removes it
npx_package_present() {
    command -v npm >/dev/null 2>&1 && npm ls -g --depth=0 pandev >/dev/null 2>&1
}

# Names in folder $1 that are not part of the skeleton (arguments as remove_skeleton). A function,
# not a loop inside $(...): bash 3.2 (/bin/bash on macOS) takes the ')' of a case pattern inside
# $(...) for the end of the substitution, and the whole script stopped on a syntax error
# (beta 2.5.22).
skeleton_extras() {
    ls -A "$1" 2>/dev/null | while IFS= read -r name; do
        entry="$1/$name"
        case " $2 " in
            *" $name "*) if [ -d "$entry" ] && [ ! -L "$entry" ] && [ -z "$(ls -A "$entry" 2>/dev/null)" ]; then continue; fi ;;
        esac
        if [ -n "$3" ] && [ "$name" = "$3" ] && [ -f "$entry" ] && [ ! -L "$entry" ] && [ ! -s "$entry" ]; then continue; fi
        echo "$name"
    done
}

# A folder of another tool that older watchers created where there was none: ~/.claude made only
# of empty debug/, projects/ and an empty history.jsonl, ~/.codex only of an empty sessions/. Gone
# only when the whole folder is such a skeleton — a live Claude Code or Codex always has something
# of its own there (settings.json, config.toml), and then nothing is touched.
#   $1 the folder, $2 names of subfolders that may be there empty, $3 a file that may be there empty
remove_skeleton() {
    [ -d "$1" ] && [ ! -L "$1" ] || return 0
    skeleton_extra=$(skeleton_extras "$1" "$2" "$3")
    [ -z "$skeleton_extra" ] || return 0
    if [ -n "$3" ] && [ -e "$1/$3" ]; then
        # renamed first: a write that starts now goes to a new file, one that came in time is kept
        mv "$1/$3" "$1/$3.pandev-removing" 2>/dev/null || return 0
        if [ -s "$1/$3.pandev-removing" ]; then
            mv -n "$1/$3.pandev-removing" "$1/$3" 2>/dev/null || true
            return 0
        fi
        rm -f "$1/$3.pandev-removing"
    fi
    for skeleton_dir in $2; do
        rmdir "$1/$skeleton_dir" 2>/dev/null || true
    done
    rmdir "$1" 2>/dev/null || true
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
    npx_note="npx pandev stays — it is a separate product: remove it with  npx pandev uninstall"
    if npx_traces_present; then
        npx_stays=1
    elif npx_package_present; then
        # only the global package: npx pandev uninstall would leave it, only npm removes it
        npx_stays=1
        npx_note="npx pandev stays — it is installed globally (npm i -g pandev): remove it with  npm uninstall -g pandev"
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

    # also when only its global package is here (npx_package_present)
    if [ "$npx_stays" = 1 ]; then
        report_note "$npx_note"
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
    # Skeletons of other tools' folders that older watchers created where there were none
    # (PDM-5182). Standard folders (~/.config, ~/.local/...) are not ours and stay, even empty.
    remove_skeleton "$HOME/.claude" "debug projects" "history.jsonl"
    remove_skeleton "$HOME/.codex" "sessions" ""
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
        # Not installed yet: a caller such as the updater must not take this for success.
        exit 1
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
    if [ -n "$FROM_DIR" ]; then
        echo "ERROR: --from is for the macOS/Linux direct install; Windows installs the MSIX package."
        exit 1
    fi
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

    # Hand off to PowerShell. install-pandev.ps1 checks the signature, carries
    # an install signed by the old test certificate over to the new package and
    # runs Add-AppxPackage - no administrator, the package is signed by PanDev's
    # SSL.com certificate (PDM-5088). -NonInteractive skips the final "press
    # any key" pause so the curl|bash flow terminates cleanly.
    echo "Launching Windows installer..."
    # The channel goes into the install receipt (LocalState\install.json, PDM-5479).
    PS_ARGS=(-NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT_WIN" -NonInteractive)
    if [ -n "$CHANNEL_ID" ]; then
        PS_ARGS+=(-Channel "$CHANNEL_ID")
    fi
    if ! powershell.exe "${PS_ARGS[@]}"; then
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
# 5. Prepare the new program — nothing installed is touched yet (PDM-5479)
# -------------------------------------------------------
# The payload directories of the direct install. Every path that finds the program
# (LauncherPath, the watcher.sh shim, the uninstallers) relies on exactly these under
# ~/.pandev, so an update replaces them in place instead of moving the install elsewhere.
PAYLOAD_DIRS="bin lib runtime scripts"
STAGE_DIR="$INSTALL_DIR/.staging.$$"
PREVIOUS_DIR="$INSTALL_DIR/.previous"
RECEIPT="$INSTALL_DIR/install.json"
LOCK_FILE="$INSTALL_DIR/.install.lock"

# prepare → replacing → done. While "replacing", any exit — an error under set -e, a signal —
# puts the previous version back (on_exit below): a half-finished update must never leave the
# machine without a working program or without the service.
PHASE="prepare"
LOCK_HELD=0
TMP_DIR=""
# set by recover_interrupted_swap — the run that died had stopped its service: 1 = it put the
# half-replaced previous version back, 2 = the install is whole and stays as it is
RECOVERED=0
# set when this run's swap found a program to move aside: a fresh install has nothing to go back to
HAD_PREVIOUS=0
# set when this run has started moving payloads: only then is .previous this run's own
SWAP_STARTED=0
# set when the new version refused --install: the rollback is expected, not a crash
ROLLBACK_REASON=""

# PanDev belongs to Homebrew here when one of our formulas is installed — not merely when brew
# is on PATH: a direct install on a Mac that got Homebrew later is still a direct install.
pandev_installed_by_brew() {
    command -v brew &>/dev/null || return 1
    brew list --formula 2>/dev/null </dev/null | grep -qE '^pandev-cli-plugin(-beta)?$'
}

USE_BREW=0
if [ -n "$FROM_DIR" ]; then
    if [[ "$OS" == "Darwin" ]] && pandev_installed_by_brew; then
        echo "ERROR: --from installs the direct (non-Homebrew) package, and on this Mac PanDev"
        echo "  is installed by Homebrew. Update it with: brew upgrade $FORMULA_NAME"
        exit 1
    fi
elif [[ "$OS" == "Darwin" ]] && command -v brew &>/dev/null; then
    USE_BREW=1
fi

# SHA256 of a file; GNU coreutils on Linux, shasum on macOS, openssl as a last resort.
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        openssl dgst -sha256 "$1" | awk '{print $NF}'
    fi
}

# The checksum this copy of the installer was published with, for this platform.
expected_sha256() {
    case "$OS_NAME/$ARCH_NAME" in
        Linux/amd64) echo "$LINUX_AMD64_SHA256" ;;
        macOS/arm64) echo "$MACOS_ARM64_SHA256" ;;
        macOS/amd64) echo "$MACOS_AMD64_SHA256" ;;
        *) echo "" ;;
    esac
}

# One installer at a time. Two of them used to wipe each other's staging and .previous — and
# with them the only copy of the previous version. The lock is a symlink whose target is the pid:
# created in one atomic step, so there is no moment when it exists without its owner.
install_lock_owner_alive() {
    lock_pid="$(readlink "$LOCK_FILE" 2>/dev/null || true)"
    [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null || return 1
    # An install never takes two hours (the download alone may take one: curl --max-time 900,
    # three retries). An older lock outlived its installer (SIGKILL, power loss) and the pid now
    # belongs to some other process — after a reboot pids are reused.
    [ -z "$(find "$LOCK_FILE" -maxdepth 0 -mmin +120 2>/dev/null)" ]
}

acquire_install_lock() {
    mkdir -p "$INSTALL_DIR"
    # `ln -s` into an existing directory does not fail: it puts the link inside and the lock looks
    # taken. A directory here is never a lock (a development build of this installer made one), so
    # it goes first; -n keeps a link that points at a directory from being followed the same way.
    if [ -d "$LOCK_FILE" ] && [ ! -L "$LOCK_FILE" ]; then
        rm -rf "$LOCK_FILE"
    fi
    if ! ln -sn "$$" "$LOCK_FILE" 2>/dev/null; then
        if install_lock_owner_alive; then
            echo "ERROR: another PanDev installer is running (PID $lock_pid, started less than"
            echo "  2 hours ago). Nothing was changed."
            exit 1
        fi
        # left by an installer that died
        rm -f "$LOCK_FILE"
        if ! ln -sn "$$" "$LOCK_FILE" 2>/dev/null; then
            echo "ERROR: could not lock $INSTALL_DIR for the install. Nothing was changed."
            exit 1
        fi
    fi
    LOCK_HELD=1
}

# An installer killed half-way through the swap left part of the program in .previous. Put the
# previous version back together before anything else: the swap below starts by clearing
# .previous, and that was the only copy of it.
recover_interrupted_swap() {
    [ -e "$PREVIOUS_DIR/bin/pandev" ] || return 0
    if [ -x "$INSTALL_DIR/bin/pandev" ] && [ -d "$INSTALL_DIR/lib" ] && [ -d "$INSTALL_DIR/runtime" ]; then
        # The install is whole, but the run that left .previous died after its swap and before
        # its activation finished (a finished one removes .previous at once) — with the service
        # already stopped. The installed version stays: an older one is never put over a whole
        # install. Whatever happens next, its service is started again.
        echo "An earlier install was interrupted after it had stopped the service."
        rm -rf "$PREVIOUS_DIR"
        RECOVERED=2
        return 0
    fi
    echo "An earlier install was interrupted: putting the previous version back first..."
    for payload_dir in $PAYLOAD_DIRS; do
        if [ -e "$PREVIOUS_DIR/$payload_dir" ]; then
            rm -rf "$INSTALL_DIR/$payload_dir"
            mv "$PREVIOUS_DIR/$payload_dir" "$INSTALL_DIR/$payload_dir"
        fi
    done
    if [ -f "$PREVIOUS_DIR/install.json" ]; then
        mv "$PREVIOUS_DIR/install.json" "$RECEIPT"
    fi
    rm -rf "$PREVIOUS_DIR"
    # the run that died had already stopped the service: whatever happens next, start it again
    RECOVERED=1
}

# Downloads the release archive of this platform into $TMP_DIR and verifies it. On any
# failure it exits — before the installed version is touched.
download_verified_asset() {
    ASSET="pandev-cli-plugin_${VERSION}_${OS_NAME}_${ARCH_NAME}.tar.gz"
    DOWNLOAD_URL="https://github.com/$REPO/releases/download/${TAG}/$ASSET"
    EXPECTED_SHA="$(expected_sha256)"
    # Shape, not equality with the token: the publish step replaces the token everywhere in
    # this file, a comparison with it would be rewritten too (see the Windows check above).
    if ! [[ "$EXPECTED_SHA" =~ ^[a-f0-9]{64}$ ]]; then
        echo "ERROR: this copy of the installer carries no checksum for $OS_NAME/$ARCH_NAME,"
        echo "  so it cannot download v$VERSION safely. Nothing was changed."
        echo "  Use the installer published with the release, or --from <unpacked archive>."
        exit 1
    fi
    echo "Downloading $ASSET..."
    if ! curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 30 --max-time 900 \
            "$DOWNLOAD_URL" -o "$TMP_DIR/$ASSET"; then
        echo "ERROR: the download failed. The installed version is not touched."
        exit 1
    fi
    echo "Verifying checksum..."
    ACTUAL_SHA="$(sha256_of "$TMP_DIR/$ASSET")"
    if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
        echo "ERROR: SHA256 mismatch for $ASSET. The installed version is not touched."
        echo "       expected: $EXPECTED_SHA"
        echo "       actual:   $ACTUAL_SHA"
        exit 1
    fi
}

# Puts the new payload into $STAGE_DIR (from the download or from --from) and runs it once.
stage_direct_payload() {
    # leftovers of installers that were killed half-way (the lock says none is running now)
    rm -rf "$INSTALL_DIR"/.staging.*
    mkdir -p "$STAGE_DIR"
    if [ -n "$FROM_DIR" ]; then
        if [ ! -x "$FROM_DIR/bin/pandev" ] || [ ! -d "$FROM_DIR/lib" ] || [ ! -d "$FROM_DIR/runtime" ]; then
            echo "ERROR: $FROM_DIR is not an unpacked PanDev release (no bin/pandev, lib/ or runtime/)."
            echo "  Nothing was changed."
            exit 1
        fi
        for payload_dir in $PAYLOAD_DIRS; do
            if [ -e "$FROM_DIR/$payload_dir" ]; then
                cp -pR "$FROM_DIR/$payload_dir" "$STAGE_DIR/"
            fi
        done
    else
        echo "Extracting..."
        if ! tar -xzf "$TMP_DIR/$ASSET" -C "$STAGE_DIR"; then
            echo "ERROR: the archive could not be unpacked. The installed version is not touched."
            exit 1
        fi
    fi
    chmod +x "$STAGE_DIR/bin/pandev" "$STAGE_DIR/bin/pandev-cli-plugin" 2>/dev/null || true
    if [ ! -x "$STAGE_DIR/bin/pandev" ] || [ ! -d "$STAGE_DIR/lib" ] || [ ! -d "$STAGE_DIR/runtime" ]; then
        echo "ERROR: the unpacked release has no bin/pandev, lib/ or runtime/. The installed version is not touched."
        exit 1
    fi
    # The new program must start on its own runtime before it replaces the old one.
    STAGED_VERSION="$("$STAGE_DIR/bin/pandev" --version 2>&1)" || {
        echo "ERROR: the new program does not start:"
        echo "$STAGED_VERSION" | tail -5
        echo "  The installed version is not touched."
        exit 1
    }
    # The whole version, not a prefix of it: v2.5.2 must not accept a program of v2.5.22.
    STAGED_V="$(printf '%s\n' "$STAGED_VERSION" | grep -o 'v[0-9][0-9.]*' | head -1)"
    if [[ "$VERSION" =~ ^[0-9] ]] && [ "$STAGED_V" != "v$VERSION" ]; then
        echo "ERROR: the unpacked program is ${STAGED_V:-of an unknown version}, not v$VERSION."
        echo "  The installed version is not touched."
        exit 1
    fi
}

# Swaps the staged payload in. The previous payload goes to $PREVIOUS_DIR so that a failed
# activation can put it back; renames inside ~/.pandev are instant and never cross a disk.
swap_in_staged_payload() {
    SWAP_STARTED=1
    if [ -e "$INSTALL_DIR/bin/pandev" ]; then
        HAD_PREVIOUS=1
    fi
    rm -rf "$PREVIOUS_DIR"
    mkdir -p "$PREVIOUS_DIR" || return 1
    for payload_dir in $PAYLOAD_DIRS; do
        if [ -e "$INSTALL_DIR/$payload_dir" ] || [ -L "$INSTALL_DIR/$payload_dir" ]; then
            mv "$INSTALL_DIR/$payload_dir" "$PREVIOUS_DIR/$payload_dir" || return 1
        fi
    done
    if [ -f "$RECEIPT" ]; then
        mv "$RECEIPT" "$PREVIOUS_DIR/install.json" || return 1
    fi
    for payload_dir in $PAYLOAD_DIRS; do
        if [ -e "$STAGE_DIR/$payload_dir" ]; then
            mv "$STAGE_DIR/$payload_dir" "$INSTALL_DIR/$payload_dir" || return 1
        fi
    done
    rmdir "$STAGE_DIR" 2>/dev/null || true
    # Check, don't assume: the program must be where every launcher looks for it.
    [ -x "$INSTALL_DIR/bin/pandev" ] && [ -d "$INSTALL_DIR/lib" ] && [ -d "$INSTALL_DIR/runtime" ]
}

# Undoes swap_in_staged_payload: the previous payload and receipt come back.
restore_previous_payload() {
    [ -d "$PREVIOUS_DIR" ] || return 1
    [ -e "$PREVIOUS_DIR/bin/pandev" ] || return 1
    for payload_dir in $PAYLOAD_DIRS; do
        if [ -e "$PREVIOUS_DIR/$payload_dir" ]; then
            rm -rf "$INSTALL_DIR/$payload_dir"
            mv "$PREVIOUS_DIR/$payload_dir" "$INSTALL_DIR/$payload_dir" || return 1
        fi
    done
    rm -f "$RECEIPT"
    if [ -f "$PREVIOUS_DIR/install.json" ]; then
        mv "$PREVIOUS_DIR/install.json" "$RECEIPT"
    fi
    rm -rf "$PREVIOUS_DIR"
}

# What was installed, by which channel — read by the updater (PDM-5478). Only when this copy
# was published for a channel: an unrendered template names none.
write_receipt() {
    [ -n "$CHANNEL_ID" ] || return 0
    printf '{"channel":"%s","kind":"direct","version":"%s","installed_at":"%s","installer":"install.sh"}\n' \
        "$CHANNEL_ID" "$VERSION" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$RECEIPT.tmp" \
        && mv "$RECEIPT.tmp" "$RECEIPT"
}

# Our tap, when it is already the pandev-cli repo by URL: then it is refreshed in place and never
# untapped — untapping would make `brew tap` below a network step after the old install is gone.
our_tap_dir() {
    tap_dir="$(brew --repository "$TAP" 2>/dev/null </dev/null || true)"
    [ -n "$tap_dir" ] && [ -d "$tap_dir/.git" ] || return 1
    # config, not `remote get-url`: the latter applies url.*.insteadOf (git@github.com: on many
    # developer machines) and would never match the https address brew tapped
    tap_remote="$(git -C "$tap_dir" config --get remote.origin.url 2>/dev/null </dev/null || true)"
    [ "$tap_remote" = "$TAP_URL" ] || [ "$tap_remote" = "$TAP_URL.git" ] || return 1
    printf '%s' "$tap_dir"
}

# Runs on every exit. While the installed version is being replaced, a stop of any kind puts
# the previous version back and starts it again.
on_exit() {
    exit_status=$?
    set +e
    # The reader of this output may be gone (Ctrl-C in `curl | bash | tee` takes tee with it; the
    # updater's pipe closes): the next echo would kill the installer by SIGPIPE half-way through
    # the rollback. The first write that finds the pipe closed sends the rest to /dev/null.
    trap 'exec >/dev/null 2>&1' PIPE
    if [ "$PHASE" = "replacing" ] || { [ "$PHASE" = "prepare" ] && [ "$RECOVERED" != 0 ]; }; then
        # Putting the previous version back takes seconds and must not be cut short. INT and HUP
        # are ignored; TERM only sets a flag — an ignored TERM would be inherited by the watcher
        # that --install starts, and `pkill` (stop_team_watcher) could never stop it again.
        trap '' INT HUP
        trap 'ROLLBACK_SIGNALLED=1' TERM
        echo ""
        if [ "$PHASE" = "prepare" ] && [ "$RECOVERED" = 1 ]; then
            echo "ERROR: the installer stopped (exit $exit_status) after putting back the version an"
            echo "  interrupted install had left half-replaced."
        elif [ "$PHASE" = "prepare" ]; then
            echo "ERROR: the installer stopped (exit $exit_status); an earlier install had stopped the"
            echo "  service and never started it again."
        elif [ -z "$ROLLBACK_REASON" ]; then
            echo "ERROR: the installer stopped half-way (exit $exit_status)."
        fi
        if [ "$USE_BREW" = 0 ]; then
            # Only this run's .previous: one left by an earlier run is older than what is installed.
            if [ "$SWAP_STARTED" = 1 ] && restore_previous_payload; then
                echo "  The previous version is put back."
            fi
            # The program in ~/.pandev is the previous one: put back above, or never moved when
            # the stop came before the swap — or, on a fresh install, the new one, there being
            # nothing to go back to. The service is down either way — start it again.
            if [ "$SWAP_STARTED" = 1 ] && [ "$HAD_PREVIOUS" = 0 ]; then
                started="  The new version is running, but the installer did not finish: start it again."
                not_started="  PanDev could not be started."
            else
                started="  The previous version is running again; the update did not happen."
                not_started="  The previous version could not be started either."
            fi
            if [ -x "$INSTALL_DIR/bin/pandev" ]; then
                # The new version may have started a watcher of its own already.
                stop_team_watcher
                if "$INSTALL_DIR/bin/pandev" --install; then
                    echo "$started"
                else
                    echo "$not_started"
                    echo "  Fix the cause, then run: $INSTALL_DIR/bin/pandev --install"
                fi
            else
                echo "  Start this installer again."
            fi
        else
            echo "  Homebrew did not finish installing $FORMULA. Start this installer again,"
            echo "  or run: brew install $FORMULA && pandev --install"
        fi
        if [ "$exit_status" = 0 ]; then
            exit_status=1
        fi
    fi
    [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
    rm -rf "$STAGE_DIR"
    if [ "$LOCK_HELD" = 1 ] && [ "$(readlink "$LOCK_FILE" 2>/dev/null)" = "$$" ]; then
        # A fresh install leaves an empty .previous behind when its activation fails. Under our
        # own lock only: an installer the lock turned away must not touch the running one's.
        rmdir "$PREVIOUS_DIR" 2>/dev/null || true
        rm -f "$LOCK_FILE"
        # a Homebrew install has nothing else there: the lock alone made the directory
        rmdir "$INSTALL_DIR" 2>/dev/null || true
    fi
    exit "$exit_status"
}
trap on_exit EXIT
# Signals end the script through the EXIT trap above, so a killed installer still rolls back.
trap 'exit 130' INT
trap 'exit 143' TERM HUP
# Without a trap SIGPIPE kills bash outright — bash 3.2 does not even run the EXIT trap then.
trap 'exit 141' PIPE

acquire_install_lock
TMP_DIR=$(mktemp -d)

BREW_TAP_DIR=""
if [ "$USE_BREW" = 1 ]; then
    # Homebrew downloads the archive itself, but only after the old install is gone — a
    # network failure there used to leave the Mac without PanDev. Download it here first:
    # a failure stops the installer with nothing changed, and the verified file is handed
    # to Homebrew's cache below, so brew install needs no second download.
    download_verified_asset
    # Our tap already in place: refresh it now, while the old install still runs. A failed
    # refresh only means the full re-tap below.
    if BREW_TAP_DIR="$(our_tap_dir)"; then
        if ! git -C "$BREW_TAP_DIR" pull --ff-only -q </dev/null; then
            BREW_TAP_DIR=""
        fi
    else
        BREW_TAP_DIR=""
    fi
else
    recover_interrupted_swap
    if [ -z "$FROM_DIR" ]; then
        download_verified_asset
    fi
    stage_direct_payload
fi

# -------------------------------------------------------
# 6. Replace the installed version (all channels, all eras, brew + direct)
# -------------------------------------------------------
echo "Replacing the installed version (if any)..."
PHASE="replacing"

# Stop the running watcher first. The program goes right below, and a failed install used to
# leave the old LaunchAgent / unit behind, restarting a watcher whose program was gone, while
# the already running one kept sending until reboot (PDM-4862). `pandev --install` at the end
# registers the service again; credentials in ~/.config/pandev are not touched.
stop_team_watcher
if [ -n "$BREW_TAP_DIR" ]; then
    # Our tap stays: only the formulas go, and the legacy beta tap.
    remove_homebrew_formulas
    brew untap "$LEGACY_BETA_TAP" 2>/dev/null || true
else
    remove_homebrew_install
fi

if [ "$USE_BREW" = 1 ]; then
    # Brew replaces the direct install: drop only its payload, receipt and the bin symlinks.
    # Credentials/config live alongside the payload under ~/.pandev (e.g. ~/.pandev/credentials)
    # — do NOT wipe the whole dir, or every reinstall logs the user out.
    for payload_dir in $PAYLOAD_DIRS; do
        rm -rf "$INSTALL_DIR/$payload_dir"
    done
    rm -rf "$RECEIPT" "$PREVIOUS_DIR"
    rm -f "$BIN_LINK" "$BIN_DIR/pandev-cli-plugin"
    echo "Homebrew detected: $(brew --version | head -1)"
    if [ -z "$BREW_TAP_DIR" ]; then
        # The tap is the pandev-cli repo itself, addressed by explicit URL (the
        # repo intentionally has no homebrew- prefix). The short tap name stays
        # pandev-metriks/pandev-cli — the same name clients have always had.
        # Without our tap in place (a first install, or the legacy tap of the same short name)
        # this is the one network step left after the old install is gone.
        echo "Tapping $TAP from $TAP_URL..."
        brew tap "$TAP" "$TAP_URL" </dev/null
    fi
    # Homebrew 6.0+ refuses formulas from a tap nobody has trusted (PDM-4862). Running this
    # installer is asking for exactly this formula, so trust that one formula — not the whole
    # tap, as Homebrew recommends. Older brew has no `trust` command: nothing to do there.
    if brew trust --help &>/dev/null; then
        brew trust --formula "$FORMULA" </dev/null \
            || echo "WARNING: could not mark $FORMULA as trusted; Homebrew may refuse to install it."
    fi
    # The archive verified above goes where Homebrew looks for its download: brew checks it
    # against the Formula's sha256 and installs without fetching it again. If the cache path
    # cannot be told, brew simply downloads the archive itself.
    BREW_CACHE_FILE="$(brew --cache --formula "$FORMULA" 2>/dev/null </dev/null || true)"
    if [ -n "$BREW_CACHE_FILE" ]; then
        mkdir -p "$(dirname "$BREW_CACHE_FILE")" 2>/dev/null \
            && cp "$TMP_DIR/$ASSET" "$BREW_CACHE_FILE" 2>/dev/null || true
    fi
    echo "Installing via Homebrew..."
    # Redirect stdin from /dev/null so brew install can't consume bytes from
    # the script itself when invoked via `curl ... | bash` (which would make
    # bash hit EOF early and silently skip the post-install steps).
    # No auto-update (HOMEBREW_NO_AUTO_UPDATE above): our tap is fresh — refreshed before the
    # stop or tapped just now — and the formula has no dependencies to look up.
    brew_installed=0
    brew install "$FORMULA" </dev/null && brew_installed=1
    if [ "$brew_installed" = 0 ]; then
        echo ""
        echo "ERROR: Homebrew could not install $FORMULA (see the message above)."
        echo "  If it says the tap or a formula is not trusted, run:"
        echo "    brew trust --formula $FORMULA"
        echo "  and start this installer again."
        PHASE="done"
        exit 1
    fi
else
    echo "Using direct GitHub release installation."
    echo "Version: $VERSION"
    if ! swap_in_staged_payload; then
        echo "ERROR: could not move the new program into $INSTALL_DIR."
        exit 1
    fi
    # Not critical: without the receipt the updater asks for the channel, without the link
    # the program still runs from ~/.pandev/bin — neither may cost the update itself.
    write_receipt || echo "WARNING: could not write the install receipt ($RECEIPT)."
    { mkdir -p "$BIN_DIR" \
        && ln -sf "$INSTALL_DIR/bin/pandev" "$BIN_LINK" \
        && ln -sf "$INSTALL_DIR/bin/pandev-cli-plugin" "$BIN_DIR/pandev-cli-plugin"; } \
        || echo "WARNING: could not create the command links in $BIN_DIR; the program is $INSTALL_DIR/bin/pandev."
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
        { echo ""; echo "# pandev-cli"; echo 'export PATH="$HOME/.local/bin:$PATH"'; } \
            >> "$PROFILE_FILE" 2>/dev/null || return 1
        echo "Added ~/.local/bin to PATH in $PROFILE_FILE"
    fi
}

if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    # Not critical either: a profile that is not ours to write (home-manager, a read-only
    # dotfile) must not cost the update.
    add_path_if_missing || echo "WARNING: could not add ~/.local/bin to PATH in $PROFILE_FILE; add it yourself."
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

# The program this installer has just put in place — not whatever `pandev` comes first on PATH:
# a global npm `pandev` (the npx edition) earlier on PATH refuses --install, and the update
# would be rolled back every time.
PANDEV_BIN=""
if [ "$USE_BREW" = 0 ]; then
    PANDEV_BIN="$INSTALL_DIR/bin/pandev"
else
    if command -v brew &>/dev/null; then
        BREW_PREFIX_BIN="$(brew --prefix 2>/dev/null)/bin/pandev"
        [ -x "$BREW_PREFIX_BIN" ] && PANDEV_BIN="$BREW_PREFIX_BIN"
    fi
    if [ -z "$PANDEV_BIN" ] && command -v pandev &>/dev/null; then
        PANDEV_BIN=$(command -v pandev)
    fi
fi

if [ -z "$PANDEV_BIN" ] || [ ! -x "$PANDEV_BIN" ]; then
    PHASE="done"
    echo "ERROR: the pandev program is not found after the install, so the watcher could not be started."
    echo "Restart your terminal and run: pandev --install"
    exit 1
fi

echo "Activating watchers via '$PANDEV_BIN --install'..."
# Провал активации — это провал установки: программа лежит, а вотчер не запущен и
# данные не собираются. Раньше скрипт печатал предупреждение и тут же объявлял
# готовность с кодом 0, и `curl | bash` выглядел успешным.
if "$PANDEV_BIN" --install; then
    # The new version runs: the previous payload is no longer needed.
    PHASE="done"
    rm -rf "$PREVIOUS_DIR"
    echo ""
    echo "pandev is ready to use."
    echo "Try: pandev --version"
else
    echo ""
    echo "ERROR: '$PANDEV_BIN --install' failed - the watcher is NOT running."
    ROLLBACK_REASON="activation"
    # A direct update keeps the previous version until the new one is activated: on_exit puts
    # it back and starts it again, so a broken release does not leave the machine without data
    # collection (PDM-5479). A fresh install and Homebrew have nothing to go back to.
    if [ "$USE_BREW" = 1 ] || [ ! -e "$PREVIOUS_DIR/bin/pandev" ]; then
        PHASE="done"
        echo "  The program itself is installed. Fix the cause, then run: $PANDEV_BIN --install"
    fi
    echo "  Details: $HOME/.local/share/pandev/logs/cli-error.log"
    exit 1
fi

echo ""
