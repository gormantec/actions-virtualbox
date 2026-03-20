param(
  [string]$VmName = 'new-vm',
  [string]$BaseVmUser = 'vmhost',
  [string]$VmUser = 'vmuser',
  [string]$ConfigRepo = '',
  [string]$ConfigRef = 'main',
  [string]$BootstrapRepo = '',
  [string]$BootstrapRef = '',
  [string]$InstallScriptPath = 'install_bootstrap.sh',
  [string]$BaseVmHostPassword,
  [string]$BootstrapInstallEnvB64,
  [string]$GitHubToken,
  [string]$GitHubCopilotToken,
  [string]$GeminiToken,
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
$bootstrapRepoSource = 'input'
if ([string]::IsNullOrWhiteSpace($BootstrapRepo)) {
  $BootstrapRepo = $env:GITHUB_ACTION_REPOSITORY
  $bootstrapRepoSource = 'env:GITHUB_ACTION_REPOSITORY'
}
if ([string]::IsNullOrWhiteSpace($BootstrapRepo)) {
  $BootstrapRepo = 'gormantec/actions-virtualbox'
  $bootstrapRepoSource = 'hardcoded fallback'
}
if ($BootstrapRepo -eq 'gormantec/actions-vitualbox') {
  Write-Warning "Detected typo in bootstrap_repo '$BootstrapRepo'. Using 'gormantec/actions-virtualbox' instead."
  $BootstrapRepo = 'gormantec/actions-virtualbox'
  $bootstrapRepoSource = 'hardcoded fallback (typo corrected)'
}
if ($BootstrapRepo -notmatch '^[^/]+/[^/]+$') {
  throw "bootstrap_repo must be in owner/repo format. Resolved value '$BootstrapRepo' from $bootstrapRepoSource is invalid."
}

$bootstrapRefSource = 'input'
if ([string]::IsNullOrWhiteSpace($BootstrapRef)) {
  $BootstrapRef = $env:GITHUB_ACTION_REF
  $bootstrapRefSource = 'env:GITHUB_ACTION_REF'
}
if ([string]::IsNullOrWhiteSpace($BootstrapRef)) {
  $BootstrapRef = 'main'
  $bootstrapRefSource = 'hardcoded fallback'
}
if ([string]::IsNullOrWhiteSpace($InstallScriptPath)) {
  throw 'install_script_path cannot be empty.'
}
if ([string]::IsNullOrWhiteSpace($BootstrapInstallEnvB64)) {
  throw 'Missing required secret BOOTSTRAP_INSTALL_ENV_B64 for guest bootstrap.'
}

Write-Host "Using config repository: $ConfigRepo"
Write-Host "Using bootstrap helper repository: $BootstrapRepo@$BootstrapRef (repo source: $bootstrapRepoSource, ref source: $bootstrapRefSource)"

$vboxManage = Get-VBoxManage -Path $VBoxManagePath

Wait-GuestControlReady -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -MaxAttempts 36 -SleepSeconds 20 -AttemptLabel 'Waiting for guestcontrol' -RetryLabel 'Waiting for guestcontrol after reset' -FailureMessage 'Guest control never became ready after reset. Check VBox logs and guest boot logs.' -ResetOnFailure -LogGuestAdditions

$repoApi = "https://api.github.com/repos/$ConfigRepo/contents"
$bootstrapRepoApi = "https://api.github.com/repos/$BootstrapRepo/contents"
$curlAuth = "-u 'x-access-token:$GitHubToken' -H 'Accept: application/vnd.github.raw'"
$installScriptPathNormalized = ($InstallScriptPath -replace '\\', '/').Trim().Trim('/')
if ([string]::IsNullOrWhiteSpace($installScriptPathNormalized)) {
  throw "install_script_path resolved to empty after normalization (raw value: '$InstallScriptPath')."
}
if ($installScriptPathNormalized.Contains('?')) {
  throw "install_script_path must not include query parameters. Provide only a file path inside config_repo (received: '$InstallScriptPath')."
}
$installScriptFileName = Split-Path -Path $installScriptPathNormalized -Leaf
if ([string]::IsNullOrWhiteSpace($installScriptFileName)) {
  throw "install_script_path '$InstallScriptPath' does not contain a valid file name."
}

$installScriptPathEncoded = (($installScriptPathNormalized -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
$bootstrapHelperPathEncoded = 'scripts/linux/install_bootstrap_service.sh'
$configRefEncoded = [uri]::EscapeDataString($ConfigRef)
$bootstrapRefEncoded = [uri]::EscapeDataString($BootstrapRef)

$installScriptGuestPath = "/root/$installScriptFileName"
$installScriptUrl = '{0}/{1}?ref={2}' -f $repoApi, $installScriptPathEncoded, $configRefEncoded
$bootstrapScriptGuestPath = '/root/install_bootstrap_service.sh'
$bootstrapScriptUrl = '{0}/{1}?ref={2}' -f $bootstrapRepoApi, $bootstrapHelperPathEncoded, $bootstrapRefEncoded

Write-Host "Resolved install script: $ConfigRepo/$installScriptPathNormalized@$ConfigRef"
Write-Host "Resolved bootstrap helper script: $BootstrapRepo/scripts/linux/install_bootstrap_service.sh@$BootstrapRef"
Write-Host "Install script URL: $installScriptUrl"
Write-Host "Bootstrap helper URL: $bootstrapScriptUrl"

Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command 'set -euo pipefail; mkdir -p /var/log; touch /var/log/unattended-postinstall.log; chmod 644 /var/log/unattended-postinstall.log'
Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command "set -euo pipefail; curl -fsSL $curlAuth '$installScriptUrl' -o $installScriptGuestPath"
Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command "set -euo pipefail; curl -fsSL $curlAuth '$bootstrapScriptUrl' -o $bootstrapScriptGuestPath"

Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command "set -euo pipefail; printf '%s' '$BootstrapInstallEnvB64' | base64 -d > /root/bootstrap-install.env"
Write-Host 'Wrote env file from BOOTSTRAP_INSTALL_ENV_B64'
# Append the Token on a new line (Fix: use $GitHubToken and add \n)
Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command "set -euo pipefail; printf '\nGITHUB_TOKEN=%s' '$GitHubToken' >> /root/bootstrap-install.env"
Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command "set -euo pipefail; printf '\nGITHUB_COPILOT_TOKEN=%s' '$GitHubCopilotToken' >> /root/bootstrap-install.env"
Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command "set -euo pipefail; printf '\nGEMINI_TOKEN=%s' '$GeminiToken' >> /root/bootstrap-install.env"
Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command "set -euo pipefail; printf '\nCLOUDFLARE_TUNNEL_TOKEN=%s' '$CloudflareTunnelToken' >> /root/bootstrap-install.env"
Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command "set -euo pipefail; printf '\nCONFIG_REPO=%s' '$ConfigRepo' >> /root/bootstrap-install.env"
Write-Host 'Appended to env file'

Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command "set -euo pipefail; if grep -q '^TARGET_USER=' /root/bootstrap-install.env; then sed -i 's/^TARGET_USER=.*/TARGET_USER=$VmUser/' /root/bootstrap-install.env; else printf '\nTARGET_USER=$VmUser\n' >> /root/bootstrap-install.env; fi"
Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command "set -euo pipefail; chmod +x $installScriptGuestPath $bootstrapScriptGuestPath"
Invoke-GuestRootBash -VBoxManage $vboxManage -VmName $VmName -GuestUser $BaseVmUser -GuestPassword $BaseVmHostPassword -Command "set -euo pipefail; bash $bootstrapScriptGuestPath --script $installScriptGuestPath --env /root/bootstrap-install.env"
