# Context Efficiency Policy

## Searching before reading
- ALWAYS prefer grep/ripgrep over reading entire files. Search for symbols, function names, or patterns FIRST.
- When you find a match, use Read with offset/limit to read ONLY the relevant function or block (20-50 lines), never the whole file unless critical.
- Do NOT read the same file twice in a conversation. Reference it by path:line once read.

## Stable files
- Files that haven't changed across turns (project dependencies, config files, framework code) are "stable" — do NOT re-read or re-include them.
- Reference stable files by path:line-number if you've already read them. The prompt cache will retain them.
- Only re-read a file if the user explicitly modifies it or asks for a fresh read.

## Context discipline
- Do NOT echo file contents in output unless asked. Reference locations briefly (e.g., "src/foo.ts:42").
- Minimize explanation text. One-line answers unless detail is requested.
- Batch parallel reads. Read multiple small sections in one call rather than sequentially.

## Tool output summarization
- Summarize tool outputs aggressively. Do NOT pipe raw output back into context.
- Reduce command output to the essential signal: success/failure, key values, relevant matches, error line.
- For grep/ripgrep results, report only the matched file:line locations and the matching snippet.
- For build/test output, report only the count of failures and the failing test names or error lines.
- For git output, report only the relevant delta (branch, changed files count, commit message).
- If output exceeds 200 lines, reduce it to a 3-5 line summary of what happened.
- NEVER echo full file paths lists, full logs, or full stack traces — extract the actionable subset.
