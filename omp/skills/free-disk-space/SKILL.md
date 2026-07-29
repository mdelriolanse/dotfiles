---
name: free-disk-space
description: Reclaim disk space on Linux by auditing and clearing build artifacts, package-manager and language-tool caches, stale git worktrees, and offloading large media to an external drive. Use whenever the user complains about low storage, a full disk, "no space left on device" errors, or asks to clean up, offload, or free up their machine — even if they don't name specific folders.
allowed-tools: Bash, Read, Grep, Glob
metadata:
  domain: ops
  triggers: disk full, out of space, no space left on device, free up space, clean up disk, offload
  role: specialist
---

# Free Disk Space (Linux)

Audit the disk, clear what's safely regenerable, and confirm before touching
anything that isn't.

## Ground rules

- **Shared machine.** Stay inside `$HOME`. Never touch other users' homes, and
  never run anything needing `sudo` (`apt clean`, `journalctl --vacuum`,
  `/var/cache`) without asking first.
- Delete with `gio trash <path>` (or `trash-put` if trash-cli is installed) so
  it lands in `~/.local/share/Trash`; ask the user to empty it once at the end.
  `gio trash` refuses files on another filesystem or over the trash size limit —
  confirm, then `rm -rf`.
- Prefer a tool's own cleanup command over deleting its directories:
  `go clean -cache -modcache`, `pnpm store prune`, `npm cache clean --force`,
  `uv cache prune`, `pip cache purge`, `cargo clean`, `ccache -C`,
  `conda clean -a`, `flatpak uninstall --unused`.
- **Never `docker system prune` / `podman system prune`.** Other devs' images,
  containers, and volumes share the daemon. At most `docker builder prune
  --filter until=<age>` after explicit confirmation — otherwise skip.
- **Do not clear GUI app data.** `~/.config/<app>`, `~/.local/share/<app>`,
  `~/.mozilla`, `~/.cache/google-chrome` hold logins, cookies, and history.
  Leave them alone unless the user names the app and accepts the risk. Prefer
  build cleanup, cache prune, stale worktrees, and external-drive offload.
- Measure per filesystem: `df -h "$HOME" /`. `/` and `/home` are usually
  separate partitions — freeing one does nothing for the other.

## Workflow

### 1. Assess

`df -h "$HOME" /; lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT`. Check
`/run/media/$USER`, `/media/$USER`, `/mnt` for an external drive. Note *which*
filesystem is actually full — that decides what's worth clearing.

### 2. Survey

Targeted `du -xh -d2 ~ 2>/dev/null | sort -hr | head -30` — bounded depth, `-x`
to stay on one filesystem. Not a full scan of `$HOME`. Usual big ones:

- **Build artifacts**: `node_modules/`, `target/`, `.venv/`, `build/`, `dist/`,
  `.next/`, `__pycache__/`, `.pytest_cache/`, `.mypy_cache/`. Locate with
  `find ~ -type d -name node_modules -prune -print` (every worktree too).
- **Language/tool caches**: `~/.cache/{go-build,uv,pip,pnpm,yarn,ccache,pre-commit}`,
  `~/.cargo/registry`, `~/go/pkg/mod`
- **Model weights / datasets**: `~/.cache/huggingface`, `~/.cache/torch`,
  `~/.ollama` — large and slow to re-download, always ask
- **Toolchains**: `~/.nvm`, `~/.rustup`, `~/.pyenv`, conda envs — report, ask
- **Large media**: `~/Downloads`, `~/Videos`, screen recordings
- **Trash already sitting there**: `du -sh ~/.local/share/Trash`
- Report app-data sizes only; don't auto-delete them

### 3. Clear safe tier without asking

Build artifacts and language-tool caches only. Everything else (app data,
media, model weights, toolchains, container storage): summarize sizes and ask,
or propose offload.

### 4. Audit git worktrees

`git worktree list` per repo. For each worktree: dirty? unique/unpushed commits
(`git log --oneline @{u}..`, or `gh` for remote state)? Clean and fully
merged/pushed → `git worktree remove` and `git branch -d` (never `-D`). Keep
and report anything dirty or ahead.

### 5. Offload keepers

`rsync -a --info=progress2 src/ /run/media/$USER/DRIVE/src/` → verify with
`du -sb` on both sides → trash the original → `ln -s` at the old path. Symlink
individual folders, not whole XDG dirs like `~/Videos`. Check the drive's
filesystem first: exFAT/NTFS won't preserve permissions or symlinks. Warn that
the app now needs the drive mounted.

### 6. Wrap up

What freed immediately, what's in Trash, what you left alone. Ask the user to
empty Trash (`gio trash --empty`) and re-check `df -h`.
