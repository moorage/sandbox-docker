# syntax=docker/dockerfile:1
FROM mcr.microsoft.com/playwright:v1.58.0-noble

RUN apt-get update && apt-get install -y --no-install-recommends \
  gnupg wget \
  && wget -qO /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc \
    https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc \
  && echo "deb https://cloud.r-project.org/bin/linux/ubuntu noble-cran40/" \
    > /etc/apt/sources.list.d/cran-r.list \
  && wget -qO /etc/apt/trusted.gpg.d/ngrok.asc \
    https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
  && echo "deb https://ngrok-agent.s3.amazonaws.com bookworm main" \
    > /etc/apt/sources.list.d/ngrok.list \
  && apt-get update && apt-get install -y --no-install-recommends \
  git openssh-client ca-certificates gh \
  python3 python3-pip python3-venv make g++ \
  ripgrep jq \
  ngrok \
  xvfb xauth \
  pulseaudio pulseaudio-utils \
  ffmpeg \
  r-base r-base-dev \
  && rm -rf /var/lib/apt/lists/*
RUN ln -s /usr/bin/python3 /usr/local/bin/python

# Codex CLI (npm package)
ARG NPM_CACHEBUST=1
RUN echo "npm cache bust: $NPM_CACHEBUST" >/dev/null && npm install -g npm@latest
RUN echo "codex cache bust: $NPM_CACHEBUST" >/dev/null && npm i -g @openai/codex

# Non-root user
RUN useradd -m -u 10001 -s /bin/bash codex

RUN mv /usr/local/bin/ngrok /usr/local/bin/ngrok-real
COPY scripts/codex-entrypoint.sh /usr/local/bin/codex-entrypoint.sh
COPY scripts/ngrok-wrapper.sh /usr/local/bin/ngrok
RUN chmod +x /usr/local/bin/codex-entrypoint.sh
RUN chmod +x /usr/local/bin/ngrok

USER codex
WORKDIR /workspace
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
ENV GIT_CONFIG_GLOBAL=/home/codex/.gitconfig
ENTRYPOINT ["/usr/local/bin/codex-entrypoint.sh"]
