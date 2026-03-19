# actions-virtualbox

Reusable GitHub Actions for managing VirtualBox VMs on self-hosted Windows runners.

## Usage

Reference each action by path and tag:

```yaml
uses: gormantec/actions-virtualbox/virtualbox-clone-vm@v1
```

GitHub Actions syntax is `owner/repo/path@ref` (not `owner/repo:/path`).

## Actions

### `virtualbox-clone-vm`

Clones a target VM from a base VM (optionally from a snapshot) and applies VM runtime settings.

Action:

```yaml
uses: gormantec/actions-virtualbox/virtualbox-clone-vm@v1
```

Mandatory inputs:

- `base_vm_name`: Name of the source/base VM.
- `vm_memory_mb`: VM memory in MB.
- `vm_cpus`: Number of vCPUs.
- `delete_existing_vm`: `true`/`false` to remove an existing target VM first.

Optional inputs:

- `base_snapshot_name` (default: `""`): Snapshot to clone from; empty uses current state.
- `vm_bridge_adapter` (default: `""`): Host bridge adapter name.
- `vm_mac_address` (default: `""`): Fixed NIC1 MAC; falls back to `VM_MAC_ADDRESS` env var if omitted.
- `vm_name` (default: `new-vm`): Target VM name.
- `vboxmanage_path` (default: `C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe`): Path to `VBoxManage.exe`.

Example:

```yaml
- name: Clone VM
	uses: gormantec/actions-virtualbox/virtualbox-clone-vm@v1
	with:
		base_vm_name: base-vm
		vm_memory_mb: "4096"
		vm_cpus: "2"
		delete_existing_vm: "true"
		base_snapshot_name: clean
```

### `virtualbox-start-vm`

Starts the target VM in headless mode.

Action:

```yaml
uses: gormantec/actions-virtualbox/virtualbox-start-vm@v1
```

Mandatory inputs:

- None.

Optional inputs:

- `vm_name` (default: `new-vm`): Target VM name.
- `vboxmanage_path` (default: `C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe`): Path to `VBoxManage.exe`.

Example:

```yaml
- name: Start VM
	uses: gormantec/actions-virtualbox/virtualbox-start-vm@v1
	with:
		vm_name: new-vm
```

### `virtualbox-ensure-new-user`

Ensures a target user exists inside the guest and applies related user/hostname configuration.

Action:

```yaml
uses: gormantec/actions-virtualbox/virtualbox-ensure-new-user@v1
```

Mandatory inputs:

- `base_vm_user`: Existing guest user used with `guestcontrol`.
- `vm_user`: User to create/configure.
- `base_vm_host_password`: Password for `base_vm_user`.
- `new_user_password`: Password to set for `vm_user`.

Optional inputs:

- `vm_name` (default: `new-vm`): Target VM name.
- `vboxmanage_path` (default: `C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe`): Path to `VBoxManage.exe`.

Example:

```yaml
- name: Ensure guest user
	uses: gormantec/actions-virtualbox/virtualbox-ensure-new-user@v1
	with:
		base_vm_user: admin
		vm_user: appuser
		base_vm_host_password: ${{ secrets.BASE_VM_HOST_PASSWORD }}
		new_user_password: ${{ secrets.NEW_USER_PASSWORD }}
```

### `virtualbox-configure-bootstrap`

Uploads bootstrap/install assets to the guest and configures runtime environment values.

Action:

```yaml
uses: gormantec/actions-virtualbox/virtualbox-configure-bootstrap@v1
```

Mandatory inputs:

- `base_vm_user`: Existing guest user used with `guestcontrol`.
- `vm_user`: New user used in generated env/config.
- `config_repo`: Repository containing install assets.
- `config_ref`: Git ref to fetch from `config_repo`.
- `base_vm_host_password`: Password for `base_vm_user`.
- `bootstrap_install_env_b64`: Base64-encoded env file payload.
- `github_token`: GitHub token for API-based downloads.
- `github_copilot_token`: GitHub Copilot token for bootstrap.
- `cloudflare_tunnel_token`: Cloudflare tunnel token for web access.

Optional inputs:

- `install_script_path` (default: `bootstrap_install.sh`): Path to the install script inside `config_repo`.
- `vm_name` (default: `new-vm`): Target VM name.
- `vboxmanage_path` (default: `C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe`): Path to `VBoxManage.exe`.

Example:

