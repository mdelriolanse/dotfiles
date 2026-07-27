#!/usr/bin/env node
// Cursor user hooks for ponytail — mirrors opencode ponytail-bridge + ponytail-activate.
const fs = require('fs');
const path = require('path');

const PONYTAIL_HOOKS = path.join(
  process.env.HOME || require('os').homedir(),
  '.config/opencode/ponytail/hooks'
);
const { getDefaultMode, getClaudeDir, normalizePersistedMode } = require(
  path.join(PONYTAIL_HOOKS, 'ponytail-config')
);
const { getPonytailInstructions } = require(path.join(PONYTAIL_HOOKS, 'ponytail-instructions'));
const { setMode, clearMode } = require(path.join(PONYTAIL_HOOKS, 'ponytail-runtime'));

const VALID_MODES = new Set(['off', 'lite', 'full', 'ultra', 'review']);

function readInput() {
  try {
    return JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
  } catch {
    return {};
  }
}

function getActiveMode() {
  try {
    const flagPath = path.join(getClaudeDir(), '.ponytail-active');
    if (fs.existsSync(flagPath)) {
      const mode = normalizePersistedMode(fs.readFileSync(flagPath, 'utf8').trim());
      if (mode) return mode;
    }
  } catch {}
  return null;
}

function effectiveMode() {
  return getActiveMode() || getDefaultMode();
}

function handleBeforeSubmit(input) {
  const prompt =
    input.prompt ||
    input.text ||
    input.user_message ||
    input.content ||
    '';
  const match = String(prompt).trim().match(/^\/ponytail(?:\s+(.*))?$/i);
  if (!match) {
    process.stdout.write('{}\n');
    return;
  }

  const arg = (match[1] || '').trim().toLowerCase();
  const mode = VALID_MODES.has(arg) ? arg : 'full';
  if (mode === 'off') clearMode();
  else setMode(mode);
  process.stdout.write('{}\n');
}

function handleSessionStart() {
  const mode = effectiveMode();
  if (mode === 'off') {
    clearMode();
    process.stdout.write('{}\n');
    return;
  }

  try {
    setMode(mode);
  } catch {}

  const context = getPonytailInstructions(mode);
  process.stdout.write(JSON.stringify({ additional_context: context }) + '\n');
}

const event = (process.argv[2] || 'sessionStart').trim();
const input = readInput();

if (event === 'beforeSubmitPrompt') handleBeforeSubmit(input);
else handleSessionStart();
