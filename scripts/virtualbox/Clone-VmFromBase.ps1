param(
  [string]$VmName = 'openclaw-vm',
  [string]$BaseVmName = 'ubuntu-24-04',
  [string]$BaseSnapshotName = 'clean-base-ubuntu',
  [string]$VmMemoryMb = '4096',
  [string]$VmCpus = '2',
  [string]$VmBridgeAdapter = '',
  [string]$VmMacAddress = '',
  [string]$DeleteExistingVm = 'true',
  [string]$VBoxManagePath = 'C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe'
)

. "$PSScriptRoot/Common.ps1"

$vboxManage = Get-VBoxManage -Path $VBoxManagePath
$deleteExisting = [System.Convert]::ToBoolean($DeleteExistingVm)
$vmBaseDir = "$env:USERPROFILE\VirtualBox VMs"
$memoryMB = [int]$VmMemoryMb
$cpus = [int]$VmCpus

$vmList = & $vboxManage list vms
Write-Host "=== Registered VMs ==="
$vmList | ForEach-Object { Write-Host "  $_" }
Write-Host "=== Looking for base VM: '$BaseVmName' ==="
$escapedBase = [regex]::Escape($BaseVmName)
$basePattern = '^"{0}"\s' -f $escapedBase
if (-not ($vmList | Where-Object { $_ -match $basePattern })) {
  throw "Base VM '$BaseVmName' not found."
}

if (-not [string]::IsNullOrWhiteSpace($BaseSnapshotName)) {
  $snapList = & $vboxManage snapshot $BaseVmName list --machinereadable 2>&1
  $escapedSnap = [regex]::Escape($BaseSnapshotName)
  if (-not ($snapList | Where-Object { $_ -match "SnapshotName.*=.*`"$escapedSnap`"" })) {
    throw "Snapshot '$BaseSnapshotName' not found on base VM '$BaseVmName'."
  }
}

$escapedVmName = [regex]::Escape($VmName)
$vmNamePattern = '^"{0}"\s' -f $escapedVmName
$existing = $vmList | Where-Object { $_ -match $vmNamePattern }
if ($existing) {
  if ($deleteExisting) {
    Write-Host "VM '$VmName' exists. Deleting (delete_existing_vm=true)."
    $stateLine = (& $vboxManage showvminfo $VmName --machinereadable | Select-String '^VMState=')
    if ($stateLine -and $stateLine.ToString().Contains('running')) {
      Write-Host "Stopping running VM '$VmName'..."
      & $vboxManage controlvm $VmName poweroff
      Start-Sleep -Seconds 5
    }
    & $vboxManage unregistervm $VmName --delete
    Write-Host "Deleted VM '$VmName'."
    Start-Sleep -Seconds 3
  } else {
    Write-Host "VM '$VmName' exists and delete_existing_vm=false. Skipping clone."
    & $vboxManage showvminfo $VmName --machinereadable
    exit 0
  }
}

if (-not [string]::IsNullOrWhiteSpace($BaseSnapshotName)) {
  Write-Host "Cloning '$BaseVmName' snapshot '$BaseSnapshotName' -> '$VmName'..."
  & $vboxManage clonevm $BaseVmName `
    --snapshot $BaseSnapshotName `
    --name $VmName `
    --basefolder $vmBaseDir `
    --register
} else {
  Write-Host "Cloning '$BaseVmName' current state -> '$VmName'..."
  & $vboxManage clonevm $BaseVmName `
    --name $VmName `
    --basefolder $vmBaseDir `
    --register
}

& $vboxManage modifyvm $VmName --memory $memoryMB --cpus $cpus

$bridgeAdapter = $VmBridgeAdapter.Trim()
if ([string]::IsNullOrWhiteSpace($bridgeAdapter)) {
  $bridgeAdapter = (& $vboxManage list bridgedifs | Select-String '^Name:' | Select-Object -First 1).ToString().Split(':', 2)[1].Trim()
  if ([string]::IsNullOrWhiteSpace($bridgeAdapter)) {
    throw "No bridged adapter detected. Set vm_bridge_adapter input to a valid adapter name."
  }
}

Write-Host "Setting bridged adapter: $bridgeAdapter"
& $vboxManage modifyvm $VmName --nic1 bridged --bridgeadapter1 "$bridgeAdapter" --cableconnected1 on

$vmMacAddress = $VmMacAddress.Trim()
if (-not [string]::IsNullOrWhiteSpace($vmMacAddress)) {
  $normalizedMac = $vmMacAddress -replace '[:\-\.]', ''
  if ($normalizedMac -notmatch '^[0-9A-Fa-f]{12}$') {
    throw "Invalid vm_mac_address '$vmMacAddress'. Use exactly 12 hex characters, for example 080027A1B2C3."
  }

  $normalizedMac = $normalizedMac.ToUpperInvariant()
  Write-Host "Applying fixed NIC1 MAC address: $normalizedMac"
  & $vboxManage modifyvm $VmName --macaddress1 $normalizedMac
}

Write-Host "VM '$VmName' cloned and ready to boot."
& $vboxManage showvminfo $VmName --machinereadable