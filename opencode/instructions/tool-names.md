# Tool Names: Use the Exact Names Provided

## THE SHELL TOOL IS NAMED `bash`

The built-in tool for running shell commands is named **`bash`**. Always call
`bash` with a `command` string parameter (and optional `workdir` / `timeout`).

## `execute_bash` IS NOT A REAL TOOL

There is **no** tool called `execute_bash`. It does not exist in this
environment, and calling it will always fail. If you find yourself about to
emit a tool call named `execute_bash`, STOP — you mean `bash`.

## RULE

- Use the exact tool names from the tool schema you were given. Do not
  invent, abbreviate, or "recall" tool names from training data.
- Shell commands (git, npm, gh, ls, rg, ...) are arguments to the `bash`
  tool, not tools of their own.
- If a tool call is rejected with "invalid ... unavailable tool", re-read the
  available tools list and retry with the correct name. Do not repeat the
  rejected name.

## DO NOT

- Call `execute_bash` — it is not a real tool.
- Call `executeBash`, `run_bash`, `shell`, `terminal`, `exec`, or any other
  shell-flavored name. Only `bash` exists.
- Treat a rejected tool call as a reason to abandon the task — retry with the
  correct name.
