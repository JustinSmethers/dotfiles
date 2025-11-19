#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
# shellcheck source=devcontainer-general/flags.sh
source "$SCRIPT_DIR/flags.sh"
load_devcontainer_flags "$SCRIPT_DIR"

if flag_enabled DEVCONTAINER_RUN_UV_SYNC 0; then
  echo "[post-create] Running 'uv sync --frozen'"
  (cd "$PROJECT_ROOT" && uv sync --frozen)
else
  echo "[post-create] Skipping 'uv sync'; DEVCONTAINER_RUN_UV_SYNC=0"
fi

if flag_enabled DEVCONTAINER_INSTALL_PLAYWRIGHT_BROWSERS 0; then
  echo "[post-create] Installing Playwright Chromium"
  (cd "$PROJECT_ROOT" && uv run playwright install chromium --with-deps)
else
  echo "[post-create] Skipping Playwright browser install"
fi

echo "[post-create] Done"
