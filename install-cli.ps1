# Install the newest `knwlge` developer CLI release on Windows.
#
#   irm https://raw.githubusercontent.com/Replient/knwlge-releases/main/install-cli.ps1 | iex
#
# From cmd.exe, install-cli.cmd beside this file downloads and runs it:
#
#   curl -fsSL https://raw.githubusercontent.com/Replient/knwlge-releases/main/install-cli.cmd -o install-cli.cmd && install-cli.cmd && del install-cli.cmd
#
# The Windows counterpart of install-cli.sh, with the same rules. Releases live
# in Replient/knwlge-releases, which two products share, so this script never
# trusts GitHub's "latest" release: it lists the releases, picks the newest tag
# that starts with `cli-v`, downloads that release's `knwlge-<version>.tgz` plus
# `checksums.txt`, verifies the SHA-256, and installs the tarball with
# `npm install -g`. Set $env:KNWLGE_CLI_VERSION = '1.2.3' to install a specific
# version instead of the newest one.
#
# Set $env:KNWLGE_CLI_RELEASE_DIR to a folder that already holds
# `knwlge-<version>.tgz` and `checksums.txt` to install from it without
# downloading: a machine with no route to GitHub, or a build that is not
# released yet.
#
# Requirements: Windows PowerShell 5.1 or PowerShell 7, and Node.js 22 or newer
# on PATH (with npm).
#
# Keep this file ASCII: Windows PowerShell 5.1 reads a script without a
# byte-order mark in the machine's ANSI code page. It runs inside a script
# block and never calls `exit`, so piping it to `iex` neither closes the
# caller's window nor leaves variables or preferences behind in the session.

