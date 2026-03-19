param(
  [string]$VmName = 'new-vm',
  [string]$BaseVmUser = 'vmhost',
  [string]$NewUser = 'newuser',
  [string]$BaseVmHostPassword,
  [string]$NewUserPassword,
  [string]$VBoxManagePath = 'C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe'
)

. "$PSScriptRoot/Common.ps1"

if ([string]::IsNullOrWhiteSpace($BaseVmHostPassword)) {
  throw 'Missing required secret BASE_VM_HOST_PASSWORD.'
}
if ([string]::IsNullOrWhiteSpace($NewUserPassword)) {
  throw 'Missing required secret NEW_USER_PASSWORD (used as the new user''s password).'

}

$vboxManage = Get-VBoxManage -Path $VBoxManagePath

Wait-GuestControlReady -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -MaxAttempts 18 -SleepSeconds 20 -AttemptLabel 'Waiting for guestcontrol before user setup' -RetryLabel 'Waiting for guestcontrol after reset' -FailureMessage 'Guest control never became ready before new user setup. Check VBox logs and guest boot logs.' -ResetOnFailure

$createUserParts = @(
  "id -u $NewUser >/dev/null 2>&1 || useradd -m -s /bin/bash $NewUser",
  "echo '${NewUser}:${NewUserPassword}' | chpasswd",
  "usermod -aG sudo $NewUser",
  "echo '$NewUser ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/$NewUser-nopasswd",
  "chmod 440 /etc/sudoers.d/$NewUser-nopasswd"
)
$createUserCmd = [string]::Join('; ', $createUserParts)

Write-Host "Ensuring user '$NewUser' exists with sudo..."
& $vboxManage guestcontrol $VmName run --username $BaseVmUser --password $BaseVmHostPassword --exe /usr/bin/sudo -- sudo -n bash -c $createUserCmd
if ($LASTEXITCODE -ne 0) {
  throw "Failed to create/configure user '$NewUser' on guest (exit code $LASTEXITCODE)."
}

$targetHostname = $VmName.ToLowerInvariant() -replace '[^a-z0-9-]', '-'
$targetHostname = $targetHostname.Trim('-')
if ([string]::IsNullOrWhiteSpace($targetHostname)) {
  throw "vm_name '$VmName' cannot be converted to a valid guest hostname. Use letters, numbers, or hyphens."
}
if ($targetHostname.Length -gt 63) {
  $targetHostname = $targetHostname.Substring(0, 63).Trim('-')
}
if ([string]::IsNullOrWhiteSpace($targetHostname)) {
  throw "vm_name '$VmName' produced an empty hostname after normalization."
}
$targetDomain = 'local'
$targetFqdn = "$targetHostname.$targetDomain"
$setHostnameParts = @(
  'set -euo pipefail',
  "hostnamectl set-hostname $targetFqdn",
  'mkdir -p /etc/cloud/cloud.cfg.d',
  "printf 'preserve_hostname: true\n' > /etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg",
  "if grep -q '^127\\.0\\.1\\.1\\s' /etc/hosts; then sed -i -E 's/^127\\.0\\.1\\.1\\s+.*/127.0.1.1 $targetFqdn $targetHostname/' /etc/hosts; else printf '127.0.1.1 $targetFqdn $targetHostname\n' >> /etc/hosts; fi",
  'hostnamectl status --static || true',
  "echo 'Configured hostname/domain: $targetHostname / $targetDomain ($targetFqdn)'"
)
$setHostnameCmd = [string]::Join('; ', $setHostnameParts)

Write-Host "Setting guest hostname/domain to '$targetHostname' and '$targetDomain'..."
& $vboxManage guestcontrol $VmName run --username $BaseVmUser --password $BaseVmHostPassword --exe /usr/bin/sudo -- sudo -n bash -lc $setHostnameCmd
if ($LASTEXITCODE -ne 0) {
  throw "Failed to configure guest hostname/domain (exit code $LASTEXITCODE)."
}