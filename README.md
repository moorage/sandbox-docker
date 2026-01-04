# sandbox-docker

## Build the Docker image

```bash
docker build -t codex-cli:local .
```

## Set up the zsh shortcuts

Add this to your `~/.zshrc`:

```bash
source /path/to/sandbox-docker/scripts/codex-worktrees.zsh
```

Reload your shell:

```bash
source ~/.zshrc
```

Optional: copy the default rules template:

```bash
mkdir -p ~/.codex/rules
cp /path/to/sandbox-docker/default.example.rules ~/.codex/rules/default.rules
```

## Use `cxhere`, `cxclose`, and `cxlist`

Start a Codex session in a dedicated git worktree + branch:

```bash
cxhere mpm/my-feature
```

Cleanup when you're done:

```bash
cxclose mpm/my-feature
```

List active Codex worktrees and flag anything prunable/stale:

```bash
cxlist
```

## Running the Docker container (manual)

```bash
docker run --rm -it \
  --init \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --pids-limit=256 \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,nodev \
  --tmpfs /home/codex:rw,noexec,nosuid,nodev,size=512m,uid=10001,gid=10001 \
  -v "$worktree_dir":/workspace:rw \
  -v "$HOME/.gitconfig":/home/codex/.gitconfig:ro \
  -v "$HOME/.codex":/home/codex/.codex:rw \
  "${env_file_arg[@]}" \
  -e CODEX_HOME=/home/codex/.codex \
  -e NPM_CONFIG_CACHE=/home/codex/.npm \
  -w /workspace \
  codex-cli:local \
  --dangerously-bypass-approvals-and-sandbox \
  --search
```

## Implementation and behavior notes

`cxhere` runs Codex in a dedicated git worktree and branch. You pass a worktree name, which is also used as the
branch name. This keeps multiple Codex sessions isolated and lets you run them concurrently in the same repo.
Slashes in the name are supported (for example `mpm/my-feature`) and are only sanitized for the worktree
directory on disk. Worktrees are created next to the repo in a sibling directory named
`<PROJECT-DIR-NAME>-worktrees/<WORKTREENAME>`.

Example paths:

```text
/path/to/sandbox-docker
/path/to/sandbox-docker-worktrees/mpm__my-feature
```

Behavior notes:

- If the branch already exists and no worktree exists for it, `cxhere` will reuse the branch and create a worktree.
- If the target worktree directory exists on disk but is not registered with git, `cxhere` will stop and print guidance.
- If a worktree already exists, `cxhere` checks for running containers with a bind mount to that worktree:
  - Exactly one container: print a message and exit 0.
  - More than one: print a message and exit non-zero.
  - None: launch Docker with the existing worktree.
- After creating or reusing a worktree, `cxhere` checks for `.agent/PLANS.md` and offers to create it from the project template if missing.
- Before launching Docker, `cxhere` checks for `$CODEX_HOME/AGENTS.md` and offers to create it from the global template if missing.
- If Docker is not running or the daemon is unreachable, `cxhere` will surface the Docker error output and exit non-zero.
