FROM mcr.microsoft.com/devcontainers/python:3.13-bookworm

ARG ENABLE_PLAYWRIGHT=0
ARG INSTALL_CLI_BUNDLE=0
ARG ENABLE_FIREWALL_DEPS=0

ENV PIPX_BIN_DIR=/usr/local/bin \
    PIPX_HOME=/opt/pipx

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      pipx \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    mv /root/.local/bin/uv /usr/local/bin/uv && \
    mv /root/.local/bin/uvx /usr/local/bin/uvx && \
    rm -rf /root/.local

# Install Node.js / npm when either Playwright tooling or Codex CLI is desired.
RUN if [ "${ENABLE_PLAYWRIGHT:-0}" = "1" ] || [ "${INSTALL_CLI_BUNDLE:-0}" = "1" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        nodejs \
        npm \
      && rm -rf /var/lib/apt/lists/*; \
    fi

# Optional Playwright browser dependencies.
RUN if [ "${ENABLE_PLAYWRIGHT:-0}" = "1" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        fonts-liberation \
        libappindicator3-1 \
        libasound2 \
        libcairo2 \
        libcups2 \
        libdrm2 \
        libgbm1 \
        libgtk-3-0 \
        libnss3 \
        libpango-1.0-0 \
        libpangocairo-1.0-0 \
        libx11-xcb1 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libxkbcommon0 \
        libxrandr2 \
        libxrender1 \
        libxshmfence1 \
        libatk-bridge2.0-0 \
        libatk1.0-0 \
        libatspi2.0-0 \
        libxtst6 \
        xdg-utils \
      && rm -rf /var/lib/apt/lists/*; \
    fi

# Optional CLI bundle (OpenAI CLI + Codex CLI).
RUN if [ "${INSTALL_CLI_BUNDLE:-0}" = "1" ]; then \
      pipx install openai && \
      npm install -g @openai/codex; \
    fi

# Optional firewall dependencies.
RUN if [ "${ENABLE_FIREWALL_DEPS:-0}" = "1" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        dnsutils \
        ipset \
        iptables \
        jq \
      && rm -rf /var/lib/apt/lists/*; \
    fi

USER vscode
WORKDIR /workspaces/job-watcher
