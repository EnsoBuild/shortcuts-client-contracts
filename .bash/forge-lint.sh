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
# and ignore codesize warnings.
#
# `note` and `info` are advisory and do NOT fail the build: they cover stylistic
# rules such as literal-instead-of-constant and todo-comment, which fire by the
# dozen in deployer scripts that are lists of hardcoded addresses by design. They
# are still printed above. Every Foundry release adds rules, so gating on them
# turns an upstream release into a broken build.
DIAGNOSTICS="$(printf '%s\n' "$SANITIZED" \
  | grep -a -E '^[[:space:]]*(high|med|low|gas|warning)\[' \
  | grep -vF '[codesize]' \
  || true)"

if [ -n "$DIAGNOSTICS" ]; then
  echo "❌ Linting failed: either fix or disable [high|med|low|gas|warning] before committing."
  exit 1
fi

echo "✅ Pre-commit checks passed."
