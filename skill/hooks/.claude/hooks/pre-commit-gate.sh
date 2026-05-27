#!/bin/bash
# pre-commit-gate.sh
# Blocks git commit if tests or typecheck fail
# Exit 2 = block, Exit 0 = allow

set -e

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only intercept git commit commands
if ! echo "$COMMAND" | grep -qE "^git\s+commit"; then
  exit 0
fi

echo "🔒 Pre-commit gate: Verifying tests before commit..." >&2

# Detect package manager
if [ -f "pnpm-lock.yaml" ]; then
  PKG="pnpm"
elif [ -f "yarn.lock" ]; then
  PKG="yarn"
else
  PKG="npm"
fi

# Run typecheck if TypeScript project
if [ -f "tsconfig.json" ]; then
  echo "📘 Running typecheck..." >&2
  if ! $PKG run typecheck 2>&1; then
    echo "❌ BLOCKED: Typecheck failed. Fix type errors before committing." >&2
    exit 2
  fi
  echo "✅ Typecheck passed" >&2
fi

# Run tests
echo "🧪 Running tests..." >&2
if ! $PKG test 2>&1; then
  echo "❌ BLOCKED: Tests failed. Fix failing tests before committing." >&2
  exit 2
fi
echo "✅ Tests passed" >&2

# Run build if build script exists
if $PKG run --if-present build:check 2>/dev/null || [ -f "package.json" ] && grep -q '"build"' package.json; then
  echo "🏗️ Running build..." >&2
  if ! $PKG run build 2>&1; then
    echo "❌ BLOCKED: Build failed. Fix build errors before committing." >&2
    exit 2
  fi
  echo "✅ Build passed" >&2
fi

# Run lint if configured
if [ -f ".eslintrc.js" ] || [ -f ".eslintrc.json" ] || [ -f "eslint.config.js" ]; then
  echo "🔍 Running lint..." >&2
  if ! $PKG run lint 2>&1; then
    echo "⚠️ Lint warnings detected (not blocking)" >&2
  fi
fi

echo "✅ All pre-commit checks passed. Commit allowed." >&2
exit 0
