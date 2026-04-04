param(
  [string]$VmName = 'new-vm',
  [string]$BaseVmUser = 'vmhost',
  [string]$BaseVmHostPassword,
  [string]$VBoxManagePath = 'C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe',
  [int]$FollowAttempts = 100,
  [int]$FollowSleepSeconds = 20,
  [int]$MaxStale = 5
)

. "$PSScriptRoot/Common.ps1"

if ([string]::IsNullOrWhiteSpace($BaseVmHostPassword)) {
  throw 'Missing required secret BASE_VM_HOST_PASSWORD for guest log retrieval.'
}

$vboxManage = Get-VBoxManage -Path $VBoxManagePath

$probeCommand = 'test -f /var/log/unattended-postinstall.log || test -f /var/log/bootstrap-install.log'
$maxAttempts = 30
$sleepSeconds = 10

$logsReady = $false

$guestReady = Wait-GuestControlReady -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -MaxAttempts $maxAttempts -SleepSeconds $sleepSeconds -AttemptLabel 'Waiting for guestcontrol after reboot' -FailureMessage 'Guest control did not become ready after reboot.'
if (-not $guestReady) {
  Stop-Action -Message 'Guest control did not become ready after reboot. Please check VBox logs and guest boot logs for more details.'
}

function Test-GuestLogsPresent {
  $previousEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $exitCode = 1
  try {
    & $vboxManage guestcontrol $VmName run --username $BaseVmUser --password $BaseVmHostPassword --exe /usr/bin/sudo -- sudo -n bash -lc $probeCommand 2>$null | Out-Null
    $exitCode = $LASTEXITCODE
  } catch {
    $exitCode = 1
  } finally {
    $ErrorActionPreference = $previousEap
  }
  return ($exitCode -eq 0)
}

for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
  Write-Host "Waiting for log files (attempt $attempt/$maxAttempts)..."
  if (Test-GuestLogsPresent) {
    $logsReady = $true
    break
  }
  Start-Sleep -Seconds $sleepSeconds
}

if (-not $logsReady) {
  Write-Warning 'Log files not detected yet. Trying best-effort fetch anyway.'
}


$lastLine = 1
$allDoneSeen = $false
$staleCount = 0
$lastLineCount = 0

