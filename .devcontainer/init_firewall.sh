#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

if [[ $EUID -ne 0 ]]; then
  echo "[firewall] Must run as root" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
# shellcheck source=devcontainer-general/flags.sh
source "$SCRIPT_DIR/flags.sh"
load_devcontainer_flags "$SCRIPT_DIR"

CHAIN=$(flag_value DEVCONTAINER_FIREWALL_CHAIN DEVCONTAINER_EGRESS)
IPSET=$(flag_value DEVCONTAINER_FIREWALL_IPSET devcontainer-allowed)
DOMAINS_FILE=$(flag_value DEVCONTAINER_FIREWALL_DOMAINS_FILE "")
EXTRA_DOMAINS=$(flag_value DEVCONTAINER_FIREWALL_EXTRA_DOMAINS "")
ALLOW_HOST_LAN=$(flag_value DEVCONTAINER_FIREWALL_ALLOW_HOST_LAN 1)

require_cmd() {
  local binary=$1
  if ! command -v "$binary" >/dev/null 2>&1; then
    echo "[firewall] $binary required" >&2
    exit 1
  fi
}

require_cmd ipset
require_cmd iptables
require_cmd dig
require_cmd jq
require_cmd curl

ipset create "$IPSET" hash:net -exist
ipset flush "$IPSET"

add_cidr() {
  local cidr=$1
  if [[ -n "$cidr" ]]; then
    ipset add -! "$IPSET" "$cidr"
  fi
}

resolve_and_allow() {
  local domain=$1
  if [[ -z "$domain" ]]; then
    return
  fi
  echo "[firewall] Resolving $domain"
  local ips
  ips=$(dig +short A "$domain" | grep -E '^[0-9]+(\.[0-9]+){3}$' | sort -u || true)
  if [[ -z "$ips" ]]; then
    echo "[firewall] WARN: Failed to resolve $domain" >&2
    return
  fi
  while read -r ip; do
    add_cidr "$ip"
  done <<<"$ips"
}

if gh_json=$(curl -fsS https://api.github.com/meta); then
  echo "$gh_json" \
    | jq -r '(.web + .api + .git)[]' \
    | while read -r cidr; do
        add_cidr "$cidr"
      done
else
  echo "[firewall] WARN: Unable to fetch GitHub meta" >&2
fi

CORE_DOMAINS=(
  pypi.org
  files.pythonhosted.org
  github.com
  api.github.com
  registry.npmjs.org
)

for domain in "${CORE_DOMAINS[@]}"; do
  resolve_and_allow "$domain"
done

parse_domains_file() {
  local file_path=$1
  if [[ -z "$file_path" ]]; then
    return
  fi
  if [[ "$file_path" != /* ]]; then
    file_path="$REPO_ROOT/$file_path"
  fi
  if [[ ! -f "$file_path" ]]; then
    echo "[firewall] Domains file $file_path not found; skipping" >&2
    return
  fi
  case "$file_path" in
    *.csv|*.CSV)
      mapfile -t csv_domains < <(python3 - "$file_path" <<'PY'
import csv
from urllib.parse import urlparse
import sys
csv_path = sys.argv[1]
seen = set()
with open(csv_path, newline="") as fh:
    reader = csv.DictReader(fh)
    for row in reader:
        for key in ("Careers Page", "url", "URL"):
            url = (row.get(key) or "").strip()
            if not url:
                continue
            host = urlparse(url).netloc.lower()
            if host and host not in seen:
                seen.add(host)
                print(host)
PY
)
      for domain in "${csv_domains[@]}"; do
        resolve_and_allow "$domain"
      done
      ;;
    *)
      echo "[firewall] Reading domains from $file_path"
      while read -r domain; do
        domain=$(echo "$domain" | tr -d '\r' | xargs)
        if [[ -n "$domain" && "$domain" != \#* ]]; then
          resolve_and_allow "$domain"
        fi
      done <"$file_path"
      ;;
  esac
}

parse_domains_file "$DOMAINS_FILE"

if [[ -n "$EXTRA_DOMAINS" ]]; then
  EXTRA_DOMAINS=${EXTRA_DOMAINS// /,}
  IFS=',' read -ra extra_array <<<"$EXTRA_DOMAINS"
  for domain in "${extra_array[@]}"; do
    domain=$(echo "$domain" | xargs)
    resolve_and_allow "$domain"
  done
  IFS=$'\n\t'
fi

if [[ "$ALLOW_HOST_LAN" == "1" ]]; then
  HOST_IP=$(ip route | awk '/^default/ {print $3; exit}')
  if [[ -n "$HOST_IP" ]]; then
    HOST_CIDR=$(echo "$HOST_IP" | awk -F. '{printf "%s.%s.%s.0/24", $1,$2,$3}')
    echo "[firewall] Allowing host network $HOST_CIDR"
    add_cidr "$HOST_CIDR"
  fi
fi

iptables -C OUTPUT -j "$CHAIN" >/dev/null 2>&1 && iptables -D OUTPUT -j "$CHAIN"
iptables -N "$CHAIN" >/dev/null 2>&1 || true
iptables -F "$CHAIN"

iptables -A "$CHAIN" -m state --state ESTABLISHED,RELATED -j RETURN
iptables -A "$CHAIN" -o lo -j RETURN
iptables -A "$CHAIN" -p udp --dport 53 -j RETURN
iptables -A "$CHAIN" -p tcp --dport 53 -j RETURN
iptables -A "$CHAIN" -d 127.0.0.0/8 -j RETURN
iptables -A "$CHAIN" -m set --match-set "$IPSET" dst -j RETURN
iptables -A "$CHAIN" -j DROP

iptables -I OUTPUT 1 -j "$CHAIN"

echo "[firewall] Applied OUTPUT allowlist via $CHAIN using $IPSET"
