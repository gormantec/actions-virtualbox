param(
  [string]$VmName = 'new-vm',
  [string]$GuestUser,
  [string]$GuestPassword,
  [string]$Script,
  [string]$EnvironmentVariables = '',
  [string]$VBoxManagePath = 'C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe',
  [int]$TimeoutMs = 600000,
  [bool]$WaitForGuestControl = $true,
  [int]$GuestControlAttempts = 18,
  [int]$GuestControlSleepSeconds = 20,
  [bool]$ResetOnGuestControlFailure = $false,
  [bool]$LogGuestAdditions = $false,
  [bool]$AllowFailure = $false,
  [bool]$WaitStdout = $true,
  [bool]$WaitStderr = $true
)

. "$PSScriptRoot/Common.ps1"

if ([string]::IsNullOrWhiteSpace($GuestUser)) {
  throw 'guest_user is required.'
}
if ([string]::IsNullOrWhiteSpace($GuestPassword)) {
  throw 'guest_password is required.'
}
if ([string]::IsNullOrWhiteSpace($Script)) {
  throw 'script is required.'
}
if ($TimeoutMs -lt 1) {
  throw 'timeout_ms must be at least 1.'
}
if ($GuestControlAttempts -lt 1) {
  throw 'guestcontrol_attempts must be at least 1.'
}
if ($GuestControlSleepSeconds -lt 1) {
  throw 'guestcontrol_sleep_seconds must be at least 1.'
}

$vboxManage = Get-VBoxManage -Path $VBoxManagePath

$environmentPreamble = @()
foreach ($line in ($EnvironmentVariables -split "`r?`n")) {
  $trimmedLine = $line.Trim()
  if ([string]::IsNullOrWhiteSpace($trimmedLine)) {
    continue
  }

  $parts = $trimmedLine -split '=', 2
  if ($parts.Count -ne 2) {
    throw "Invalid environment variable entry '$trimmedLine'. Expected KEY=VALUE."
  }

  $name = $parts[0].Trim()
  $value = $parts[1]
  if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
    throw "Invalid environment variable name '$name'."
  }

  $escapedValue = $value.Replace("'", "'\''")
  $environmentPreamble += "export $name='$escapedValue'"
}

$command = if ($environmentPreamble.Count -gt 0) {
  ([string]::Join("`n", $environmentPreamble) + "`n" + $Script)
} else {
  $Script
}

if ($WaitForGuestControl) {
  $guestReady = Wait-GuestControlReady -VBoxManage $vboxManage -VmName $VmName -GuestUser $GuestUser -GuestPassword $GuestPassword -MaxAttempts $GuestControlAttempts -SleepSeconds $GuestControlSleepSeconds -AttemptLabel 'Waiting for guestcontrol before guest bash' -RetryLabel 'Waiting for guestcontrol after reset before guest bash' -FailureMessage 'Guest control never became ready before running guest bash.' -ResetOnFailure:$ResetOnGuestControlFailure -LogGuestAdditions:$LogGuestAdditions
  if (-not $guestReady) {
    Stop-Action -Message 'Guest control never became ready before running guest bash. Please check VBox logs and guest boot logs for more details.'
  }
}

$exitCode = Invoke-GuestBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $GuestUser -GuestPassword $GuestPassword -Command $command -TimeoutMs $TimeoutMs -AllowFailure:$AllowFailure -WaitStdout:$WaitStdout -WaitStderr:$WaitStderr

if ($env:GITHUB_OUTPUT) {
  "exit_code=$exitCode" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
}