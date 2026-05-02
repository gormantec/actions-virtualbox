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

function Invoke-GuestControlCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Command
  )

  $previousEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $output = ''
  $exitCode = 1

  try {
    $output = (& $vboxManage guestcontrol $VmName run --username $BaseVmUser --password $BaseVmHostPassword --exe /usr/bin/sudo -- sudo -n bash -lc $Command 2>&1 | Out-String)
    $exitCode = $LASTEXITCODE
  } catch {
    $output = $_.Exception.Message
    if ($LASTEXITCODE -is [int]) {
      $exitCode = $LASTEXITCODE
    }
  } finally {
    $ErrorActionPreference = $previousEap
  }

  $trimmedOutput = $output.TrimEnd("`r", "`n")
  $guestExecutionServiceNotReady = $trimmedOutput -match 'guest execution service is not ready'

  return [pscustomobject]@{
    ExitCode = $exitCode
    Output = $trimmedOutput
    Succeeded = ($exitCode -eq 0)
    GuestExecutionServiceNotReady = $guestExecutionServiceNotReady
  }
}

function Test-GuestLogsPresent {
  $probeResult = Invoke-GuestControlCommand -Command $probeCommand
  return $probeResult.Succeeded
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
$endedDueToInactiveStaleLog = $false

for ($attempt = 1; $attempt -le $FollowAttempts; $attempt++) {
  Write-Host "Following /var/log/bootstrap-install.log (attempt $attempt/$FollowAttempts)..."

  $countCommand = 'if [ -f /var/log/bootstrap-install.log ]; then wc -l < /var/log/bootstrap-install.log; else echo 0; fi'
  $lineCountResult = Invoke-GuestControlCommand -Command $countCommand

  if ($lineCountResult.GuestExecutionServiceNotReady) {
    Write-Host 'Guest execution service is not ready yet. Retrying log follow on the next attempt.'
    Start-Sleep -Seconds $FollowSleepSeconds
    continue
  }

  if ($lineCountResult.Succeeded) {
    $lineCountMatch = [regex]::Match($lineCountResult.Output, '(?m)^\s*(\d+)\s*$')
    if ($lineCountMatch.Success) {
      $lineCount = [int]$lineCountMatch.Groups[1].Value
      if ($lineCount -ge $lastLine) {
        $chunkCommand = "sed -n '$lastLine,${lineCount}p' /var/log/bootstrap-install.log"
        $chunkResult = Invoke-GuestControlCommand -Command $chunkCommand
        if ($chunkResult.Succeeded) {
          if (-not [string]::IsNullOrWhiteSpace($chunkResult.Output)) {
            Write-Host $chunkResult.Output
          }
        } elseif (-not $chunkResult.GuestExecutionServiceNotReady) {
          Write-Warning 'Unable to read log chunk on this attempt.'
        }

        if ($chunkResult.Succeeded) {
          $lastLine = $lineCount + 1
          $staleCount = 0
        }
      } else {
        $staleCount++
      }
    } else {
      $staleCount++
    }
  } else {
    $staleCount++
  }

  $doneCommand = "if [ -f /var/log/bootstrap-install.log ] && grep -q 'All Done' /var/log/bootstrap-install.log; then echo done; fi"
  $doneResult = Invoke-GuestControlCommand -Command $doneCommand

  if ($doneResult.GuestExecutionServiceNotReady) {
    Write-Host 'Guest execution service became temporarily unavailable while checking completion. Retrying.'
    Start-Sleep -Seconds $FollowSleepSeconds
    continue
  }

  if ($doneResult.Succeeded -and $doneResult.Output -match 'done') {
    Write-Host "Detected completion marker 'All Done' in /var/log/bootstrap-install.log."
    $allDoneSeen = $true
    break
  }

  $configValidationErrorCommand = "if [ -f /var/log/bootstrap-install.log ] && grep -q 'Error: Config validation failed' /var/log/bootstrap-install.log; then echo config-validation-failed; fi"
  $configValidationResult = Invoke-GuestControlCommand -Command $configValidationErrorCommand

  if ($configValidationResult.GuestExecutionServiceNotReady) {
    Write-Host 'Guest execution service became temporarily unavailable while checking config validation. Retrying.'
    Start-Sleep -Seconds $FollowSleepSeconds
    continue
  }

  if ($configValidationResult.Succeeded -and $configValidationResult.Output -match 'config-validation-failed') {
    throw "Detected 'Error: Config validation failed' in /var/log/bootstrap-install.log."
  }

  if ($configValidationResult.Succeeded -and $configValidationResult.Output -match 'ConfigMutationConflictError') {
    throw "Detected 'Error: ConfigMutationConflictError occured' in /var/log/bootstrap-install.log."
  }

  

  if ($configValidationResult.Succeeded -and $configValidationResult.Output -match 'last exit 1') {
    throw "Detected 'Error: last exit 1' in /var/log/bootstrap-install.log."
  }


  if ($configValidationResult.Succeeded -and $configValidationResult.Output -match 'Could not get lock /var/lib/dpkg/lock-frontend') {
    throw "Detected 'Error: Could not get lock /var/lib/dpkg/lock-frontend' in /var/log/bootstrap-install.log."
  }


  if ($configValidationResult.Succeeded -and $configValidationResult.Output -match 'curl: (22) The requested URL returned error: 401') {
    throw "Detected 'Error: curl: (22) The requested URL returned error: 401' in /var/log/bootstrap-install.log."
  }

  if ($configValidationResult.Succeeded -and $configValidationResult.Output -match 'Error: Command failed at line') {
    throw "Detected 'Error: Command failed at line' in /var/log/bootstrap-install.log."
  }

  

  

  $failedCommand = 'if systemctl is-failed --quiet bootstrap.service; then echo failed; fi'
  $failedResult = Invoke-GuestControlCommand -Command $failedCommand

  if ($failedResult.GuestExecutionServiceNotReady) {
    Write-Host 'Guest execution service became temporarily unavailable while checking service status. Retrying.'
    Start-Sleep -Seconds $FollowSleepSeconds
    continue
  }

  if ($failedResult.Succeeded -and $failedResult.Output -match 'failed') {
    Write-Warning 'Detected failed state for bootstrap.service. Dumping service diagnostics...'
    $serviceDiag = "echo '=== systemctl status bootstrap.service ==='; systemctl --no-pager --full status bootstrap.service || true; echo ''; echo '=== journalctl -u bootstrap.service (last 120 lines) ==='; journalctl -u bootstrap.service --no-pager -n 120 || true"

    $serviceDiagResult = Invoke-GuestControlCommand -Command $serviceDiag
    if ($serviceDiagResult.Succeeded) {
      if (-not [string]::IsNullOrWhiteSpace($serviceDiagResult.Output)) {
        Write-Host $serviceDiagResult.Output
      }
    } elseif (-not $serviceDiagResult.GuestExecutionServiceNotReady) {
      Write-Warning 'Unable to fetch bootstrap service diagnostics.'
    }

    throw 'bootstrap.service entered failed state before completion.'
  }

  $serviceActiveCommand = 'systemctl is-active --quiet bootstrap.service && echo active || echo inactive'
  $serviceActiveResult = Invoke-GuestControlCommand -Command $serviceActiveCommand

  if ($serviceActiveResult.GuestExecutionServiceNotReady) {
    Write-Host 'Guest execution service became temporarily unavailable while checking whether bootstrap.service is still active. Retrying.'
    Start-Sleep -Seconds $FollowSleepSeconds
    continue
  }

  if ($staleCount -ge $MaxStale -and $serviceActiveResult.Succeeded -and $serviceActiveResult.Output -match 'inactive') {
    Write-Warning "Log file has not grown for $MaxStale attempts and bootstrap.service is inactive. Assuming completion."
    $endedDueToInactiveStaleLog = $true
    break
  }

  Start-Sleep -Seconds $FollowSleepSeconds
}

if (-not $allDoneSeen -and $endedDueToInactiveStaleLog) {
  Write-Warning "Did not detect 'All Done' marker, but exiting due to stale log and inactive service."
}

$finalDump = "echo '=== /var/log/unattended-postinstall.log ==='; if [ -f /var/log/unattended-postinstall.log ]; then tail -n 200 /var/log/unattended-postinstall.log; else echo 'missing'; fi; echo ''; echo '=== /var/log/vboxadd-setup.log ==='; if [ -f /var/log/vboxadd-setup.log ]; then tail -n 120 /var/log/vboxadd-setup.log; else echo 'missing'; fi; echo ''; echo '=== /var/log/vboxadd-install.log ==='; if [ -f /var/log/vboxadd-install.log ]; then tail -n 120 /var/log/vboxadd-install.log; else echo 'missing'; fi"
$finalDumpResult = Invoke-GuestControlCommand -Command $finalDump
if ($finalDumpResult.Succeeded) {
  if (-not [string]::IsNullOrWhiteSpace($finalDumpResult.Output)) {
    Write-Host $finalDumpResult.Output
  }
} elseif (-not $finalDumpResult.GuestExecutionServiceNotReady) {
  Write-Warning 'Best-effort final log dump failed.'
}