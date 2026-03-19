param(
  [string]$VmName = 'new-vm',
  [string]$BaseVmUser = 'vmhost',
  [string]$BaseVmHostPassword,
  [string]$VBoxManagePath = 'C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe'
)

. "$PSScriptRoot/Common.ps1"

if ([string]::IsNullOrWhiteSpace($BaseVmHostPassword)) {
  throw 'Missing required secret BASE_VM_HOST_PASSWORD for guest log retrieval.'
}

$vboxManage = Get-VBoxManage -Path $VBoxManagePath

$probeCommand = 'test -f /var/log/unattended-postinstall.log || test -f /var/log/bootstrap.log'
$maxAttempts = 30
$sleepSeconds = 10
$logsReady = $false

Wait-GuestControlReady -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -MaxAttempts $maxAttempts -SleepSeconds $sleepSeconds -AttemptLabel 'Waiting for guestcontrol after reboot' -FailureMessage 'Guest control did not become ready after reboot.'

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
$followAttempts = 200
$followSleepSeconds = 20
$allDoneSeen = $false

for ($attempt = 1; $attempt -le $followAttempts; $attempt++) {
  Write-Host "Following /var/log/bootstrap.log (attempt $attempt/$followAttempts)..."

  $countCommand = 'if [ -f /var/log/bootstrap.log ]; then wc -l < /var/log/bootstrap.log; else echo 0; fi'
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
        $chunkCommand = "sed -n '$lastLine,${lineCount}p' /var/log/bootstrap.log"
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
      }
    }
  }

  $doneCommand = "if [ -f /var/log/bootstrap.log ] && grep -q 'All Done' /var/log/bootstrap.log; then echo done; fi"
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
    Write-Host "Detected completion marker 'All Done' in /var/log/bootstrap.log."
    $allDoneSeen = $true
    break
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

  Start-Sleep -Seconds $followSleepSeconds
}

if (-not $allDoneSeen) {
  throw "Timed out waiting for 'All Done' in /var/log/bootstrap.log."
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