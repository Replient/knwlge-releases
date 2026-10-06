$ErrorActionPreference = 'Stop'

$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

Uninstall-BinFile -Name 'knwlge' -Path (Join-Path $toolsDir 'knwlge.cmd')
