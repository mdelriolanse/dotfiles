---
name: shared-machine
description: HARD RULE — this is a shared dev machine. Never interfere with other devs' work. Always active.
disable-model-invocation: true
---

# Shared Machine Policy — HARD RULE

**This is a shared development machine.** Other developers work on it simultaneously. You must never interfere with their work, resources, or processes.

## Ports and networking

- **Assume every port could be in use by another dev.** Before binding to any port, check if it's already occupied (`ss -tlnp`, `lsof -i`, or similar).
- **Never kill or override another dev's port binding.** Choose a different port instead.
- **Never modify system-wide network configuration** (iptables, nftables, /etc/hosts, DNS resolvers) without explicit request.
- **Never expose services on public interfaces (0.0.0.0) without explicit request.**

## Processes and containers

- **Never kill, stop, or restart processes you didn't start.** This includes Docker containers, systemd services, and background daemons.
- **Never run `docker-compose down`, `docker stop`, `docker rm`, `kill`, `pkill`, or `killall`** without explicit confirmation you're targeting your own resources.
- **Never run `systemctl stop/restart/disable` on system services** unless explicitly instructed.
- **If you start a container or long-running process, bind it to your own user context** (e.g., use your username in container names, use non-conflicting ports, clean up when done).

## Filesystem

- **Stay within your home directory** (`$HOME`) unless explicitly directed elsewhere.
- **Never read, modify, or delete files owned by other users** or in their home directories.
- **Never change permissions or ownership of shared directories** (`/tmp`, `/opt`, `/usr/local`) unless instructed.
- **Never delete or modify files under `/var`, `/etc`, or `/dev`** without explicit request.

## System-wide resources

- **Never modify shared configuration** (global git config, system PATH, global npm/pip packages, kernel parameters).
- **Never restart the machine or trigger a reboot.**
- **Never install or remove system packages** (`apt`, `yum`, `dnf`, `pacman`) unless instructed.
- **Never run `chown`, `chmod -R` on shared directories.**

## What IS allowed

- Creating, modifying, and deleting files within `$HOME`.
- Starting processes and containers scoped to your user, on non-conflicting ports, cleaned up after use.
- Installing packages in user-local contexts (user pip, user npm, npx, local venvs).
- Running `git` operations on your own repositories (never push — see never-push policy).
- Using `/tmp/opencode` for temporary work.

## When in doubt

If an action could affect another developer — **stop and ask the user first.**
