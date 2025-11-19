#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=devcontainer-general/flags.sh
source "$SCRIPT_DIR/flags.sh"
load_devcontainer_flags "$SCRIPT_DIR"

if flag_enabled DEVCONTAINER_RUN_FIREWALL 0; then
  echo "[post-start] Applying egress firewall rules"
  sudo --preserve-env=DEVCONTAINER_FLAG_FILE,DEVCONTAINER_FIREWALL_DOMAINS_FILE,DEVCONTAINER_FIREWALL_EXTRA_DOMAINS,DEVCONTAINER_FIREWALL_CHAIN,DEVCONTAINER_FIREWALL_IPSET,DEVCONTAINER_FIREWALL_ALLOW_HOST_LAN \
    bash "$SCRIPT_DIR/init_firewall.sh"
else
  echo "[post-start] Skipping firewall setup"
fi
