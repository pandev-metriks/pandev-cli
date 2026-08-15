<#
.SYNOPSIS
    PanDev CLI - install bootstrap (PowerShell-native).

.DESCRIPTION
    Single-command install entry point for Windows users who don't have
    Git Bash / WSL / Cygwin available. Mirrors the macOS/Linux
    `curl ... | bash` UX but speaks native PowerShell so users can
    copy-paste:

      beta:   iwr -useb https://raw.githubusercontent.com/pandev-metriks/homebrew-pandev-cli-beta/main/install-experimental.ps1 | iex
      stable: iwr -useb https://raw.githubusercontent.com/pandev-metriks/homebrew-pandev-cli/main/install.ps1 | iex

    Steps:
      1. Download the Windows .zip release asset for the templated VERSION.
      2. Verify SHA256 against the value baked in at publish time.
      3. Extract into a temp directory.
      4. Invoke install-pandev.ps1 from the extracted bundle. That script
         self-elevates via UAC, imports the publisher cert into
         LocalMachine\TrustedPeople, and runs Add-AppxPackage.

    Source-of-truth lives in pdm-source/release/install-experimental.ps1.
    Both release CI workflows render it on every release: the beta workflow
    into the beta tap as install-experimental.ps1, the prod workflow into
    the stable tap as install.ps1. Only the @-tokens below differ between
    the rendered copies - the install logic itself is channel-agnostic.

    Tokens replaced by the publish step (do NOT pre-fill them here):
      2.4.12               - semantic version, e.g. 2.5.0
      v2.4.12-beta                   - release tag hosting the assets, e.g. v2.5.0-beta
      0f1c5326e691b2bb971ccccdf8acbe3d8d627eff6688e07cef15d5ae471bfa54  - checksum of the Windows .zip asset
      pandev-metriks/pandev-cli                  - repo whose GitHub release hosts the .zip
      Beta               - display label: Beta or Stable

    EXECUTION MODEL:
    Designed to be safe under `iwr | iex` - i.e., when iex runs the
    downloaded text in the user's CURRENT PowerShell session. That means:
      - DON'T set $ErrorActionPreference at the top level (would leak to
        the user's session and turn every later command-not-found into a
        session-killing terminating error).
      - DON'T use `exit` for error paths (would close the user's terminal).
    Everything runs inside a scriptblock `& { ... }` so $ErrorActionPreference
    is scoped to that block, and error paths use `return` instead of `exit`.
#>

