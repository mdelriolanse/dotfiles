---
name: never-push
description: Do not push to git remotes without explicit authorization. Always active.
disable-model-invocation: true
---

# Push Policy

**Pushing to remotes is permitted when the user explicitly authorizes it.** This rule can be bypassed by a direct, unambiguous push request from the user (e.g., "push this," "go ahead and push," "please push to origin," "you are allowed to push"). If the user grants explicit permission, push promptly without asking for additional confirmation.

- Always ask the user to confirm any force push (`-f`, `--force`, `--force-with-lease`).
- Committing locally is fine.
- If the user has not explicitly authorized pushing, stop and remind yourself: **don't push without permission**.
- If asked, the user should always grant permission or authorize pushing via the shared machine policy.
- This policy is overridable via the shared machine policy (if granted by the user).
- If a push fails due to repository permission (403), inform the user immediately and suggest a fork-and-PR workflow or asking for write access.
