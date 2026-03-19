#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${SCRIPT_SOURCE:-./install.sh}"
ENV_SOURCE="${ENV_SOURCE:-}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/lib/bootstrap}"
RUNNER_PATH="${RUNNER_PATH:-/usr/local/sbin/run-bootstrap-install.sh}"
SERVICE_NAME="${SERVICE_NAME:-bootstrap-install}"
STATE_DIR="${STATE_DIR:-/var/lib/${SERVICE_NAME}}"
ENV_DEST="${ENV_DEST:-/etc/bootstrap/install.env}"
LOG_FILE="${LOG_FILE:-/var/log/${SERVICE_NAME}.log}"

usage() {
  cat <<'EOF'
Usage:
  sudo bash install_bootstrap_service.sh [--script /path/install.sh] [--env /path/bootstrap.env]

Options:
  --script PATH        Path to installer script (default: ./install.sh)
  --env PATH           Optional env file copied to /etc/bootstrap/install.env
  --install-dir PATH   Directory to install the bootstrap script into
  --runner PATH        Path to the helper runner script
  --service-name NAME  systemd service name without .service suffix
  --state-dir PATH     Directory used for bootstrap completion state
  --env-dest PATH      Destination path for the copied env file
  --log-file PATH      Log file written by the runner
  -h, --help           Show this help
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
    --install-dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --runner)
      RUNNER_PATH="$2"
      shift 2
      ;;
    --service-name)
      SERVICE_NAME="$2"
      shift 2
      ;;
    --state-dir)
      STATE_DIR="$2"
      shift 2
      ;;
    --env-dest)
      ENV_DEST="$2"
      shift 2
      ;;
    --log-file)
      LOG_FILE="$2"
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

if [[ -n "${ENV_SOURCE}" && ! -f "${ENV_SOURCE}" ]]; then
  echo "Env file not found: ${ENV_SOURCE}"
  exit 1
fi

INSTALLED_SCRIPT_PATH="${INSTALL_DIR}/$(basename "${SCRIPT_SOURCE}")"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
STATE_FILE="${STATE_DIR}/done"

install -d -m 0755 "${INSTALL_DIR}"
install -d -m 0755 "$(dirname "${RUNNER_PATH}")"
install -d -m 0755 "${STATE_DIR}"
install -d -m 0755 "$(dirname "${ENV_DEST}")"
install -d -m 0755 "$(dirname "${LOG_FILE}")"

install -m 0755 "${SCRIPT_SOURCE}" "${INSTALLED_SCRIPT_PATH}"

if [[ -n "${ENV_SOURCE}" ]]; then
  install -m 0600 "${ENV_SOURCE}" "${ENV_DEST}"
fi

cat >"${RUNNER_PATH}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${STATE_FILE}"
INSTALL_SCRIPT="${INSTALLED_SCRIPT_PATH}"
ENV_FILE="${ENV_DEST}"
LOG_FILE="${LOG_FILE}"

install -d -m 0755 "\$(dirname "\${LOG_FILE}")"
touch "\${LOG_FILE}"
chmod 0644 "\${LOG_FILE}"
exec > >(tee -a "\${LOG_FILE}") 2>&1
export PS4='+ \$(date -Is) \${BASH_SOURCE##*/}:\${LINENO}: '
set -x

if [[ -f "\${STATE_FILE}" ]]; then
  echo "Bootstrap already completed."
  exit 0
fi

if [[ -f "\${ENV_FILE}" ]]; then
  export SECRET_ENV_FILE="\${ENV_FILE}"
fi

bash "\${INSTALL_SCRIPT}"

touch "\${STATE_FILE}"
systemctl disable ${SERVICE_NAME}.service >/dev/null 2>&1 || true
EOF

chmod 0755 "${RUNNER_PATH}"

cat >"${SERVICE_PATH}" <<EOF
[Unit]
Description=Bootstrap installer on boot
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=${RUNNER_PATH}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service"

echo "Installed bootstrap service."
echo "Service: ${SERVICE_NAME}.service"
echo "Runner:  ${RUNNER_PATH}"
echo "Script:  ${INSTALLED_SCRIPT_PATH}"
if [[ -f "${ENV_DEST}" ]]; then
  echo "Env:     ${ENV_DEST}"
fi
