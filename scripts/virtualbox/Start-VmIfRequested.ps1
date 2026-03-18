param(
  [string]$VmName = 'openclaw-vm',
  [string]$VBoxManagePath = 'C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe'
)

. "$PSScriptRoot/Common.ps1"

$vboxManage = Get-VBoxManage -Path $VBoxManagePath
$stateLine = (& $vboxManage showvminfo $VmName --machinereadable | Select-String '^VMState=')
if ($stateLine -and $stateLine.ToString().Contains('running')) {
  Write-Host "VM '$VmName' is already running."
  exit 0
}

& $vboxManage startvm $VmName --type headless
Write-Host "Started VM '$VmName' (headless)."
Write-Host 'Waiting 30 seconds for boot...'
Start-Sleep -Seconds 30