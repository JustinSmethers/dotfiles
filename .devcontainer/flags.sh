#!/usr/bin/env bash
# Helper functions for working with devcontainer flag files.

load_devcontainer_flags() {
  local script_dir=$1
  local default_file="$script_dir/flags.default.env"
  local local_file="$script_dir/flags.local.env"
  local extra_file="${DEVCONTAINER_FLAG_FILE:-}"

  for file in "$default_file" "$local_file" "$extra_file"; do
    if [[ -n "$file" && -f "$file" ]]; then
      # shellcheck disable=SC1090
      source "$file"
    fi
  done
}

flag_enabled() {
  local name=$1
  local default=${2:-0}
  local value=${!name:-}
  if [[ -z "$value" ]]; then
    value=$default
  fi
  [[ "$value" == "1" ]]
}

flag_value() {
  local name=$1
  local default=$2
  local value=${!name:-}
  if [[ -z "$value" ]]; then
    value=$default
  fi
  printf '%s' "$value"
}
