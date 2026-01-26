#!/usr/bin/env zsh

cxhere() {
  # Run in a subshell so `set -e` can't terminate the caller's shell.
  # This avoids zsh exiting entirely when a command fails.
  ( set -e
  if [ -z "$1" ]; then
    echo "usage: cxhere <worktree-name> [session-id]" >&2
    echo "env: CXHERE_NO_DOCKER=1 to run codex locally without docker" >&2
    return 2
  fi

  local branch_name worktree_slug repo_root repo_parent repo_name worktrees_root worktree_dir
  local session_id
  local -a codex_args
  local plans_url plans_path create_plans
  local agents_url agents_path create_agents
  local env_file create_env_file
  local -a env_sources
  local gitignore_path create_gitignore add_env_ignore
  local env_file_arg
  local codex_config codex_config_dir add_workspace_trust
  local use_docker
  repo_root="$(git rev-parse --show-toplevel)"
  branch_name="$1"
  session_id="$2"
  worktree_slug="${branch_name//\//__}"
  repo_parent="$(dirname "$repo_root")"
  repo_name="$(basename "$repo_root")"
  worktrees_root="$repo_parent/${repo_name}-worktrees"
  worktree_dir="$worktrees_root/$worktree_slug"
  plans_url="https://raw.githubusercontent.com/moorage/sandbox-docker/refs/heads/main/PLANS.example.project.md"
  plans_path="$worktree_dir/.agent/PLANS.md"
  agents_url="https://raw.githubusercontent.com/moorage/sandbox-docker/refs/heads/main/AGENTS.example.global.md"
  agents_path="${CODEX_HOME:-$HOME/.codex}/AGENTS.md"
  codex_config="${CODEX_HOME:-$HOME/.codex}/config.toml"
  codex_config_dir="$(dirname "$codex_config")"
  env_file="$worktree_dir/.env.cx.local"
  gitignore_path="$worktree_dir/.gitignore"
  env_file_arg=()
  use_docker=1

  case "${CXHERE_NO_DOCKER:-}" in
    1|true|TRUE|yes|YES|y|Y) use_docker=0 ;;
  esac

  codex_workspace_trust_present() {
    [ -f "$codex_config" ] || return 1
    awk '
      BEGIN{in_section=0;ok=0}
      /^\[/{in_section=0}
      /^\[projects\."\/workspace"\]/{in_section=1}
      in_section && /^[[:space:]]*trust_level[[:space:]]*=[[:space:]]*"trusted"[[:space:]]*$/{ok=1}
      END{exit ok?0:1}
    ' "$codex_config"
  }

  codex_ensure_workspace_trust() {
    if codex_workspace_trust_present; then
      return 0
    fi

    echo "codex config missing trusted /workspace entry: $codex_config" >&2
    read -r "add_workspace_trust?Add it? [y/N] "
    if [[ "$add_workspace_trust" != [yY]* ]]; then
      return 0
    fi

    mkdir -p "$codex_config_dir"
    if [ ! -f "$codex_config" ]; then
      printf "%s\n" "[projects.\"/workspace\"]" "trust_level = \"trusted\"" > "$codex_config"
      echo "created $codex_config with /workspace trust" >&2
      return 0
    fi

    if rg -q '^\[projects\."\/workspace"\][[:space:]]*$' "$codex_config"; then
      local tmp_config
      tmp_config="$(mktemp)"
      awk '
        BEGIN{in_section=0;done=0}
        /^\[projects\."\/workspace"\]/{print; in_section=1; next}
        /^\[/{ if (in_section && !done){print "trust_level = \"trusted\""; done=1} in_section=0 }
        {
          if (in_section && $0 ~ /^[[:space:]]*trust_level[[:space:]]*=/) {
            if (!done) {print "trust_level = \"trusted\""; done=1}
            next
          }
          print
        }
        END{ if (in_section && !done) print "trust_level = \"trusted\"" }
      ' "$codex_config" > "$tmp_config"
      mv "$tmp_config" "$codex_config"
      echo "updated $codex_config with /workspace trust" >&2
    else
      printf "\n%s\n%s\n" "[projects.\"/workspace\"]" "trust_level = \"trusted\"" >> "$codex_config"
      echo "added /workspace trust to $codex_config" >&2
    fi
  }

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
    if [ "$use_docker" -eq 1 ]; then
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

  if [ ! -f "$plans_path" ]; then
    echo "missing plans file: $plans_path" >&2
    read -r "create_plans?Create it from $plans_url? [y/N] "
    if [[ "$create_plans" == [yY]* ]]; then
      mkdir -p "$(dirname "$plans_path")"
      if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "$plans_url" -o "$plans_path"; then
          echo "failed to download plans template; please create $plans_path manually." >&2
        fi
      elif command -v wget >/dev/null 2>&1; then
        if ! wget -qO "$plans_path" "$plans_url"; then
          echo "failed to download plans template; please create $plans_path manually." >&2
        fi
      else
        echo "neither curl nor wget is available; please create $plans_path manually." >&2
      fi
    fi
  fi

  if [ ! -f "$agents_path" ]; then
    echo "missing agents file: $agents_path" >&2
    read -r "create_agents?Create it from $agents_url? [y/N] "
    if [[ "$create_agents" == [yY]* ]]; then
      mkdir -p "$(dirname "$agents_path")"
      if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "$agents_url" -o "$agents_path"; then
          echo "failed to download agents template; please create $agents_path manually." >&2
        fi
      elif command -v wget >/dev/null 2>&1; then
        if ! wget -qO "$agents_path" "$agents_url"; then
          echo "failed to download agents template; please create $agents_path manually." >&2
        fi
      else
        echo "neither curl nor wget is available; please create $agents_path manually." >&2
      fi
    fi
  fi

  setopt local_options null_glob
  env_sources=("$repo_root"/.env*)
  if (( ${#env_sources[@]} )); then
    local env_source env_target
    for env_source in "${env_sources[@]}"; do
      if [ -f "$env_source" ]; then
        env_target="$worktree_dir/$(basename "$env_source")"
        if [ ! -f "$env_target" ]; then
          cp "$env_source" "$env_target"
          echo "copied env file: $env_target"
        fi
      fi
    done
  fi

  if [ ! -f "$env_file" ]; then
    echo "missing env file: $env_file" >&2
    read -r "create_env_file?Create it? [y/N] "
    if [[ "$create_env_file" == [yY]* ]]; then
      : > "$env_file"
      echo "created env file: $env_file"
    fi
  fi

  if [ ! -f "$gitignore_path" ]; then
    read -r "create_gitignore?Create $gitignore_path and ignore .env* files? [y/N] "
    if [[ "$create_gitignore" == [yY]* ]]; then
      printf "%s\n" ".env*" > "$gitignore_path"
      echo "created $gitignore_path with .env* ignore"
    fi
  elif ! rg -q '^[[:space:]]*\.env([[:space:]]*$|\*|[.])' "$gitignore_path"; then
    read -r "add_env_ignore?Add .env* to $gitignore_path? [y/N] "
    if [[ "$add_env_ignore" == [yY]* ]]; then
      printf "%s\n" ".env*" >> "$gitignore_path"
      echo "added .env* to $gitignore_path"
    fi
  fi

  codex_ensure_workspace_trust

  echo "worktree directory: $worktree_dir"
  if command -v code >/dev/null 2>&1; then
    echo "open in VS Code: code \"$worktree_dir\""
  fi
  if command -v cursor >/dev/null 2>&1; then
    echo "open in Cursor: cursor \"$worktree_dir\""
  fi
  if command -v codium >/dev/null 2>&1; then
    echo "open in VSCodium: codium \"$worktree_dir\""
  fi
  if command -v open >/dev/null 2>&1; then
    echo "open in Finder: open \"$worktree_dir\""
  fi
  if command -v xdg-open >/dev/null 2>&1; then
    echo "open in file manager: xdg-open \"$worktree_dir\""
  fi
  if command -v wslpath >/dev/null 2>&1 && command -v explorer.exe >/dev/null 2>&1; then
    echo "open in Explorer (WSL): explorer.exe \"$(wslpath -w "$worktree_dir")\""
  elif command -v explorer.exe >/dev/null 2>&1; then
    echo "open in Explorer: explorer.exe \"$(pwd -W 2>/dev/null)\""
  fi

  if [ -f "$env_file" ]; then
    env_file_arg=(--env-file "$env_file")
  fi

  codex_args=()
  if [ -n "$session_id" ]; then
    codex_args=(resume "$session_id")
  fi

  if [ "$use_docker" -eq 1 ]; then
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
      "${codex_args[@]}" \
      --dangerously-bypass-approvals-and-sandbox \
      --search
  else
    if [ -f "$env_file" ]; then
      set -a
      . "$env_file"
      set +a
    fi
    if ! command -v codex >/dev/null 2>&1; then
      echo "codex CLI not found in PATH; install it or enable Docker mode." >&2
      return 1
    fi
    (cd "$worktree_dir" && codex "${codex_args[@]}" --dangerously-bypass-approvals-and-sandbox --search)
  fi
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
