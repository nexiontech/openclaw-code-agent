#!/bin/bash
# reachability-check.sh — Find new exports that are only imported by test files
#
# Detects "dead code" pattern: worker creates exported functions that pass unit tests
# but are never imported from actual application code (only from .test./.spec. files).
#
# Usage: ./scripts/reachability-check.sh [base-branch]
# Default base: main
#
# Exit 0 = all new exports reachable from non-test code
# Exit 1 = unreachable exports found (potentially unwired)

set -u

BASE="${1:-main}"
WARNINGS=0
UNREACHABLE=0

echo "=== REACHABILITY CHECK ==="
echo "Comparing against: $BASE"
echo ""

# Get list of changed/added files (source only, not tests)
CHANGED_FILES=$(git diff "$BASE" --name-only --diff-filter=AM 2>/dev/null | grep -E '\.(ts|js|tsx|jsx)$' | grep -vE '\.test\.|\.spec\.|__test__|__mock__' || true)

if [ -z "$CHANGED_FILES" ]; then
  echo "No changed source files found."
  echo "ALL REACHABLE (nothing to check)"
  exit 0
fi

# For each changed file, find new exports
for file in $CHANGED_FILES; do
  [ -f "$file" ] || continue

  # Get new exported symbols (added lines with export)
  EXPORTS=$(git diff "$BASE" -- "$file" 2>/dev/null | grep "^+" | grep -v "^+++" | grep -E "export (function|const|class|type|interface|enum|default)" | sed 's/^+//' || true)

  [ -z "$EXPORTS" ] || while IFS= read -r export_line; do
    # Extract the symbol name
    SYMBOL=$(echo "$export_line" | grep -oE '(function|const|class|type|interface|enum) [a-zA-Z_][a-zA-Z0-9_]*' | awk '{print $2}' || true)

    # Handle default exports
    if [ -z "$SYMBOL" ] && echo "$export_line" | grep -q "export default"; then
      SYMBOL="default"
    fi

    [ -z "$SYMBOL" ] && continue

    # Get the filename without extension for import matching
    BASENAME=$(basename "$file" | sed 's/\.[^.]*$//')
    DIRPATH=$(dirname "$file")

    # Search for imports of this symbol from non-test files
    # Match: import { Symbol } from '...' or import Symbol from '...'
    NON_TEST_IMPORTS=$(grep -rl "$SYMBOL" --include="*.ts" --include="*.js" --include="*.tsx" --include="*.jsx" . 2>/dev/null | grep -vE '\.test\.|\.spec\.|__test__|__mock__|node_modules|\.git' | grep -v "$file" || true)

    # Also check if the file itself is imported (for re-exports / barrel files)
    FILE_IMPORTS=$(grep -rl "$BASENAME" --include="*.ts" --include="*.js" --include="*.tsx" --include="*.jsx" . 2>/dev/null | grep -vE '\.test\.|\.spec\.|__test__|__mock__|node_modules|\.git' | grep -v "$file" || true)

    if [ -z "$NON_TEST_IMPORTS" ] && [ -z "$FILE_IMPORTS" ]; then
      # Check if it's imported in test files (to distinguish "unused" from "test-only")
      TEST_IMPORTS=$(grep -rl "$SYMBOL" --include="*.test.*" --include="*.spec.*" . 2>/dev/null | grep -v node_modules || true)

      if [ -n "$TEST_IMPORTS" ]; then
        echo "⚠️  TEST-ONLY: $SYMBOL (from $file)"
        echo "   Imported in tests but NOT in application code"
        echo "   Test files: $(echo "$TEST_IMPORTS" | head -3 | tr '\n' ', ')"
        UNREACHABLE=$((UNREACHABLE + 1))
      else
        echo "⚠️  UNUSED: $SYMBOL (from $file)"
        echo "   Not imported anywhere (test or application)"
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  done <<< "$EXPORTS"
done

echo ""
echo "=== REACHABILITY SUMMARY ==="
echo "Unreachable (test-only): $UNREACHABLE"
echo "Unused (no imports): $WARNINGS"

if [ "$UNREACHABLE" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo "ALL NEW EXPORTS REACHABLE"
  exit 0
elif [ "$UNREACHABLE" -gt 0 ]; then
  echo ""
  echo "⚠️  $UNREACHABLE export(s) only imported by test files — potentially unwired."
  echo "Verify these are called from actual application code paths."
  exit 1
else
  echo ""
  echo "⚠️  $WARNINGS unused export(s) found (no imports at all)."
  echo "These may be intentional (public API) or dead code."
  exit 0
fi
