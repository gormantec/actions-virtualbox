param(
  [string]$VmName = 'openclaw-vm',
  [string]$BaseVmUser = 'vmhost',
  [string]$OpenClawUser = 'openclaw',
  [string]$ConfigRepo = '',
  [string]$ConfigRef = 'main',
  [string]$BaseVmHostPassword,
  [string]$OpenClawInstallEnvB64,
  [string]$GitHubToken,
  [string]$GitHubCopilotToken,
  [string]$CloudflareTunnelToken,
  [string]$VBoxManagePath = 'C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe'
)

. "$PSScriptRoot/Common.ps1"

if ([string]::IsNullOrWhiteSpace($BaseVmHostPassword)) {
  throw 'Missing required secret BASE_VM_HOST_PASSWORD for guest bootstrap.'
}
if ([string]::IsNullOrWhiteSpace($GitHubToken)) {
  throw 'Missing GitHub token. Use runner github.token or set secret ENV_GITHUB_TOKEN.'
}
if ([string]::IsNullOrWhiteSpace($ConfigRepo)) {
  $ConfigRepo = $env:GITHUB_REPOSITORY
}
if ([string]::IsNullOrWhiteSpace($ConfigRepo) -or $ConfigRepo -notmatch '^[^/]+/[^/]+$') {
  throw "config_repo must be in owner/repo format. Provide config_repo input or set GITHUB_REPOSITORY (current: '$ConfigRepo')."
}
if ([string]::IsNullOrWhiteSpace($ConfigRef)) {
  throw 'config_ref cannot be empty.'
}
if ([string]::IsNullOrWhiteSpace($OpenClawInstallEnvB64)) {
  throw 'Missing required secret OPENCLAW_INSTALL_ENV_B64 for guest bootstrap.'
}

Write-Host "Using config repository: $ConfigRepo"

$vboxManage = Get-VBoxManage -Path $VBoxManagePath

Wait-GuestControlReady -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -MaxAttempts 36 -SleepSeconds 20 -AttemptLabel 'Waiting for guestcontrol' -RetryLabel 'Waiting for guestcontrol after reset' -FailureMessage 'Guest control never became ready after reset. Check VBox logs and guest boot logs.' -ResetOnFailure -LogGuestAdditions

$repoApi = "https://api.github.com/repos/$ConfigRepo/contents"
$curlAuth = "-u 'x-access-token:$GitHubToken' -H 'Accept: application/vnd.github.raw'"
$installScriptUrl = "$repoApi/install_openclaw_private.sh?ref=$ConfigRef"
$bootstrapScriptUrl = "$repoApi/scripts/install_bootstrap_on_vm.sh?ref=$ConfigRef"

Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command 'set -euo pipefail; mkdir -p /var/log; touch /var/log/openclaw-unattended-postinstall.log; chmod 644 /var/log/openclaw-unattended-postinstall.log'
Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command "set -euo pipefail; curl -fsSL $curlAuth '$installScriptUrl' -o /root/install_openclaw_private.sh"
Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command "set -euo pipefail; curl -fsSL $curlAuth '$bootstrapScriptUrl' -o /root/install_bootstrap_on_vm.sh"

Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command "set -euo pipefail; printf '%s' '$OpenClawInstallEnvB64' | base64 -d > /root/openclaw-install.env"
Write-Host 'Wrote env file from OPENCLAW_INSTALL_ENV_B64'
# Append the Token on a new line (Fix: use $GitHubToken and add \n)
Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command "set -euo pipefail; printf '\nGITHUB_TOKEN=%s' '$GitHubCopilotToken' >> /root/openclaw-install.env"
Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command "set -euo pipefail; printf '\nCLOUDFLARE_TUNNEL_TOKEN=%s' '$CloudflareTunnelToken' >> /root/openclaw-install.env"
Write-Host 'Appended to env file'

Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command "set -euo pipefail; if grep -q '^TARGET_USER=' /root/openclaw-install.env; then sed -i 's/^TARGET_USER=.*/TARGET_USER=$OpenClawUser/' /root/openclaw-install.env; else printf '\nTARGET_USER=$OpenClawUser\n' >> /root/openclaw-install.env; fi"
Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command 'set -euo pipefail; chmod +x /root/install_openclaw_private.sh /root/install_bootstrap_on_vm.sh'
Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command 'set -euo pipefail; bash /root/install_bootstrap_on_vm.sh --script /root/install_openclaw_private.sh --env /root/openclaw-install.env'