#!/usr/bin/env bash
set -euo pipefail

# Installs bootstrap_install_script.sh into /usr/local and configures
# a systemd service that executes it at boot until it succeeds once.

SCRIPT_SOURCE="${SCRIPT_SOURCE:-./bootstrap_install_script.sh}"
ENV_SOURCE="${ENV_SOURCE:-}"
INSTALL_DIR="/usr/local/lib/openclaw"
RUNNER_PATH="/usr/local/sbin/run-openclaw-bootstrap.sh"
SERVICE_PATH="/etc/systemd/system/openclaw-bootstrap.service"
STATE_DIR="/var/lib/openclaw-bootstrap"
ENV_DEST="/etc/openclaw/openclaw-install.env"

usage() {
  cat <<'EOF'
Usage:
  sudo bash scripts/install_bootstrap_on_vm.sh [--script /path/bootstrap_install_script.sh] [--env /path/openclaw-install.env]

Options:
  --script PATH   Path to bootstrap_install_script.sh (default: ./bootstrap_install_script.sh)
  --env PATH      Optional env file copied to /etc/openclaw/openclaw-install.env
  -h, --help      Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --script)
      SCRIPT_SOURCE="$2"
      shift 2
      ;;
    --env)
      ENV_SOURCE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "This script must be run as root."
  exit 1
fi

if [[ ! -f "${SCRIPT_SOURCE}" ]]; then
  echo "Installer script not found: ${SCRIPT_SOURCE}"
  exit 1
fi

install -d -m 0755 "${INSTALL_DIR}"
install -d -m 0755 /etc/openclaw
install -d -m 0755 "${STATE_DIR}"

install -m 0755 "${SCRIPT_SOURCE}" "${INSTALL_DIR}/bootstrap_install_script.sh"

if [[ -n "${ENV_SOURCE}" ]]; then
  if [[ ! -f "${ENV_SOURCE}" ]]; then
    echo "Env file not found: ${ENV_SOURCE}"
    exit 1
  fi

  install -m 0600 "${ENV_SOURCE}" "${ENV_DEST}"
fi

cat >"${RUNNER_PATH}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="/var/lib/openclaw-bootstrap/done"
INSTALL_SCRIPT="/usr/local/lib/openclaw/bootstrap_install_script.sh"
ENV_FILE="/etc/openclaw/openclaw-install.env"
LOG_FILE="/var/log/openclaw-bootstrap.log"

install -d -m 0755 /var/log
touch "${LOG_FILE}"
chmod 0644 "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1
export PS4='+ $(date -Is) ${BASH_SOURCE##*/}:${LINENO}: '
set -x

if [[ -f "${STATE_FILE}" ]]; then
  echo "Bootstrap already completed."
  exit 0
fi

if [[ -f "${ENV_FILE}" ]]; then
  export SECRET_ENV_FILE="${ENV_FILE}"
fi

bash "${INSTALL_SCRIPT}"

touch "${STATE_FILE}"
systemctl disable openclaw-bootstrap.service >/dev/null 2>&1 || true
EOF

chmod 0755 "${RUNNER_PATH}"

cat >"${SERVICE_PATH}" <<'EOF'
[Unit]
Description=OpenClaw bootstrap installer on boot
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/run-openclaw-bootstrap.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable openclaw-bootstrap.service

echo "Installed OpenClaw boot bootstrap service."
echo "Service: openclaw-bootstrap.service"
echo "Runner:  ${RUNNER_PATH}"
echo "Script:  ${INSTALL_DIR}/bootstrap_install_script.sh"
if [[ -f "${ENV_DEST}" ]]; then
  echo "Env:     ${ENV_DEST}"
fi