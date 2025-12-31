# syntax=docker/dockerfile:1
FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
  git openssh-client ca-certificates \
  python3 make g++ \
  ripgrep jq \
  && rm -rf /var/lib/apt/lists/*

# Codex CLI (npm package)
RUN npm i -g @openai/codex

# Non-root user
RUN useradd -m -u 10001 -s /bin/bash codex
USER codex

WORKDIR /workspace
ENTRYPOINT ["codex"]
