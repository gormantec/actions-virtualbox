# actions-virtualbox

Reusable GitHub Actions for managing VirtualBox VMs on self-hosted Windows runners.

## Usage

Reference each action by path and tag:

```yaml
uses: gormantec/actions-virtualbox/virtualbox-clone-vm@v1
```

GitHub Actions syntax is `owner/repo/path@ref` (not `owner/repo:/path`).

## Available actions

- `gormantec/actions-virtualbox/virtualbox-clone-vm@v1`
- `gormantec/actions-virtualbox/virtualbox-start-vm@v1`
- `gormantec/actions-virtualbox/virtualbox-ensure-openclaw-user@v1`
- `gormantec/actions-virtualbox/virtualbox-configure-bootstrap@v1`
- `gormantec/actions-virtualbox/virtualbox-reboot-guest@v1`
- `gormantec/actions-virtualbox/virtualbox-dump-bootstrap-logs@v1`

## Requirements

- Self-hosted Windows runner with VirtualBox installed.
- `VBoxManage.exe` available (default path used by all actions):
	`C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe`

## Notes

- All actions keep your current input names and behavior to make migration simple.
- Most actions expose optional inputs with defaults so consumers only pass what they need.
- Shared PowerShell scripts live in `scripts/virtualbox` and are invoked relative to each action path.
