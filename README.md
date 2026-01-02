# sandbox-docker

- PLANS.md and ExecPlans comes from <https://cookbook.openai.com/articles/codex_exec_plans>
- prompting guide comes from <https://cookbook.openai.com/examples/gpt-5/gpt-5-1-codex-max_prompting_guide>


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
  -v "$HOME/.gitconfig":/home/codex/.gitconfig:ro \
  -v "$HOME/.codex":/home/codex/.codex:rw \
  -e CODEX_HOME=/home/codex/.codex \
  codex-cli:local \
  --full-auto --search
```

## macOS zsh shortcut (`cxhere`)

Add this function to your `~/.zshrc` to run Codex in a dedicated git worktree and branch. You pass a
worktree name, which is also used as the branch name. This keeps multiple Codex sessions isolated
and lets you run them concurrently in the same repo. Slashes in the name are supported (for example
`mpm/my-feature`), and are only sanitized for the worktree directory on disk. Worktrees are created
next to the repo in a sibling directory named `<PROJECT-DIR-NAME>-worktrees/<WORKTREENAME>`.

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
- If Docker is not running or the daemon is unreachable, `cxhere` will surface the Docker error output and exit non-zero.

```bash
cxhere() {
  # Run in a subshell so `set -e` can't terminate the caller's shell.
  # This avoids zsh exiting entirely when a command fails.
  ( set -e
  if [ -z "$1" ]; then
    echo "usage: cxhere <worktree-name>" >&2
    return 2
  fi

  local branch_name worktree_slug repo_root repo_parent repo_name worktrees_root worktree_dir
  repo_root="$(git rev-parse --show-toplevel)"
  branch_name="$1"
  worktree_slug="${branch_name//\//__}"
  repo_parent="$(dirname "$repo_root")"
  repo_name="$(basename "$repo_root")"
  worktrees_root="$repo_parent/${repo_name}-worktrees"
  worktree_dir="$worktrees_root/$worktree_slug"

  docker_find_worktree_containers() {
    local match_ids
    match_ids="$(
      docker ps -q | while read -r id; do
        if docker inspect -f '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{"\n"}}{{end}}{{end}}' "$id" | rg -F -x "$worktree_dir"; then
          echo "$id"
        fi
      done
    )"
    printf "%s\n" "$match_ids"
  }

  mkdir -p "$worktrees_root"
  if git -C "$repo_root" worktree list --porcelain | rg -q "^worktree $worktree_dir$"; then
    local matching_ids
    matching_ids="$(docker_find_worktree_containers)"

    if [ -n "$matching_ids" ]; then
      local match_count
      match_count="$(printf "%s\n" "$matching_ids" | wc -l | tr -d ' ')"
      if [ "$match_count" -gt 1 ]; then
        echo "multiple containers running for worktree: $worktree_dir" >&2
        echo "example container: $(printf "%s\n" "$matching_ids" | head -n1)" >&2
        return 1
      fi
      echo "container already running for worktree: $worktree_dir ($matching_ids)" >&2
      return 0
    fi
  else
    if [ -e "$worktree_dir" ]; then
      echo "worktree directory exists but is not registered: $worktree_dir" >&2
      echo "hint: remove or rename it, or register it with: git worktree add \"$worktree_dir\" \"$branch_name\"" >&2
      return 1
    fi

    if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch_name"; then
      git worktree add "$worktree_dir" "$branch_name"
    else
      git worktree add -b "$branch_name" "$worktree_dir"
    fi
  fi

    docker run --rm -it \
    --init \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    --pids-limit=256 \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,nodev \
    --tmpfs /home/codex:rw,noexec,nosuid,nodev,size=512m \
    -v "$worktree_dir":/workspace:rw \
    -v "$HOME/.gitconfig":/home/codex/.gitconfig:ro \
    -v "$HOME/.codex":/home/codex/.codex:rw \
    -e CODEX_HOME=/home/codex/.codex \
    -w /workspace \
    codex-cli:local \
    --full-auto --sandbox workspace-write --ask-for-approval on-failure --search
  )
}

cxclose() {
  local repo_root repo_parent repo_name worktrees_root branch_name worktree_dir worktree_slug git_dir
  local status_output locked_line

  if [ -z "$1" ]; then
    echo "usage: cxclose <worktree-name>" >&2
    return 2
  fi

  repo_root="$(git rev-parse --show-toplevel)"
  branch_name="$1"
  worktree_slug="${branch_name//\//__}"
  repo_parent="$(dirname "$repo_root")"
  repo_name="$(basename "$repo_root")"
  worktrees_root="$repo_parent/${repo_name}-worktrees"
  worktree_dir="$worktrees_root/$worktree_slug"

  if ! git -C "$repo_root" worktree list --porcelain | rg -q "^worktree $worktree_dir$"; then
    echo "worktree not found: $worktree_dir" >&2
    return 1
  fi

  locked_line="$(git -C "$repo_root" worktree list --porcelain | awk -v wt="$worktree_dir" '
    $1=="worktree"{inwt=($2==wt)}
    inwt && $1=="locked"{print $0}
  ')"

  if [ -n "$locked_line" ]; then
    echo "worktree is locked (busy): $locked_line" >&2
    echo "hint: unlock it with: git worktree unlock \"$worktree_dir\"" >&2
    return 1
  fi

  if git -C "$worktree_dir" rev-parse --git-dir >/dev/null 2>&1; then
    git_dir="$(git -C "$worktree_dir" rev-parse --git-dir)"
    if [ -f "$git_dir/index.lock" ] || [ -f "$git_dir/HEAD.lock" ]; then
      echo "worktree appears busy (git lock files present)." >&2
      echo "hint: ensure no git process or container is using it, then retry." >&2
      return 1
    fi
  fi

  status_output="$(git -C "$worktree_dir" status --porcelain)"
  if [ -n "$status_output" ]; then
    echo "worktree has uncommitted changes; refusing to remove." >&2
    echo "hint: commit/stash changes or clean the worktree, then retry." >&2
    return 1
  fi

  git worktree remove "$worktree_dir"
  git branch -d "$branch_name"
}

cxlist() {
  set -e
  local repo_root repo_parent repo_name worktrees_root

  repo_root="$(git rev-parse --show-toplevel)"
  repo_parent="$(dirname "$repo_root")"
  repo_name="$(basename "$repo_root")"
  worktrees_root="$repo_parent/${repo_name}-worktrees"

  echo "codex worktrees under $worktrees_root:"
  git -C "$repo_root" worktree list --porcelain | awk -v base="$worktrees_root/" '
    $1=="worktree"{
      wt=$2; branch=""; head=""; locked=""; prunable=""
      next
    }
    $1=="branch"{branch=$2}
    $1=="HEAD"{head=$2}
    $1=="locked"{locked="locked"}
    $1=="prunable"{prunable="prunable"}
    $0==""{
      if (index(wt, base)==1) {
        status=""
        if (locked!="") status=status locked " "
        if (prunable!="") status=status prunable " "
        if (status=="") status="ok"
        printf "- %s | %s | %s\n", wt, branch, status
      }
    }
  '
}
```

Reload your shell and use it with a worktree name:

```bash
source ~/.zshrc
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
