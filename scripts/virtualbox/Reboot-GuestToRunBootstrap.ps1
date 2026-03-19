param(
  [string]$VmName = 'new-vm',
  [string]$BaseVmUser = 'vmhost',
  [string]$BaseVmHostPassword,
  [string]$VBoxManagePath = 'C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe'
)

. "$PSScriptRoot/Common.ps1"

if ([string]::IsNullOrWhiteSpace($BaseVmHostPassword)) {
  throw 'Missing required secret BASE_VM_HOST_PASSWORD for guest reboot.'
}

$vboxManage = Get-VBoxManage -Path $VBoxManagePath

Write-Host 'Rebooting guest to trigger openclaw-bootstrap.service...'
# VBoxManage can emit VERR_NOT_FOUND when reboot kills the guestcontrol session.
# Treat that specific condition as expected, but fail on real reboot errors.
$previousEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$rebootOutput = @()
$rebootExitCode = 1
try {
  $rebootOutput = & $vboxManage guestcontrol $VmName run --username $BaseVmUser --password $BaseVmHostPassword --exe /usr/bin/sudo -- sudo -n systemctl reboot 2>&1
  $rebootExitCode = $LASTEXITCODE
} catch {
  $rebootOutput += $_.Exception.Message
  if ($LASTEXITCODE -is [int]) {
    $rebootExitCode = $LASTEXITCODE
  }
} finally {
  $ErrorActionPreference = $previousEap
}

$rebootText = ($rebootOutput | Out-String)
$expectedGuestSessionClose = ($rebootText -match 'VERR_NOT_FOUND' -or $rebootText -match 'Closing guest session')

if ($rebootExitCode -ne 0 -and -not $expectedGuestSessionClose) {
  throw "Failed to trigger guest reboot via VBoxManage (exit code $rebootExitCode). Output: $rebootText"
}

if ($expectedGuestSessionClose) {
  Write-Host 'Guest session closed during reboot (expected VBoxManage behavior).'
}

Write-Host 'Reboot command issued. Waiting for VM to go offline...'

$wentOffline = $false
for ($attempt = 1; $attempt -le 6; $attempt++) {
  $stateLine = & $vboxManage showvminfo $VmName --machinereadable | Select-String '^VMState='
  if (-not $stateLine -or -not $stateLine.ToString().Contains('running')) {
    Write-Host 'VM has gone offline.'
    $wentOffline = $true
    break
  }
  Write-Host "Waiting for VM to go offline (attempt $attempt/6)..."
  Start-Sleep -Seconds 5
}

if (-not $wentOffline) {
  Write-Warning "VM '$VmName' did not appear to go offline; continuing anyway."
}

$running = $false
for ($attempt = 1; $attempt -le 24; $attempt++) {
  $stateLine = & $vboxManage showvminfo $VmName --machinereadable | Select-String '^VMState='
  if ($stateLine -and $stateLine.ToString().Contains('running')) {
    Write-Host 'VM is running again.'
    $running = $true
    break
  }
  Write-Host "Waiting for VM to return to running state (attempt $attempt/24)..."
  Start-Sleep -Seconds 5
}

if (-not $running) {
  throw "VM '$VmName' did not return to a running state after reboot."
}

Wait-GuestControlReady `
  -VBoxManage $vboxManage `
  -VmName $VmName `
  -GuestUser $BaseVmUser `
  -GuestPassword $BaseVmHostPassword `
  -MaxAttempts 18 `
  -SleepSeconds 20 `
  -AttemptLabel 'Waiting for guest control after reboot' `
  -FailureMessage "Guest control did not become ready after rebooting '$VmName'."

Write-Host 'Guest is up and ready after reboot.'