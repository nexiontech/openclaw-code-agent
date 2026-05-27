#!/bin/bash
# anti-pattern-scan.sh — Scan changed files for known dangerous patterns
#
# Reads anti-patterns.json and greps changed files for each pattern.
# Projects build this file over time as bugs are discovered — turning incidents into prevention.
#
# Usage: ./scripts/anti-pattern-scan.sh [base-branch] [anti-patterns-file]
# Default base: main | Default file: anti-patterns.json
#
# anti-patterns.json format:
# [
#   {
#     "pattern": "useEffect.*toast.*\\[.*toast",
#     "description": "Unstable hook return in useEffect deps causes infinite re-render",
#     "severity": "critical",
#     "filePattern": "*.tsx"
#   }
# ]
#
# Exit 0 = no anti-patterns found
# Exit 1 = critical anti-pattern detected
# Exit 0 + warnings = non-critical patterns found

set -u

BASE="${1:-main}"
PATTERNS_FILE="${2:-anti-patterns.json}"
CRITICAL=0
WARNINGS=0

if [ ! -f "$PATTERNS_FILE" ]; then
  echo "No anti-patterns file at $PATTERNS_FILE — skipping"
  exit 0
fi

if ! jq empty "$PATTERNS_FILE" 2>/dev/null; then
  echo "ERROR: $PATTERNS_FILE is not valid JSON"
  exit 1
fi

COUNT=$(jq 'length' "$PATTERNS_FILE")
if [ "$COUNT" -eq 0 ]; then
  echo "Anti-patterns file is empty — skipping"
  exit 0
fi

# Get changed files
CHANGED_FILES=$(git diff "$BASE" --name-only --diff-filter=AMR 2>/dev/null || true)
if [ -z "$CHANGED_FILES" ]; then
  echo "No changed files to scan"
  exit 0
fi

echo "=== ANTI-PATTERN SCAN ==="
echo "Patterns: $COUNT | Changed files: $(echo "$CHANGED_FILES" | wc -l | tr -d ' ')"
echo ""

for i in $(seq 0 $(($COUNT - 1))); do
  PATTERN=$(jq -r ".[$i].pattern" "$PATTERNS_FILE")
  DESC=$(jq -r ".[$i].description // \"Unknown anti-pattern\"" "$PATTERNS_FILE")
  SEVERITY=$(jq -r ".[$i].severity // \"warning\"" "$PATTERNS_FILE")
  FILE_PATTERN=$(jq -r ".[$i].filePattern // \"*\"" "$PATTERNS_FILE")

  # Filter changed files by filePattern
  MATCHING_FILES=""
  for f in $CHANGED_FILES; do
    case "$f" in
      $FILE_PATTERN) MATCHING_FILES="$MATCHING_FILES $f" ;;
      # Also match by extension
      *) 
        EXT_PATTERN=$(echo "$FILE_PATTERN" | sed 's/^\*//')
        case "$f" in
          *$EXT_PATTERN) MATCHING_FILES="$MATCHING_FILES $f" ;;
        esac
        ;;
    esac
  done

  [ -z "$MATCHING_FILES" ] && continue

  # Scan matching files for the pattern
  HITS=""
  for f in $MATCHING_FILES; do
    [ -f "$f" ] || continue
    MATCH=$(grep -nE "$PATTERN" "$f" 2>/dev/null || true)
    if [ -n "$MATCH" ]; then
      HITS="$HITS
$f:$MATCH"
    fi
  done

  if [ -n "$HITS" ]; then
    if [ "$SEVERITY" = "critical" ]; then
      echo "❌ CRITICAL: $DESC"
      CRITICAL=$((CRITICAL + 1))
    else
      echo "⚠️  WARNING: $DESC"
      WARNINGS=$((WARNINGS + 1))
    fi
    echo "   Pattern: $PATTERN"
    echo "$HITS" | head -10 | sed 's/^/   /'
    echo ""
  fi
done

echo "=== ANTI-PATTERN SUMMARY ==="
echo "Critical: $CRITICAL | Warnings: $WARNINGS"

if [ "$CRITICAL" -gt 0 ]; then
  echo "BLOCKED: $CRITICAL critical anti-pattern(s) detected"
  exit 1
else
  if [ "$WARNINGS" -gt 0 ]; then
    echo "PASSED with $WARNINGS warning(s)"
  else
    echo "CLEAN — no anti-patterns found"
  fi
  exit 0
fi
