param(
  [Parameter(Mandatory = $true)]
  [string]$Subcommand,
  [string]$Arguments = '',
  [string]$VBoxManagePath = 'C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe'
)

. "$PSScriptRoot/Common.ps1"

$vboxManage = Get-VBoxManage -Path $VBoxManagePath

$argumentList = @()
if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
  foreach ($line in ($Arguments -split "`r?`n")) {
    $arg = $line.Trim()
    if (-not [string]::IsNullOrWhiteSpace($arg)) {
      $argumentList += $arg
    }
  }
}

Write-Host "Running VBoxManage $Subcommand"
if ($argumentList.Count -gt 0) {
  Write-Host 'Arguments:'
  $argumentList | ForEach-Object { Write-Host "  $_" }
}

& $vboxManage $Subcommand @argumentList
if ($LASTEXITCODE -ne 0) {
  throw "VBoxManage command '$Subcommand' failed with exit code $LASTEXITCODE."
}
