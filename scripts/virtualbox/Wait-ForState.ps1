param(
  [Parameter(Mandatory = $true)]
  [string]$VmName,
  [Parameter(Mandatory = $true)]
  [string]$AllowedStates,
  [string]$VBoxManagePath = 'C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe',
  [int]$TimeoutSeconds = 300,
  [int]$PollIntervalSeconds = 5,
  [bool]$FailOnTimeout = $true
)

. "$PSScriptRoot/Common.ps1"

$vboxManage = Get-VBoxManage -Path $VBoxManagePath

$allowedStateList = @()
foreach ($line in ($AllowedStates -split "`r?`n")) {
  $state = $line.Trim()
  if (-not [string]::IsNullOrWhiteSpace($state)) {
    $allowedStateList += $state
  }
}

if ($allowedStateList.Count -eq 0) {
  throw 'At least one allowed VM state must be provided.'
}

if ($TimeoutSeconds -lt 0) {
  throw 'timeout_seconds must be 0 or greater.'
}

if ($PollIntervalSeconds -lt 1) {
  throw 'poll_interval_seconds must be at least 1.'
}

function Get-VMState {
  param(
    [Parameter(Mandatory = $true)]
    [string]$VBoxManage,
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $output = & $VBoxManage showvminfo $Name --machinereadable
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to get VM state for '$Name'."
  }

  foreach ($line in $output) {
    if ($line -match '^VMState="([^"]+)"$') {
      return $Matches[1]
    }
  }

  throw "VMState not found for '$Name'."
}

$deadline = if ($TimeoutSeconds -eq 0) { $null } else { (Get-Date).AddSeconds($TimeoutSeconds) }
$lastState = ''

while ($true) {
  $currentState = Get-VMState -VBoxManage $vboxManage -Name $VmName
  if ($currentState -ne $lastState) {
    Write-Host "Current VM state: $currentState"
    $lastState = $currentState
  }

  if ($allowedStateList -contains $currentState) {
    Write-Host "Reached allowed state '$currentState'."
    if ($env:GITHUB_OUTPUT) {
      "final_state=$currentState" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
      'reached_state=true' | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
    }
    exit 0
  }

  if ($null -ne $deadline -and (Get-Date) -ge $deadline) {
    $message = "Timed out waiting for '$VmName' to reach one of: $($allowedStateList -join ', '). Last state: $currentState"
    if ($env:GITHUB_OUTPUT) {
      "final_state=$currentState" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
      'reached_state=false' | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
    }

    if ($FailOnTimeout) {
      throw $message
    }

    Write-Warning $message
    exit 0
  }

  Start-Sleep -Seconds $PollIntervalSeconds
}