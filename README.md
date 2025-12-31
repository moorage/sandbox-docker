# sandbox-docker

## Building the Docker Image

To build the Docker image, run the following command in the terminal:

```bash
docker build -t codex-cli:local .
```

## Running the Docker Container

```bash
docker run --rm -it \
  --init \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --pids-limit=256 \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,nodev \
  --tmpfs /home/codex:rw,noexec,nosuid,nodev,size=512m \
  -v "$(pwd)":/workspace:rw \
  -v "$HOME/.codex":/home/codex/.codex:rw \
  -e CODEX_HOME=/home/codex/.codex \
  codex-cli:local \
  --full-auto --search
```

## macOS zsh shortcut (`cxhere`)

Add this function to your `~/.zshrc` to run Codex in the current directory with the same container flags:

```bash
cxhere() {
  docker run --rm -it \
    --init \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    --pids-limit=256 \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,nodev \
    --tmpfs /home/codex:rw,noexec,nosuid,nodev,size=512m \
    -v "$(pwd)":/workspace:rw \
    -v "$HOME/.codex":/home/codex/.codex:rw \
    -e CODEX_HOME=/home/codex/.codex \
    codex-cli:local \
    --full-auto --search
}
```

Reload your shell and use it:

```bash
source ~/.zshrc
cxhere
```
