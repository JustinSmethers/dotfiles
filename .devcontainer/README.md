# Flag-Based Devcontainer Template

This directory contains a reusable, flag-based devcontainer configuration. Every optional dependency or lifecycle hook is gated behind a flag so the same definition can be reused across projects.

## Included Tooling
- Base image `mcr.microsoft.com/devcontainers/python:3.13-bookworm`, which ships Python 3.13, pip, git, zsh, and common build tools from the official Dev Containers collection.
- `pipx`, `curl`, and `ca-certificates` baked into the image so command-line installers work out of the box.
- `uv` + `uvx` installed globally for dependency and script management.
- Optional extras enabled via build-time flags:
  - `DEVCONTAINER_ENABLE_PLAYWRIGHT=1` → installs Node.js/npm plus the entire Chromium/Playwright system dependency stack (GTK, fonts, audio libs, etc.).
  - `DEVCONTAINER_INSTALL_CLI_BUNDLE=1` → installs the OpenAI CLI (via pipx) and the Codex CLI (via npm) for Codex workflows.
  - `DEVCONTAINER_ENABLE_FIREWALL_DEPS=1` → installs `ipset`, `iptables`, `dnsutils`, and `jq` so network allowlisting can run.
- Optional runtime tasks enabled via flag files:
  - `DEVCONTAINER_RUN_UV_SYNC=1` → executes `uv sync --frozen` immediately after the container is created.
  - `DEVCONTAINER_INSTALL_PLAYWRIGHT_BROWSERS=1` → installs Playwright Chromium browsers (requires the Playwright build flag if system libs are needed).
  - `DEVCONTAINER_RUN_FIREWALL=1` → applies the allowlist defined in `init_firewall.sh`, honoring CSV/extra domain overrides.

## Build-Time Flags
Set these environment variables before running `devcontainer up` (or add them to the `build.args` block) to opt into additional image layers:

| Flag | Description |
| --- | --- |
| `DEVCONTAINER_ENABLE_PLAYWRIGHT=1` | Installs Chromium/Playwright system libraries plus Node.js/npm. |
| `DEVCONTAINER_INSTALL_CLI_BUNDLE=1` | Installs the OpenAI CLI via pipx and the Codex CLI via npm. |
| `DEVCONTAINER_ENABLE_FIREWALL_DEPS=1` | Installs `ipset`, `iptables`, `dnsutils`, and `jq` so the firewall script can run. |

By default these flags are unset/`0`, so the resulting image only has the Python toolchain + `uv`.

## Runtime Flags
Create `devcontainer-general/flags.local.env` (ignored by git) to override the defaults in `flags.default.env`. Each variable is binary (`0`/`1`) unless stated otherwise.

| Flag | Purpose |
| --- | --- |
| `DEVCONTAINER_RUN_UV_SYNC` | Run `uv sync --frozen` on container creation. |
| `DEVCONTAINER_INSTALL_PLAYWRIGHT_BROWSERS` | Run `uv run playwright install chromium --with-deps` on container creation. |
| `DEVCONTAINER_RUN_FIREWALL` | Invoke `init_firewall.sh` on every start. Requires `DEVCONTAINER_ENABLE_FIREWALL_DEPS=1` at build time. |
| `DEVCONTAINER_FIREWALL_DOMAINS_FILE` | Path (relative to repo) of a CSV or newline list to resolve and allow. Default: `devcontainer-general/firewall-domains.csv`. |
| `DEVCONTAINER_FIREWALL_EXTRA_DOMAINS` | Comma-separated hostnames that should always be allowed. |
| `DEVCONTAINER_FIREWALL_CHAIN`/`DEVCONTAINER_FIREWALL_IPSET` | Customize the iptables chain/ipset names if they conflict with existing setups. |
| `DEVCONTAINER_FIREWALL_ALLOW_HOST_LAN` | When `1`, automatically allow the host LAN /24. |

You can also export these variables before attaching to the devcontainer; the scripts treat environment values as higher priority than the defaults.

## Auth / Config Passthrough
The devcontainer bind-mounts your host auth/config directories so CLI tools stay signed in by default:
- `~/.codex` → `/home/vscode/.codex`
- `~/.config/uv` → `/home/vscode/.config/uv`
- `~/.config/claude` → `/home/vscode/.config/claude`

All mounts use your host `HOME`. If you want to opt out or point at different paths, adjust the `mounts` block in `devcontainer.json` before launching the container.

To disable a specific mount (e.g., Claude), edit `devcontainer.json` and list only the mounts you want. Example:

```jsonc
{
  // Keep Codex and uv mounts, drop Claude
  "mounts": [
    "type=bind,source=${localEnv:HOME}/.codex,target=/home/vscode/.codex,consistency=cached",
    "type=bind,source=${localEnv:HOME}/.config/uv,target=/home/vscode/.config/uv,consistency=cached"
  ]
}
```

### Example allowlist CSV
The default file `devcontainer-general/firewall-domains.csv` ships with sample rows you can edit in-place. Each row must provide a column named `url` (lowercase) or any of the other recognized headers (`Careers Page`, `URL`). The firewall script parses that column, extracts hostnames, and allows each resolved IP. To add more hosts, append rows like:

```csv
label,url
Example Careers,https://example.com/careers
Analytics Dashboard,https://dash.example.net/login
```

Alternatively, replace the file path with a newline-delimited list if CSV isn’t convenient.

## Lifecycle Hooks
- `post-create.sh` checks `DEVCONTAINER_RUN_UV_SYNC` and `DEVCONTAINER_INSTALL_PLAYWRIGHT_BROWSERS` before deciding whether to run the expensive bootstrap commands.
- `post-start.sh` checks `DEVCONTAINER_RUN_FIREWALL` and only shells out to the privileged firewall script when explicitly requested.

This mirrors the guidance in `docs/devcontainer-generalization.md`: keep the JSON generic, move per-project behavior into scripts, and gate every expensive step behind an opt-in flag.