# Wrap the whole installer in a scriptblock so any preference changes
# (especially $ErrorActionPreference = 'Stop') stay scoped to the block.
# When invoked as `iwr | iex`, the script's top level runs in the caller's
# session - leaking 'Stop' into that session would kill the terminal on
# the next command-not-found.
& {
    $ErrorActionPreference = 'Stop'

    # Force UTF-8 on the console so user-facing messages don't get mangled
    # on hosts with non-UTF-8 OEM code pages. Best-effort.
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    } catch {
        # Pre-PS 5.0 / locked-down hosts. Not fatal.
    }

    # Templated by CI. Publish step rewrites these literals on every release.
    $VERSION = '2.4.12'
    $TAG = 'v2.4.12-beta'
    $WINDOWS_AMD64_SHA256 = '0f1c5326e691b2bb971ccccdf8acbe3d8d627eff6688e07cef15d5ae471bfa54'

    $REPO = 'pandev-metriks/pandev-cli'
    $ASSET_NAME = "pandev-cli-plugin_${VERSION}_Windows_amd64.zip"
    $DOWNLOAD_URL = "https://github.com/$REPO/releases/download/${TAG}/$ASSET_NAME"

    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "  PanDev CLI Plugin - Beta install (Windows)" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "  Version: $VERSION"
    Write-Host ""

    # -----------------------------------------------------------------------
    # Sanity checks. Use `return` (exits the scriptblock) instead of `exit`
    # (would close the iex-invoking session). The caller sees a no-op return,
    # not a dead terminal.
    # -----------------------------------------------------------------------
    if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
        Write-Host "ERROR: This installer is Windows-only." -ForegroundColor Red
        Write-Host "       For macOS/Linux use the Homebrew tap or the .sh installer." -ForegroundColor Red
        return
    }

    # Detect un-templated state by SHA *shape* (64 lowercase hex chars),
    # NOT by literal token equality. Earlier we compared against
    # '0f1c5326e691b2bb971ccccdf8acbe3d8d627eff6688e07cef15d5ae471bfa54', but the publish step's str.replace runs
    # over THE WHOLE FILE - including the literal token inside this check
    # - so after templating the comparison became
    # "$WINDOWS_AMD64_SHA256 -eq <the actual hash>", which is always true,
    # so the script always reported "installer not available" even on
    # successful builds. Length+regex check is immune to this self-replace.
    if ($WINDOWS_AMD64_SHA256 -notmatch '^[a-f0-9]{64}$') {
        Write-Host "ERROR: Windows installer is not available for v$VERSION." -ForegroundColor Red
        Write-Host "       The CI build for Windows failed for this release." -ForegroundColor Red
        Write-Host "       Try a newer version once it lands, or contact the team." -ForegroundColor Red
        return
    }

    # -----------------------------------------------------------------------
    # Download + verify + extract + hand off
    # -----------------------------------------------------------------------
    $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pandev-install-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
    $zipPath = Join-Path $tmpRoot $ASSET_NAME

    # Track success so the catch block can report cleanly without bubbling
    # an exception up into the user's session.
    $installSucceeded = $false

    try {
        Write-Host "Downloading $ASSET_NAME..."
        Invoke-WebRequest -UseBasicParsing -Uri $DOWNLOAD_URL -OutFile $zipPath

        Write-Host "Verifying checksum..."
        $actualSha = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $expectedSha = $WINDOWS_AMD64_SHA256.ToLowerInvariant()
        if ($actualSha -ne $expectedSha) {
            throw "SHA256 mismatch for $ASSET_NAME. expected=$expectedSha actual=$actualSha"
        }

        Write-Host "Extracting..."
        Expand-Archive -Path $zipPath -DestinationPath $tmpRoot -Force

        $installer = Join-Path $tmpRoot 'install-pandev.ps1'
        if (-not (Test-Path -LiteralPath $installer)) {
            throw "install-pandev.ps1 missing from $ASSET_NAME after extract."
        }

        # Hand off in a SEPARATE powershell.exe process (not in this scope):
        #   - install-pandev.ps1 self-elevates via UAC and calls `exit` on
        #     finish; running in a separate process keeps that exit from
        #     terminating either our scriptblock or the user's session.
        #   - The child uses its own console window (no -NoNewWindow) so
        #     the install log doesn't compete with the user's prompt and
        #     the elevation flow is visually obvious.
        Write-Host ""
        Write-Host "Launching install-pandev.ps1 (UAC prompt will appear)..." -ForegroundColor Yellow
        Write-Host ""

        $childArgs = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', "`"$installer`""
        )
        $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $childArgs -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            # Don't throw - that would propagate via iex back to the user
            # session and (with their EAP) could close the terminal.
            # Print and return instead.
            Write-Host ""
            Write-Host "ERROR: install-pandev.ps1 exited with code $($proc.ExitCode)." -ForegroundColor Red
            Write-Host "       See the elevated PowerShell window for details." -ForegroundColor Red
            return
        }

        $installSucceeded = $true
    } catch {
        Write-Host ""
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        # Swallow the exception - don't propagate to caller's session.
    } finally {
        try {
            Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Host "(temp directory $tmpRoot was left behind; delete manually if you care)" -ForegroundColor DarkGray
        }
    }

    if (-not $installSucceeded) {
        # Already printed the failure reason above; just return so the
        # caller's session continues unharmed.
        return
    }

    # -----------------------------------------------------------------------
    # Make the `pandev` command actually resolvable.
    #
    # `pandev` ships as an MSIX appExecutionAlias: a 0-byte launcher stub that
    # Add-AppxPackage drops into %LOCALAPPDATA%\Microsoft\WindowsApps. The
    # command only resolves when BOTH are true:
    #   (a) %LOCALAPPDATA%\Microsoft\WindowsApps is on the user's PATH, and
    #   (b) "App execution aliases" is enabled for pandev in Windows Settings.
    # Windows normally seeds (a) out of the box, but locked-down / re-imaged /
    # hand-edited profiles sometimes lose it - which is exactly the "installs
    # fine but the terminal can't find pandev" report. We can repair (a) here
    # so a freshly opened terminal works; we can't flip (b) for the user, so we
    # detect the failure and tell them precisely what to do.
    # -----------------------------------------------------------------------
    $windowsApps = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'

    if ($env:LOCALAPPDATA) {
        # Read the *persisted* user PATH (not $env:Path, which is the merged
        # process view) so we edit the real registry value.
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')

        $alreadyOnPath = $false
        if ($userPath) {
            foreach ($p in ($userPath -split ';')) {
                if ($p -and ($p.TrimEnd('\') -ieq $windowsApps.TrimEnd('\'))) {
                    $alreadyOnPath = $true
                    break
                }
            }
        }

        if (-not $alreadyOnPath) {
            try {
                $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
                    $windowsApps
                } else {
                    ($userPath.TrimEnd(';') + ';' + $windowsApps)
                }
                # 'User' scope writes HKCU\Environment (no admin needed) and
                # broadcasts WM_SETTINGCHANGE, so terminals opened *after* this
                # inherit it. Already-open shells won't - hence the refresh below.
                [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
                Write-Host "Added '$windowsApps' to your user PATH (required for the 'pandev' command)." -ForegroundColor Yellow
            } catch {
                Write-Host "WARNING: could not add '$windowsApps' to your PATH automatically: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        # Refresh PATH in THIS session (Machine + User) so the verify below can
        # succeed without a terminal restart. Best-effort; other shells unaffected.
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $freshUser   = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path = (@($machinePath, $freshUser) | Where-Object { $_ }) -join ';'
    }

    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "  PanDev CLI installed successfully" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green

    # -----------------------------------------------------------------------
    # If the user is ALREADY logged in, start the watcher live right now.
    #
    # The watcher only auto-starts via the MSIX windows.startupTask, which
    # fires at the NEXT user logon. On a reinstall/upgrade over an existing
    # login that means the watcher stays dead - and coding time goes
    # untracked - until the user happens to sign out and back in. When we can
    # see an existing login (token persisted in this package's LocalState), we
    # launch it now via `pandev --watcher` so tracking resumes immediately. A
    # brand-new (not-yet-logged-in) install needs nothing here: `pandev login`
    # starts the watcher itself.
    # -----------------------------------------------------------------------
    $loggedIn = $false
    try {
        $pkg = Get-AppxPackage -Name 'PandevInc.PandevCLIPlugin' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pkg) {
            $tokenFile = Join-Path $env:LOCALAPPDATA "Packages\$($pkg.PackageFamilyName)\LocalState\token"
            $loggedIn = (Test-Path -LiteralPath $tokenFile) -and ((Get-Item -LiteralPath $tokenFile).Length -gt 0)
        }
    } catch {
    }

    $pandevReady = [bool](Get-Command pandev -ErrorAction SilentlyContinue)

    if ($loggedIn -and $pandevReady) {
        try {
            Start-Process -FilePath 'pandev' -ArgumentList '--watcher' -WindowStyle Hidden
            Write-Host "Watcher started - your coding activity is being tracked now." -ForegroundColor Green
        } catch {
            Write-Host "NOTE: could not start the watcher now ($($_.Exception.Message))." -ForegroundColor Yellow
            Write-Host "      It will start automatically at your next sign-in." -ForegroundColor Yellow
        }
    }

    if ($pandevReady) {
        Write-Host "The 'pandev' command is ready in this window." -ForegroundColor Green
        if (-not $loggedIn) {
            Write-Host "Run: pandev login"
        }
    } else {
        # PATH is now fixed for future shells, but this one may still be stale,
        # or the appExecutionAlias didn't register / is toggled off.
        Write-Host "'pandev' does not resolve in THIS window yet." -ForegroundColor Yellow
        Write-Host ""
        if ($loggedIn) {
            Write-Host "  You're already logged in. Open a NEW PowerShell window to use 'pandev';"
            Write-Host "  the watcher will start at your next sign-in either way."
        } else {
            Write-Host "  1. Open a NEW PowerShell window, then run:  pandev login"
        }
        Write-Host ""
        Write-Host "If a brand-new window still can't find 'pandev':" -ForegroundColor Yellow
        if (Test-Path -LiteralPath (Join-Path $windowsApps 'pandev.exe')) {
            Write-Host "  - Open Windows Settings -> Apps -> Advanced app settings ->"
            Write-Host "    'App execution aliases' and make sure the alias for PanDev is ON."
        } else {
            Write-Host "  - The app-execution alias was not created. Open Windows Settings ->"
            Write-Host "    Apps -> Advanced app settings -> 'App execution aliases' and turn the"
            Write-Host "    PanDev alias ON, then reopen your terminal."
        }
    }
    Write-Host ""
}
