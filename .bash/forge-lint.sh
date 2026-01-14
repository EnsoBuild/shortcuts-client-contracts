#!/bin/sh
set -eu

echo "🔎 Running forge lint (default profile in foundry.toml)..."

# Capture BOTH stdout and stderr, but don't fail on forge's exit code
set +e
RAW_OUTPUT="$(forge lint --color never 2>&1)"
set -e

# Show raw linter output (so CI logs display everything)
printf '%s\n' "$RAW_OUTPUT"

# Normalize line endings (remove any CRs from CRLF)
SANITIZED="$(printf '%s\n' "$RAW_OUTPUT" | tr -d '\r')"

# Extract diagnostic lines that start with a severity (allow optional leading spaces),
# and ignore codesize warnings
DIAGNOSTICS="$(printf '%s\n' "$SANITIZED" \
  | grep -a -E '^[[:space:]]*(high|med|low|info|gas|warning|note)\[' \
  | grep -vF '[codesize]' \
  || true)"

if [ -n "$DIAGNOSTICS" ]; then
  echo "❌ Linting failed: either fix or disable [high|med|low|info|gas|warning|note] before committing."
  exit 1
fi

echo "✅ Pre-commit checks passed."
