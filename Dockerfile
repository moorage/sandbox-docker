# syntax=docker/dockerfile:1
FROM mcr.microsoft.com/playwright:v1.58.0-noble

ARG APT_CACHEBUST=1
RUN echo "apt cache bust: $APT_CACHEBUST" >/dev/null && \
  apt-get update && apt-get install -y --no-install-recommends \
  git openssh-client ca-certificates gh \
  python3 make g++ \
  ripgrep jq \
  && rm -rf /var/lib/apt/lists/*

# Codex CLI (npm package)
ARG NPM_CACHEBUST=1
RUN echo "npm cache bust: $NPM_CACHEBUST" >/dev/null && npm install -g npm@latest
RUN echo "codex cache bust: $NPM_CACHEBUST" >/dev/null && npm i -g @openai/codex

# Non-root user
RUN useradd -m -u 10001 -s /bin/bash codex
USER codex

WORKDIR /workspace
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
ENV GIT_CONFIG_GLOBAL=/home/codex/.gitconfig
ENTRYPOINT ["codex"]