for ($attempt = 1; $attempt -le $FollowAttempts; $attempt++) {
  Write-Host "Following /var/log/bootstrap-install.log (attempt $attempt/$FollowAttempts)..."

  $countCommand = 'if [ -f /var/log/bootstrap-install.log ]; then wc -l < /var/log/bootstrap-install.log; else echo 0; fi'
  $previousEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $lineCountRaw = ''
  $lineCountExit = 1
  try {
    $lineCountRaw = (& $vboxManage guestcontrol $VmName run --username $BaseVmUser --password $BaseVmHostPassword --exe /usr/bin/sudo -- sudo -n bash -lc $countCommand 2>$null | Out-String)
    $lineCountExit = $LASTEXITCODE
  } catch {
    $lineCountExit = 1
  } finally {
    $ErrorActionPreference = $previousEap
  }

  if ($lineCountExit -eq 0) {
    $lineCountMatch = [regex]::Match($lineCountRaw, '(?m)^\s*(\d+)\s*$')
    if ($lineCountMatch.Success) {
      $lineCount = [int]$lineCountMatch.Groups[1].Value
      if ($lineCount -ge $lastLine) {
        $chunkCommand = "sed -n '$lastLine,${lineCount}p' /var/log/bootstrap-install.log"
        $previousEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
          & $vboxManage guestcontrol $VmName run --username $BaseVmUser --password $BaseVmHostPassword --exe /usr/bin/sudo -- sudo -n bash -lc $chunkCommand
        } catch {
          Write-Warning 'Unable to read log chunk on this attempt.'
        } finally {
          $ErrorActionPreference = $previousEap
        }
        $lastLine = $lineCount + 1
        $staleCount = 0
      } else {
        $staleCount++
      }
      $lastLineCount = $lineCount
    } else {
      $staleCount++
    }
  } else {
    $staleCount++
  }

  $doneCommand = "if [ -f /var/log/bootstrap-install.log ] && grep -q 'All Done' /var/log/bootstrap-install.log; then echo done; fi"
  $previousEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $doneRaw = ''
  $doneExit = 1
  try {
    $doneRaw = (& $vboxManage guestcontrol $VmName run --username $BaseVmUser --password $BaseVmHostPassword --exe /usr/bin/sudo -- sudo -n bash -lc $doneCommand 2>$null | Out-String)
    $doneExit = $LASTEXITCODE
  } catch {
    $doneExit = 1
  } finally {
    $ErrorActionPreference = $previousEap
  }

  if ($doneExit -eq 0 -and $doneRaw -match 'done') {
    Write-Host "Detected completion marker 'All Done' in /var/log/bootstrap-install.log."
    $allDoneSeen = $true
    break
  }

  $configValidationErrorCommand = "if [ -f /var/log/bootstrap-install.log ] && grep -q 'Error: Config validation failed' /var/log/bootstrap-install.log; then echo config-validation-failed; fi"
  $previousEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $configValidationErrorRaw = ''
  $configValidationErrorExit = 1
  try {
    $configValidationErrorRaw = (& $vboxManage guestcontrol $VmName run --username $BaseVmUser --password $BaseVmHostPassword --exe /usr/bin/sudo -- sudo -n bash -lc $configValidationErrorCommand 2>$null | Out-String)
    $configValidationErrorExit = $LASTEXITCODE
  } catch {
    $configValidationErrorExit = 1
  } finally {
    $ErrorActionPreference = $previousEap
  }

  if ($configValidationErrorExit -eq 0 -and $configValidationErrorRaw -match 'config-validation-failed') {
    throw "Detected 'Error: Config validation failed' in /var/log/bootstrap-install.log."
  }

  $failedCommand = 'if systemctl is-failed --quiet bootstrap.service; then echo failed; fi'
  $previousEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $failedRaw = ''
  $failedExit = 1
  try {
    $failedRaw = (& $vboxManage guestcontrol $VmName run --username $BaseVmUser --password $BaseVmHostPassword --exe /usr/bin/sudo -- sudo -n bash -lc $failedCommand 2>$null | Out-String)
    $failedExit = $LASTEXITCODE
  } catch {
    $failedExit = 1
  } finally {
    $ErrorActionPreference = $previousEap
  }

  if ($failedExit -eq 0 -and $failedRaw -match 'failed') {
    Write-Warning 'Detected failed state for bootstrap.service. Dumping service diagnostics...'
    $serviceDiag = "echo '=== systemctl status bootstrap.service ==='; systemctl --no-pager --full status bootstrap.service || true; echo ''; echo '=== journalctl -u bootstrap.service (last 120 lines) ==='; journalctl -u bootstrap.service --no-pager -n 120 || true"
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      & $vboxManage guestcontrol $VmName run --username $BaseVmUser --password $BaseVmHostPassword --exe /usr/bin/sudo -- sudo -n bash -lc $serviceDiag
    } catch {
      Write-Warning 'Unable to fetch bootstrap service diagnostics.'
    } finally {
      $ErrorActionPreference = $previousEap
    }

    throw 'bootstrap.service entered failed state before completion.'
  }

  # New: Check if service is inactive and log is stale
  $serviceActiveCommand = 'systemctl is-active --quiet bootstrap.service && echo active || echo inactive'
  $serviceActiveRaw = (& $vboxManage guestcontrol $VmName run --username $BaseVmUser --password $BaseVmHostPassword --exe /usr/bin/sudo -- sudo -n bash -lc $serviceActiveCommand 2>$null | Out-String)
  if ($staleCount -ge $MaxStale -and $serviceActiveRaw -match 'inactive') {
    Write-Warning "Log file has not grown for $MaxStale attempts and bootstrap.service is inactive. Assuming completion."
    break
  }

  Start-Sleep -Seconds $FollowSleepSeconds
}

if (-not $allDoneSeen) {
  Write-Warning "Did not detect 'All Done' marker, but exiting due to stale log and inactive service."
}

$finalDump = "echo '=== /var/log/unattended-postinstall.log ==='; if [ -f /var/log/unattended-postinstall.log ]; then tail -n 200 /var/log/unattended-postinstall.log; else echo 'missing'; fi; echo ''; echo '=== /var/log/vboxadd-setup.log ==='; if [ -f /var/log/vboxadd-setup.log ]; then tail -n 120 /var/log/vboxadd-setup.log; else echo 'missing'; fi; echo ''; echo '=== /var/log/vboxadd-install.log ==='; if [ -f /var/log/vboxadd-install.log ]; then tail -n 120 /var/log/vboxadd-install.log; else echo 'missing'; fi"
$previousEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
  & $vboxManage guestcontrol $VmName run --username $BaseVmUser --password $BaseVmHostPassword --exe /usr/bin/sudo -- sudo -n bash -lc $finalDump
} catch {
  Write-Warning 'Best-effort final log dump failed.'
} finally {
  $ErrorActionPreference = $previousEap
}