```yaml
- name: Configure bootstrap
	uses: gormantec/actions-virtualbox/virtualbox-configure-bootstrap@v1
	with:
		base_vm_user: admin
		vm_user: newuser
		config_repo: my-org/bootstrap-install
		config_ref: main
		base_vm_host_password: ${{ secrets.BASE_VM_HOST_PASSWORD }}
		bootstrap_install_env_b64: ${{ secrets.BOOTSTRAP_INSTALL_ENV_B64 }}
		github_token: ${{ secrets.GITHUB_TOKEN }}
		github_copilot_token: ${{ secrets.GITHUB_COPILOT_TOKEN }}
		cloudflare_tunnel_token: ${{ secrets.CLOUDFLARE_TUNNEL_TOKEN }}
		install_script_path: bootstrap_install.sh
```

### `virtualbox-reboot-guest`

Reboots the guest VM so bootstrap services/processes can start after provisioning.

Action:

```yaml
uses: gormantec/actions-virtualbox/virtualbox-reboot-guest@v1
```

Mandatory inputs:

- `base_vm_user`: Existing guest user used with `guestcontrol`.
- `base_vm_host_password`: Password for `base_vm_user`.

Optional inputs:

- `vm_name` (default: `new-vm`): Target VM name.
- `vboxmanage_path` (default: `C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe`): Path to `VBoxManage.exe`.

Example:

```yaml
- name: Reboot guest
	uses: gormantec/actions-virtualbox/virtualbox-reboot-guest@v1
	with:
		base_vm_user: admin
		base_vm_host_password: ${{ secrets.BASE_VM_HOST_PASSWORD }}
```

### `virtualbox-dump-bootstrap-logs`

Streams and dumps guest bootstrap logs until completion.

Action:

```yaml
uses: gormantec/actions-virtualbox/virtualbox-dump-bootstrap-logs@v1
```

Mandatory inputs:

- `base_vm_user`: Existing guest user used with `guestcontrol`.
- `base_vm_host_password`: Password for `base_vm_user`.

Optional inputs:

- `vm_name` (default: `new-vm`): Target VM name.
- `vboxmanage_path` (default: `C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe`): Path to `VBoxManage.exe`.

Example:

```yaml
- name: Dump bootstrap logs
	uses: gormantec/actions-virtualbox/virtualbox-dump-bootstrap-logs@v1
	with:
		base_vm_user: admin
		base_vm_host_password: ${{ secrets.BASE_VM_HOST_PASSWORD }}
```

## Generic VBoxManage command actions

In addition to workflow-focused actions above, this repository now includes one generic action per top-level `VBoxManage` command. Each action accepts:

- `arguments` (optional): Newline-separated arguments passed to the command.
- `vboxmanage_path` (optional): Path to `VBoxManage.exe`.

Example (`showvminfo` variants grouped into one action):

```yaml
- name: Show VM info (machine-readable)
	uses: gormantec/actions-virtualbox/virtualbox-showvminfo@v1
	with:
		arguments: |
			my-vm
			--machinereadable

- name: Show VM log index 0
	uses: gormantec/actions-virtualbox/virtualbox-showvminfo@v1
	with:
		arguments: |
			my-vm
			--log=0
```

Basic examples:

```yaml
- name: List all VMs
	uses: gormantec/actions-virtualbox/virtualbox-list@v1
	with:
		arguments: |
			vms

- name: Start VM headless
	uses: gormantec/actions-virtualbox/virtualbox-startvm@v1
	with:
		arguments: |
			my-vm
			--type=headless

- name: Graceful shutdown via ACPI
	uses: gormantec/actions-virtualbox/virtualbox-controlvm@v1
	with:
		arguments: |
			my-vm
			acpipowerbutton

- name: Run command in guest
	uses: gormantec/actions-virtualbox/virtualbox-guestcontrol@v1
	with:
		arguments: |
			my-vm
			run
			--username=vmhost
			--password=${{ secrets.BASE_VM_HOST_PASSWORD }}
			--exe=/bin/echo
			--
			hello-from-guest
```

Available generic command actions:

