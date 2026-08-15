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
#    2.4.12               — semantic version, e.g. 2.5.0
#    v2.4.12-beta                   — release tag hosting the assets, e.g. v2.5.0-beta
#    Beta               — human-readable channel name: Beta | Stable
#    pandev-cli-plugin-beta               — formula name: pandev-cli-plugin[-beta]
#    52fb11346fc6eed9d54d11a503749a87a926d8887561b1c73fcbe2a29e4fb3eb  — checksum of the Windows .zip asset
#  macOS/Linux SHAs are enforced by the Homebrew Formula at install time.
# =============================================================================
set -e

VERSION="2.4.12"
TAG="v2.4.12-beta"
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
WINDOWS_AMD64_SHA256="52fb11346fc6eed9d54d11a503749a87a926d8887561b1c73fcbe2a29e4fb3eb"

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

echo "PanDev CLI installer — $CHANNEL channel, v$VERSION"
echo "Platform detected: $OS_NAME / $ARCH_NAME"

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

if command -v brew &>/dev/null; then
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
fi

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
    echo "Installing via Homebrew..."
    # Redirect stdin from /dev/null so brew install can't consume bytes from
    # the script itself when invoked via `curl ... | bash` (which would make
    # bash hit EOF early and silently skip the post-install steps).
    brew install "$FORMULA" </dev/null
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
    "$PANDEV_BIN" --install || echo "WARNING: '$PANDEV_BIN --install' failed. Run 'pandev --install' manually to activate watchers."
    echo ""
    echo "pandev is ready to use."
    echo "Try: pandev --version"
else
    echo "WARNING: pandev binary not found after install."
    echo "Restart your terminal and run: pandev --install"
fi

echo ""
