#!/bin/bash
# post-edit-tests.sh
# Runs tests after file edits to catch issues early
# This is informational - doesn't block, but reports status

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Skip non-code files
if echo "$FILE_PATH" | grep -qE "\.(md|txt|json|yaml|yml|toml|lock)$"; then
  exit 0
fi

# Skip test files themselves (avoid infinite loop)
if echo "$FILE_PATH" | grep -qE "\.(test|spec)\.(ts|tsx|js|jsx)$"; then
  exit 0
fi

# Skip if no package.json (not a JS/TS project)
if [ ! -f "package.json" ]; then
  exit 0
fi

# Detect package manager
if [ -f "pnpm-lock.yaml" ]; then
  PKG="pnpm"
elif [ -f "yarn.lock" ]; then
  PKG="yarn"
else
  PKG="npm"
fi

echo "🧪 Post-edit check: Running tests after editing $FILE_PATH..." >&2

# Run typecheck first (faster)
if [ -f "tsconfig.json" ]; then
  if ! $PKG run typecheck 2>&1 >/dev/null; then
    echo "⚠️ Typecheck failing after edit. Fix before committing." >&2
  fi
fi

# Run related tests if possible
RELATED_TEST="${FILE_PATH%.ts}.test.ts"
RELATED_TEST="${RELATED_TEST%.tsx}.test.tsx"
RELATED_TEST="${RELATED_TEST%.js}.test.js"
RELATED_TEST="${RELATED_TEST%.jsx}.test.jsx"

if [ -f "$RELATED_TEST" ]; then
  echo "Running related test: $RELATED_TEST" >&2
  $PKG test -- "$RELATED_TEST" 2>&1 || echo "⚠️ Related test failing" >&2
else
  # Run full test suite (could be slow - consider running in background)
  echo "Running test suite..." >&2
  timeout 60 $PKG test 2>&1 || echo "⚠️ Some tests failing after edit" >&2
fi

# Always exit 0 - this is informational, not blocking
# The pre-commit-gate will do the actual blocking
exit 0