- `gormantec/actions-virtualbox/virtualbox-list@v1`
- `gormantec/actions-virtualbox/virtualbox-showvminfo@v1`
- `gormantec/actions-virtualbox/virtualbox-registervm@v1`
- `gormantec/actions-virtualbox/virtualbox-unregistervm@v1`
- `gormantec/actions-virtualbox/virtualbox-createvm@v1`
- `gormantec/actions-virtualbox/virtualbox-modifyvm@v1`
- `gormantec/actions-virtualbox/virtualbox-snapshot@v1`
- `gormantec/actions-virtualbox/virtualbox-clonevm@v1`
- `gormantec/actions-virtualbox/virtualbox-movevm@v1`
- `gormantec/actions-virtualbox/virtualbox-encryptvm@v1`
- `gormantec/actions-virtualbox/virtualbox-startvm@v1`
- `gormantec/actions-virtualbox/virtualbox-controlvm@v1`
- `gormantec/actions-virtualbox/virtualbox-import@v1`
- `gormantec/actions-virtualbox/virtualbox-export@v1`
- `gormantec/actions-virtualbox/virtualbox-mediumio@v1`
- `gormantec/actions-virtualbox/virtualbox-sharedfolder@v1`
- `gormantec/actions-virtualbox/virtualbox-dhcpserver@v1`
- `gormantec/actions-virtualbox/virtualbox-debugvm@v1`
- `gormantec/actions-virtualbox/virtualbox-extpack@v1`
- `gormantec/actions-virtualbox/virtualbox-unattended@v1`
- `gormantec/actions-virtualbox/virtualbox-cloud@v1`
- `gormantec/actions-virtualbox/virtualbox-cloudprofile@v1`
- `gormantec/actions-virtualbox/virtualbox-signova@v1`
- `gormantec/actions-virtualbox/virtualbox-modifynvram@v1`
- `gormantec/actions-virtualbox/virtualbox-hostonlynet@v1`
- `gormantec/actions-virtualbox/virtualbox-updatecheck@v1`
- `gormantec/actions-virtualbox/virtualbox-discardstate@v1`
- `gormantec/actions-virtualbox/virtualbox-adoptstate@v1`
- `gormantec/actions-virtualbox/virtualbox-closemedium@v1`
- `gormantec/actions-virtualbox/virtualbox-storageattach@v1`
- `gormantec/actions-virtualbox/virtualbox-storagectl@v1`
- `gormantec/actions-virtualbox/virtualbox-bandwidthctl@v1`
- `gormantec/actions-virtualbox/virtualbox-showmediuminfo@v1`
- `gormantec/actions-virtualbox/virtualbox-createmedium@v1`
- `gormantec/actions-virtualbox/virtualbox-modifymedium@v1`
- `gormantec/actions-virtualbox/virtualbox-clonemedium@v1`
- `gormantec/actions-virtualbox/virtualbox-mediumproperty@v1`
- `gormantec/actions-virtualbox/virtualbox-encryptmedium@v1`
- `gormantec/actions-virtualbox/virtualbox-checkmediumpwd@v1`
- `gormantec/actions-virtualbox/virtualbox-convertfromraw@v1`
- `gormantec/actions-virtualbox/virtualbox-setextradata@v1`
- `gormantec/actions-virtualbox/virtualbox-getextradata@v1`
- `gormantec/actions-virtualbox/virtualbox-setproperty@v1`
- `gormantec/actions-virtualbox/virtualbox-usbfilter@v1`
- `gormantec/actions-virtualbox/virtualbox-guestproperty@v1`
- `gormantec/actions-virtualbox/virtualbox-guestcontrol@v1`
- `gormantec/actions-virtualbox/virtualbox-metrics@v1`
- `gormantec/actions-virtualbox/virtualbox-natnetwork@v1`
- `gormantec/actions-virtualbox/virtualbox-hostonlyif@v1`
- `gormantec/actions-virtualbox/virtualbox-usbdevsource@v1`
- `gormantec/actions-virtualbox/virtualbox-objtracker@v1`

## Requirements

- Self-hosted Windows runner with VirtualBox installed.
- `VBoxManage.exe` available (default path used by all actions):
	`C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe`

## Notes

- All actions keep your current input names and behavior to make migration simple.
- Most actions expose optional inputs with defaults so consumers only pass what they need.
- Shared PowerShell scripts live in `scripts/virtualbox` and are invoked relative to each action path.
- The guest bootstrap service helper lives in `scripts/linux/install_bootstrap_service.sh` and is fetched by `virtualbox-configure-bootstrap` from this repository.

## License

- This repository is licensed under the MIT License. See `LICENSE`.
- Third-party dependency and trademark notice for VirtualBox usage is documented in `NOTICE`.
