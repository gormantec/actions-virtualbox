param(
  [string]$PreferredVBoxManagePath = 'C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe',
  [string]$FallbackVBoxManagePath = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe',
  [string]$ChocoPackageName = 'virtualbox',
  [string]$InstallArguments = '-y --no-progress'
)

$ErrorActionPreference = 'Stop'
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
  $PSNativeCommandUseErrorActionPreference = $false
}

function Resolve-VBoxManagePath {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$CandidatePaths
  )

  foreach ($candidate in $CandidatePaths) {
    if ([string]::IsNullOrWhiteSpace($candidate)) {
      continue
    }

    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  return $null
}

$resolvedPath = Resolve-VBoxManagePath -CandidatePaths @($PreferredVBoxManagePath, $FallbackVBoxManagePath)
$wasInstalled = $false

if ($null -eq $resolvedPath) {
  Write-Host 'VBoxManage.exe not found. Installing VirtualBox with Chocolatey...'

  $choco = Get-Command choco -ErrorAction SilentlyContinue
  if ($null -eq $choco) {
    throw 'Chocolatey is not installed or not on PATH, so VirtualBox cannot be installed automatically.'
  }

  $installArgumentList = @('install', $ChocoPackageName)
  foreach ($token in ($InstallArguments -split '\s+')) {
    if (-not [string]::IsNullOrWhiteSpace($token)) {
      $installArgumentList += $token
    }
  }

  & $choco.Source @installArgumentList
  if ($LASTEXITCODE -ne 0) {
    throw "Chocolatey failed to install package '$ChocoPackageName' (exit code $LASTEXITCODE)."
  }

  $resolvedPath = Resolve-VBoxManagePath -CandidatePaths @($PreferredVBoxManagePath, $FallbackVBoxManagePath)
  if ($null -eq $resolvedPath) {
    throw 'VirtualBox installation completed, but VBoxManage.exe was not found at the expected locations.'
  }

  $wasInstalled = $true
}

Write-Host "Using VBoxManage.exe at: $resolvedPath"
if ($env:GITHUB_OUTPUT) {
  "vboxmanage_path=$resolvedPath" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
  "was_installed=$($wasInstalled.ToString().ToLowerInvariant())" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
}