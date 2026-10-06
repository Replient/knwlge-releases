$ErrorActionPreference = 'Stop'

$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$tarball = Join-Path $toolsDir 'knwlge-1.0.3.tgz'
$packageDir = Join-Path $toolsDir 'package'

if (Test-Path -LiteralPath $packageDir) {
  Remove-Item -LiteralPath $packageDir -Recurse -Force
}

Get-ChocolateyWebFile -PackageName $env:ChocolateyPackageName `
  -FileFullPath $tarball `
  -Url 'https://github.com/Replient/knwlge-releases/releases/download/cli-v1.0.3/knwlge-1.0.3.tgz' `
  -Checksum '421102b86bb0efa1db6ca3461f82d9583e550f6af5af17443e49993d89e650a9' `
  -ChecksumType 'sha256'

# The release is a gzipped tar that holds every runtime dependency: the first pass yields the tar, the second its files.
Get-ChocolateyUnzip -FileFullPath $tarball -Destination $toolsDir
$tar = Get-ChildItem -LiteralPath $toolsDir -Filter '*.tar' | Select-Object -First 1
if (-not $tar) {
  throw 'The knwlge release did not unpack to a tar archive.'
}
Get-ChocolateyUnzip -FileFullPath $tar.FullName -Destination $toolsDir
Remove-Item -LiteralPath $tarball, $tar.FullName -Force

if (-not (Test-Path -LiteralPath (Join-Path $packageDir 'dist\index.js') -PathType Leaf)) {
  throw 'The knwlge release did not unpack to package\dist\index.js.'
}

Install-BinFile -Name 'knwlge' -Path (Join-Path $toolsDir 'knwlge.cmd')
