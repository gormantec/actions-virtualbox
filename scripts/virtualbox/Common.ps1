$ErrorActionPreference = 'Stop'
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
  $PSNativeCommandUseErrorActionPreference = $false
}

function Get-VBoxManage {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "VBoxManage not found at: $Path"
  }

  Write-Host "Validated VBoxManage path."
  return $Path
}

function Test-GuestControlReady {
  param(
    [Parameter(Mandatory = $true)]
    [string]$VBoxManage,
    [Parameter(Mandatory = $true)]
    [string]$VmName,
    [Parameter(Mandatory = $true)]
    [string]$GuestUser,
    [Parameter(Mandatory = $true)]
    [string]$GuestPassword
  )

  $previousEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $exitCode = 1
  try {
    & $VBoxManage guestcontrol $VmName run --username $GuestUser --password $GuestPassword --exe /usr/bin/env -- env bash -lc "echo guestcontrol-ready" 2>$null | Out-Null
    $exitCode = $LASTEXITCODE
  } catch {
    $exitCode = 1
  } finally {
    $ErrorActionPreference = $previousEap
  }

  return ($exitCode -eq 0)
}

function Wait-GuestControlReady {
  param(
    [Parameter(Mandatory = $true)]
    [string]$VBoxManage,
    [Parameter(Mandatory = $true)]
    [string]$VmName,
    [Parameter(Mandatory = $true)]
    [string]$GuestUser,
    [Parameter(Mandatory = $true)]
    [string]$GuestPassword,
    [int]$MaxAttempts = 18,
    [int]$SleepSeconds = 20,
    [string]$AttemptLabel = 'Waiting for guestcontrol',
    [string]$RetryLabel = 'Waiting for guestcontrol after reset',
    [string]$FailureMessage = 'Guest control never became ready.',
    [switch]$ResetOnFailure,
    [switch]$LogGuestAdditions
  )

  $lastGaState = ''

  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    Write-Host "$AttemptLabel (attempt $attempt/$MaxAttempts)..."

    if ($LogGuestAdditions) {
      $gaInfo = (& $VBoxManage showvminfo $VmName --machinereadable | Select-String '^GuestAdditionsRunLevel=|^GuestAdditionsVersion=' | ForEach-Object { $_.ToString().Trim() })
      $gaState = ($gaInfo -join '; ')
      if (-not [string]::IsNullOrWhiteSpace($gaState) -and $gaState -ne $lastGaState) {
        Write-Host "Guest Additions state: $gaState"
        $lastGaState = $gaState
      }
    }

    if (Test-GuestControlReady -VBoxManage $VBoxManage -VmName $VmName -GuestUser $GuestUser -GuestPassword $GuestPassword) {
      return $true
    }

    Start-Sleep -Seconds $SleepSeconds
  }

  if (-not $ResetOnFailure) {
    Write-Warning $FailureMessage
    return $false
  }

  Write-Warning "Guest control not ready yet. Resetting VM once and retrying."
  & $VBoxManage controlvm $VmName reset
  Start-Sleep -Seconds 30

  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    Write-Host "$RetryLabel (attempt $attempt/$MaxAttempts)..."

    if ($LogGuestAdditions) {
      $gaInfo = (& $VBoxManage showvminfo $VmName --machinereadable | Select-String '^GuestAdditionsRunLevel=|^GuestAdditionsVersion=' | ForEach-Object { $_.ToString().Trim() })
      $gaState = ($gaInfo -join '; ')
      if (-not [string]::IsNullOrWhiteSpace($gaState) -and $gaState -ne $lastGaState) {
        Write-Host "Guest Additions state: $gaState"
        $lastGaState = $gaState
      }
    }

    if (Test-GuestControlReady -VBoxManage $VBoxManage -VmName $VmName -GuestUser $GuestUser -GuestPassword $GuestPassword) {
      return $true
    }

    Start-Sleep -Seconds $SleepSeconds
  }

  Write-Warning $FailureMessage
  return $false
}

function Stop-Action {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message,
    [int]$ExitCode = 1
  )

  Write-Host "::error::$Message"
  exit $ExitCode
}

function Invoke-GuestRootBash {
  param(
    [Parameter(Mandatory = $true)]
    [string]$VBoxManage,
    [Parameter(Mandatory = $true)]
    [string]$VmName,
    [Parameter(Mandatory = $true)]
    [string]$GuestUser,
    [Parameter(Mandatory = $true)]
    [string]$GuestPassword,
    [Parameter(Mandatory = $true)]
    [string]$Command,
    [switch]$AllowFailure
  )

  & $VBoxManage guestcontrol $VmName run --username $GuestUser --password $GuestPassword --exe /usr/bin/sudo -- sudo -n bash -lc $Command
  $exitCode = $LASTEXITCODE
  if (-not $AllowFailure -and $exitCode -ne 0) {
    throw "Guest command failed (exit code $exitCode): $Command"
  }

  return $exitCode
}