& {
  $ErrorActionPreference = 'Stop'
  # Windows PowerShell 5.1 draws a progress bar per download that slows it many times over.
  $ProgressPreference = 'SilentlyContinue'

  $releasesRepo = 'Replient/knwlge-releases'
  $releasesApi = "https://api.github.com/repos/$releasesRepo/releases?per_page=100"
  $downloadBase = "https://github.com/$releasesRepo/releases/download"
  $tagPrefix = 'cli-v'
  $minNodeMajor = 22
  $versionPattern = '^(\d+)\.(\d+)\.(\d+)(-[0-9A-Za-z.-]+)?$'
  $onWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

  $nodeInstallHint = @"
knwlge needs Node.js $minNodeMajor or newer on PATH (the persistent sidecar service pins the
exact Node executable it was installed with, so use a durable install, not a
temporary shell-only runtime):

  winget:      winget install OpenJS.NodeJS.LTS
  Chocolatey:  choco install nodejs-lts
  Installer:   https://nodejs.org/en/download

Open a new terminal afterwards, and re-run this script once node --version reports v$minNodeMajor or newer.
"@

  # Windows PowerShell 5.1 on an older .NET Framework still offers TLS 1.0 first; GitHub requires 1.2.
  try {
    [System.Net.ServicePointManager]::SecurityProtocol =
      [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
  } catch {
    # A runtime that manages this itself (PowerShell 7) needs nothing.
  }

  # --- Node.js and npm ---------------------------------------------------------

  $node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $node) {
    Write-Host $nodeInstallHint
    throw 'install-cli: Node.js was not found on PATH.'
  }
  $nodeVersion = (& $node.Path --version | Out-String).Trim()
  $nodeMajor = 0
  if ($nodeVersion -match '^v(\d+)\.') { $nodeMajor = [int]$Matches[1] }
  if ($nodeMajor -lt $minNodeMajor) {
    Write-Host $nodeInstallHint
    throw "install-cli: Node.js $minNodeMajor or newer is required; found $nodeVersion."
  }
  # npm.cmd by name: in PowerShell a bare `npm` is npm.ps1, which the default execution policy refuses to run.
  $npmName = 'npm'
  if ($onWindows) { $npmName = 'npm.cmd' }
  $npm = Get-Command $npmName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $npm) {
    throw "install-cli: $npmName is required but was not found on PATH (it ships with Node.js)."
  }

  # --- which version -----------------------------------------------------------

  $releaseDir = [string]$env:KNWLGE_CLI_RELEASE_DIR
  $version = [string]$env:KNWLGE_CLI_VERSION
  if ($releaseDir -ne '' -and -not (Test-Path -LiteralPath $releaseDir -PathType Container)) {
    throw "install-cli: KNWLGE_CLI_RELEASE_DIR is not a folder: $releaseDir"
  }
  if ($version -eq '' -and $releaseDir -ne '') {
    $found = @(Get-ChildItem -LiteralPath $releaseDir -Filter 'knwlge-*.tgz' -File |
        Where-Object { $_.Name -match '^knwlge-(\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?)\.tgz$' })
    if ($found.Count -ne 1) {
      throw "install-cli: $releaseDir holds $($found.Count) knwlge-<version>.tgz files; set KNWLGE_CLI_VERSION to choose one."
    }
    $version = $found[0].Name -replace '^knwlge-', '' -replace '\.tgz$', ''
  }
  if ($version -eq '') {
    # Newest `cli-v<version>` tag by SemVer order (a pre-release sorts below its final release). Only tag names are read
    # from the API response.
    $headers = @{
      'Accept'               = 'application/vnd.github+json'
      'X-GitHub-Api-Version' = '2022-11-28'
      'User-Agent'           = 'knwlge-install-cli'
    }
    try {
      $releases = Invoke-RestMethod -Uri $releasesApi -Headers $headers -UseBasicParsing
    } catch {
      throw "install-cli: the releases of $releasesRepo could not be listed: $($_.Exception.Message)"
    }
    $bestKey = ''
    foreach ($release in @($releases)) {
      $tag = [string]$release.tag_name
      if (-not $tag.StartsWith($tagPrefix)) { continue }
      $candidate = $tag.Substring($tagPrefix.Length)
      if ($candidate -notmatch $versionPattern) { continue }
      $final = 1
      if ($Matches.ContainsKey(4)) { $final = 0 }
      $key = '{0:D9}.{1:D9}.{2:D9}.{3}' -f [int]$Matches[1], [int]$Matches[2], [int]$Matches[3], $final
      if ([string]::CompareOrdinal($key, $bestKey) -gt 0) {
        $bestKey = $key
        $version = $candidate
      }
    }
    if ($version -eq '') {
      throw "install-cli: no $tagPrefix* release was found in $releasesRepo."
    }
  }
  if ($version -notmatch $versionPattern) {
    throw "install-cli: `"$version`" is not a version (expected something like 1.2.3)."
  }
  $tag = "$tagPrefix$version"
  $asset = "knwlge-$version.tgz"

  # --- download, verify, install -----------------------------------------------

  $workdir = Join-Path ([System.IO.Path]::GetTempPath()) ('knwlge-install-' + [System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $workdir | Out-Null
  try {
    $tarball = Join-Path $workdir $asset
    $checksums = Join-Path $workdir 'checksums.txt'
    if ($releaseDir -ne '') {
      Write-Host "Reading $asset from $releaseDir..."
      foreach ($name in @($asset, 'checksums.txt')) {
        $source = Join-Path $releaseDir $name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
          throw "install-cli: $releaseDir does not hold $name."
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path $workdir $name)
      }
    } else {
      Write-Host "Downloading $asset from $releasesRepo $tag..."
      try {
        Invoke-WebRequest -Uri "$downloadBase/$tag/$asset" -OutFile $tarball -UseBasicParsing
        Invoke-WebRequest -Uri "$downloadBase/$tag/checksums.txt" -OutFile $checksums -UseBasicParsing
      } catch {
        throw "install-cli: $tag could not be downloaded from ${releasesRepo}: $($_.Exception.Message)"
      }
    }

    $expected = ''
    foreach ($line in @(Get-Content -LiteralPath $checksums)) {
      $parts = @($line.Trim() -split '\s+')
      if ($parts.Count -ge 2 -and ($parts[1] -eq $asset -or $parts[1] -eq "*$asset")) {
        $expected = $parts[0].ToLowerInvariant()
        break
      }
    }
    if ($expected -eq '') {
      throw "install-cli: checksums.txt in $tag does not list $asset."
    }
    $actual = (Get-FileHash -LiteralPath $tarball -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($expected -ne $actual) {
      throw "install-cli: SHA-256 mismatch for ${asset}: expected $expected, got $actual."
    }

    Write-Host "Installing knwlge $version with npm..."
    & $npm.Path install -g --no-audit --no-fund $tarball
    if ($LASTEXITCODE -ne 0) {
      throw "install-cli: npm install -g did not finish (exit $LASTEXITCODE)."
    }
  } finally {
    Remove-Item -LiteralPath $workdir -Recurse -Force -ErrorAction SilentlyContinue
  }

  # --- check what was installed --------------------------------------------------

  # npm's global folder holds the launchers themselves on Windows, and a bin folder everywhere else.
  $prefix = (& $npm.Path prefix -g | Out-String).Trim()
  $binDir = Join-Path $prefix 'bin'
  $launcher = Join-Path $binDir 'knwlge'
  if ($onWindows) {
    $binDir = $prefix
    $launcher = Join-Path $binDir 'knwlge.cmd'
  }
  $installed = ''
  if (Test-Path -LiteralPath $launcher -PathType Leaf) {
    $installed = (& $launcher --version | Out-String).Trim()
  }
  if ($installed -ne $version) {
    throw "install-cli: knwlge $version was installed, but `"$launcher`" --version printed `"$installed`"."
  }

  $onPath = $false
  foreach ($entry in ([string]$env:PATH).Split([System.IO.Path]::PathSeparator)) {
    if ($entry.Trim().TrimEnd('\', '/') -ieq $binDir.TrimEnd('\', '/')) { $onPath = $true }
  }
  if (-not $onPath) {
    Write-Host ''
    Write-Host "knwlge was installed to $binDir, which is not on PATH."
    Write-Host 'Add that folder to your PATH (Settings > System > About > Advanced system settings > Environment Variables),'
    Write-Host 'then open a new terminal.'
  }

  if ($onWindows) {
    # What a new PowerShell window will enforce: the first scope that sets a policy, else the Windows default.
    $policy = 'Restricted'
    try {
      foreach ($scope in @('MachinePolicy', 'UserPolicy', 'CurrentUser', 'LocalMachine')) {
        $scoped = [string](Get-ExecutionPolicy -Scope $scope)
        if ($scoped -ne 'Undefined') {
          $policy = $scoped
          break
        }
      }
    } catch {
      $policy = ''
    }
    if ($policy -eq 'Restricted' -or $policy -eq 'AllSigned') {
      Write-Host ''
      Write-Host "PowerShell on this machine does not run unsigned scripts (execution policy: $policy), and npm installs a"
      Write-Host 'knwlge.ps1 launcher that PowerShell picks first. In PowerShell, either run knwlge.cmd instead of knwlge, or'
      Write-Host 'allow local scripts once:  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned'
      Write-Host 'Command Prompt and Git Bash are not affected.'
    }
  }

  Write-Host ''
  Write-Host "knwlge $version installed. Next: knwlge init --api-url https://your-enterprise-server"
}
