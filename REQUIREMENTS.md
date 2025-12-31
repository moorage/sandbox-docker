# Requirements: cxhere worktree reuse, stale dir handling, and docker reuse

## Problem
Running `cxhere <branch>` fails with `fatal: a branch named '<branch>' already exists` when a branch exists but no worktree is attached. Also, stale worktree directories can exist on disk without being registered in git, and the current flow doesn’t handle them cleanly.
Additionally, `cxhere` exits early if a worktree already exists, even when no Docker container is running for it.

## Goals
- Allow `cxhere <branch>` to proceed when the branch already exists but no worktree exists for it.
- Detect and handle a pre-existing worktree directory that is not registered as a worktree.
- Document the new behavior in the README.
- If the target worktree already exists, reuse it by launching Docker only when no container is running for that worktree.

## Non-goals
- Automatic cleanup or deletion of stale directories.
- Changing `cxclose` or `cxlist` behavior beyond documenting usage.
- Automatically attaching to an existing container.
- Changing Docker image or runtime flags beyond adding identification needed to find containers by bind mount.

## Acceptance Criteria
- If the branch exists and no worktree exists for it, `cxhere` creates a worktree using the existing branch without error.
- If the target worktree directory already exists on disk but is not a registered worktree, `cxhere` prints a clear error with next-step guidance and exits non-zero.
- If the target worktree directory is already registered as a worktree, `cxhere` checks for running containers with a bind mount to that directory.
- If exactly one running container is found for that worktree, `cxhere` prints a message and exits zero without launching Docker.
- If more than one running container is found for that worktree, `cxhere` refuses, prints a message listing one container ID, and exits non-zero.
- If no running container is found for that worktree, `cxhere` launches Docker even if the worktree is locked/busy by git.
- README includes a short note describing the behavior when the branch exists, when a stale directory is found, and when a worktree already exists with/without a running container.
