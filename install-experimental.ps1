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
      2.5.17               - semantic version, e.g. 2.5.0
      v2.5.17-beta                   - release tag hosting the assets, e.g. v2.5.0-beta
        - checksum of the Windows .zip asset
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

    UNINSTALL (PDM-4862): the same script removes PanDev of any version, with
    or without the package still installed:
      & ([scriptblock]::Create((iwr -useb <url>))) -Uninstall
#>
param(
    [switch] $Uninstall
)

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

    # -----------------------------------------------------------------------
    # Uninstall. MSIX never runs our code on removal, and old versions' own
    # `pandev uninstall-hooks` stripped only the hooks, leaving the watcher
    # running. This script is always the current one, so it removes PanDev of
    # any version, whether or not the package is still installed. No
    # administrator rights needed.
    # -----------------------------------------------------------------------
    if ($Uninstall) {
        $state = @{ Clean = $true; Reported = $false }
        function Write-Removed([string]$what) {
            $state.Reported = $true
            Write-Host "  [OK] $what" -ForegroundColor Green
        }
        function Write-Note([string]$what) {
            $state.Reported = $true
            Write-Host "  $what" -ForegroundColor Gray
        }
        function Write-Left([string]$what, [string]$fix) {
            $state.Clean = $false
            $state.Reported = $true
            Write-Host "  [X] $what" -ForegroundColor Red
            if ($fix) {
                Write-Host "      $fix" -ForegroundColor Yellow
            }
        }
        function Remove-OurPath([string]$path, [string]$what) {
            if (-not (Test-Path -LiteralPath $path)) {
                return
            }
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $path) {
                Write-Left "$what - could not remove $path" 'Delete it by hand.'
            } else {
                Write-Removed $what
            }
        }

        Write-Host ""
        Write-Host "Removing PanDev from this Windows account..." -ForegroundColor Cyan
        Write-Host ""

        # npx pandev is a SEPARATE PRODUCT: its own install command, its own uninstall
        # (PDM-4862). This script removes the team edition and leaves the npx edition running,
        # with its autostart, its program copy and its data. Any trace means it lives here.
        $startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
        $npxCopy = Join-Path $env:LOCALAPPDATA 'pandev'
        $npxMarks = @(
            (Join-Path $startup 'pandev-dashboard.vbs'),
            (Join-Path $startup 'pandev-dashboard-open.vbs'),
            (Join-Path $HOME '.config\pandev\b2c-dashboard.cmd'),
            (Join-Path $HOME '.config\pandev\b2c.firstrun'),
            (Join-Path $HOME '.config\pandev\autostart.off'),
            (Join-Path $npxCopy 'app')
        )
        $npxStays = @($npxMarks | Where-Object { $_ -and (Test-Path -LiteralPath $_) }).Count -gt 0

        # 1. Everything of OURS that runs. The npx dashboard runs pandev.exe too - out of its
        #    private copy, with 'dashboard --serve' on the command line - and its restart loop
        #    is a cmd.exe on b2c-dashboard.cmd. Both are told apart and left alone. taskkill
        #    through cmd: its "not found" on stderr must not turn into an error here.
        #    The list comes from Get-Process, which always works; WMI is asked only for the
        #    command lines that tell npx apart. With WMI unavailable the path alone does it,
        #    so the watcher is stopped either way.
        $images = @('pandev-watcher', 'pandev', 'pandev-mcp')
        $teamProcesses = {
            $lines = @{}
            foreach ($row in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
                $lines[[int]$row.ProcessId] = [string]$row.CommandLine
            }
            @(Get-Process -Name $images -ErrorAction SilentlyContinue | Where-Object {
                $line = $lines[[int]$_.Id]
                $isNpx = ($line -and ($line -match 'b2c-dashboard' -or $line -match 'dashboard\s+--serve' -or
                                      $line -match '\\_npx\\'))
                if (-not $isNpx -and $_.Path) {
                    $isNpx = $_.Path -match '\\_npx\\' -or
                        ($npxCopy -and $_.Path.StartsWith($npxCopy, [StringComparison]::OrdinalIgnoreCase))
                }
                -not $isNpx
            })
        }
        $found = $false
        for ($round = 0; $round -lt 3; $round++) {
            $running = & $teamProcesses
            if ($running.Count -eq 0) {
                break
            }
            $found = $true
            foreach ($proc in $running) {
                $null = cmd.exe /c "taskkill /F /T /PID $($proc.Id) >nul 2>&1"
            }
            Start-Sleep -Seconds 2
        }
        $left = & $teamProcesses
        if ($left.Count -gt 0) {
            $pids = ($left | ForEach-Object { $_.Id }) -join ', '
            Write-Left "PanDev processes are still running (PID $pids)" 'End them in Task Manager, then run this command again.'
        } elseif ($found) {
            Write-Removed 'PanDev processes stopped'
        }

        # 2. Hooks: each "# --- PANDEV <X> START ---" block goes with its own END; a START without
        #    an END leaves the file untouched. The encoding is kept - a BOM matters to PowerShell 5.1.
        # MyDocuments can come back empty - a roaming or locked-down profile, a wiped
        # shell-folder value in the registry. Join-Path then throws and the uninstall stops
        # at the hooks, never reaching the data or the package. So the profiles are only
        # looked at when there is a path to look at.
        $docs = [Environment]::GetFolderPath('MyDocuments')
        $hookFiles = @()
        if ($docs) {
            $hookFiles += @(
                (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
                (Join-Path $docs 'WindowsPowerShell\profile.ps1'),
                (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'),
                (Join-Path $docs 'PowerShell\profile.ps1')
            )
        } else {
            Write-Note 'Documents folder is unknown - PowerShell profiles were not checked for hooks'
        }
        $hookFiles += @(
            (Join-Path $HOME '.bashrc'),
            (Join-Path $HOME '.bash_profile')
        )
        foreach ($file in $hookFiles) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                continue
            }
            $text = [IO.File]::ReadAllText($file)
            if ($text -notmatch '# --- PANDEV [A-Z ]+ START ---') {
                continue
            }
            $stripped = [regex]::Replace($text,
                '(?s)(\r?\n)?# --- PANDEV (?<n>[A-Z ]+) START ---.*?# --- PANDEV \k<n> END ---(\r?\n)?', '')
            if ($stripped -ne $text) {
                $newline = "`n"
                if ($text.Contains("`r`n")) {
                    $newline = "`r`n"
                }
                $stripped = ([regex]::Replace($stripped, '(\r?\n){3,}', $newline + $newline)).Trim()
                $bytes = [IO.File]::ReadAllBytes($file)
                $encoding = New-Object System.Text.UTF8Encoding($false)
                if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                    $encoding = New-Object System.Text.UTF8Encoding($true)
                } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
                    $encoding = [System.Text.Encoding]::Unicode
                }
                if ([string]::IsNullOrWhiteSpace($stripped)) {
                    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
                } else {
                    [IO.File]::WriteAllText($file, $stripped + $newline, $encoding)
                }
            }
            if ((Test-Path -LiteralPath $file) -and ([IO.File]::ReadAllText($file) -match '# --- PANDEV [A-Z ]+ START ---')) {
                Write-Left "A PanDev hook is still in $file" "Delete the lines from '# --- PANDEV ... START ---' to its END."
            } else {
                Write-Removed "Hook removed from $file"
            }
        }

        # 3. Cost data outside the package. On Windows the team edition keeps its own state in
        #    the package's LocalState, and these places hold what `pandev cost web` wrote -
        #    which is also where the npx edition lives. So they go only when it does not.
        #    ~/pandev-cost.html is an offline copy of the dashboard and holds prompt texts.
        if ($npxStays) {
            Write-Note 'npx pandev stays - it is a separate product: remove it with  npx pandev uninstall'
        } else {
            Remove-OurPath (Join-Path $HOME '.config\pandev') 'Dashboard settings and data removed'
            Remove-OurPath (Join-Path $HOME '.pandev') 'Local data removed (.pandev)'
            Remove-OurPath (Join-Path $HOME 'pandev-open.html') 'Dashboard jump page removed'
            Remove-OurPath (Join-Path $HOME 'pandev-cost.html') 'Dashboard page removed (pandev-cost.html)'
            # The npm edition installed globally (npm i -g pandev) is a product of its own: it is
            # named, never removed here. Through cmd: npm is npm.cmd, and its stderr must not
            # turn into an error.
            if (Get-Command npm -ErrorAction SilentlyContinue) {
                $null = cmd.exe /c "npm ls -g --depth=0 pandev >nul 2>&1"
                if ($LASTEXITCODE -eq 0) {
                    Write-Note 'The npx edition is installed globally (npm i -g pandev) - remove it with  npx pandev uninstall'
                }
            }
        }

        # 4. The package last: Windows deletes its LocalState (token, queue, logs) with it.
        if (@(Get-AppxPackage -Name 'PandevInc.PandevCLIPlugin' -ErrorAction SilentlyContinue).Count -gt 0) {
            try {
                Get-AppxPackage -Name 'PandevInc.PandevCLIPlugin' | Remove-AppxPackage -ErrorAction Stop
            } catch {
                # checked right below
            }
            if (@(Get-AppxPackage -Name 'PandevInc.PandevCLIPlugin' -ErrorAction SilentlyContinue).Count -gt 0) {
                Write-Left 'The PanDev package is still installed' 'Settings > Apps > Installed apps > PanDev CLI Plugin > Uninstall'
            } else {
                Write-Removed 'Package removed (PanDev CLI Plugin)'
            }
        }

        if (-not $state.Reported) {
            Write-Host '  Nothing of PanDev was found for this account.'
        }
        $certs = @(Get-ChildItem -Path 'Cert:\LocalMachine\TrustedPeople' -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -match 'PanDev' })
        if ($certs.Count -gt 0) {
            Write-Host ""
            Write-Host "  The PanDev publisher certificate stays trusted on this computer: other accounts" -ForegroundColor Gray
            Write-Host "  may still use PanDev. To remove it, in PowerShell as administrator:" -ForegroundColor Gray
            Write-Host "    Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object Subject -match 'PanDev' | Remove-Item" -ForegroundColor Gray
        }
        Write-Host ""
        if ($state.Clean) {
            if ($npxStays) {
                Write-Host 'The PanDev CLI Plugin is removed.' -ForegroundColor Green
            } else {
                Write-Host 'PanDev is fully removed.' -ForegroundColor Green
            }
        } else {
            Write-Host 'Some parts of PanDev are still here - see [X] above.' -ForegroundColor Red
        }
        Write-Host ""
        return
    }

    # Templated by CI. Publish step rewrites these literals on every release.
    $VERSION = '2.5.17'
    $TAG = 'v2.5.17-beta'
    $WINDOWS_AMD64_SHA256 = ''

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
    # '', but the publish step's str.replace runs
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
