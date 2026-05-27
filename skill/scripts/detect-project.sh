#!/bin/bash
# detect-project.sh — Detect project structure and output JSON config
# Usage: ./scripts/detect-project.sh [project-path]
# Output: JSON config for use by supervisor/quality-gate.sh

set -euo pipefail

PROJECT_PATH="${1:-$(pwd)}"
cd "$PROJECT_PATH"

# Package manager detection
PACKAGE_MANAGER="npm"
INSTALL_CMD="npm install"
TEST_CMD="npm test"
TYPECHECK_CMD="npx tsc --noEmit"
BUILD_CMD="npm run build"

if [ -f "pnpm-lock.yaml" ]; then
  PACKAGE_MANAGER="pnpm"
  INSTALL_CMD="pnpm install"
  TEST_CMD="pnpm test"
  TYPECHECK_CMD="pnpm exec tsc --noEmit"
  BUILD_CMD="pnpm build"
elif [ -f "yarn.lock" ]; then
  PACKAGE_MANAGER="yarn"
  INSTALL_CMD="yarn install"
  TEST_CMD="yarn test"
  TYPECHECK_CMD="yarn tsc --noEmit"
  BUILD_CMD="yarn build"
elif [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then
  PACKAGE_MANAGER="bun"
  INSTALL_CMD="bun install"
  TEST_CMD="bun test"
  TYPECHECK_CMD="bunx tsc --noEmit"
  BUILD_CMD="bun run build"
fi

# Monorepo detection
MONOREPO=false
if [ -f "pnpm-workspace.yaml" ] || [ -f "lerna.json" ] || [ -f "nx.json" ]; then
  MONOREPO=true
fi
if [ -f "package.json" ] && command -v jq &>/dev/null; then
  if jq -e '.workspaces' package.json &>/dev/null; then
    MONOREPO=true
  fi
fi

# Adjust commands for monorepo
TEST_CMD_ROOT="$TEST_CMD"
TYPECHECK_CMD_ROOT="$TYPECHECK_CMD"
if [ "$MONOREPO" = "true" ] && [ "$PACKAGE_MANAGER" = "pnpm" ]; then
  # Per-package (story scope): pnpm test runs in the package dir
  TEST_CMD="pnpm test"
  TYPECHECK_CMD="pnpm exec tsc --noEmit"
  # Root-level (phase/final scope): pnpm -r test respects per-package configs
  TEST_CMD_ROOT="pnpm -r test"
  TYPECHECK_CMD_ROOT="pnpm -r exec tsc --noEmit"
  BUILD_CMD="pnpm -r build"
elif [ "$MONOREPO" = "true" ] && [ "$PACKAGE_MANAGER" = "yarn" ]; then
  TEST_CMD_ROOT="yarn workspaces run test"
  TYPECHECK_CMD_ROOT="yarn workspaces run tsc --noEmit"
fi

# Docker detection
DOCKER=false
DOCKER_BUILD_CMD=""
if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
  DOCKER=true
  DOCKER_BUILD_CMD="docker compose build"
elif [ -f "Dockerfile" ]; then
  DOCKER=true
  IMAGE_NAME=$(basename "$PROJECT_PATH" | tr '[:upper:]' '[:lower:]')
  DOCKER_BUILD_CMD="docker build -t $IMAGE_NAME ."
fi

# TypeScript detection
TYPESCRIPT=false
TSCONFIG=""
if [ -f "tsconfig.json" ]; then
  TYPESCRIPT=true
  TSCONFIG="tsconfig.json"
elif find . -name "tsconfig.json" -not -path "*/node_modules/*" -maxdepth 3 | grep -q .; then
  TYPESCRIPT=true
  TSCONFIG=$(find . -name "tsconfig.json" -not -path "*/node_modules/*" -maxdepth 3 | head -1)
fi

# Override typecheck if not TypeScript
if [ "$TYPESCRIPT" = "false" ]; then
  TYPECHECK_CMD=""
fi

# Check for custom test/build scripts in package.json
if [ -f "package.json" ] && command -v jq &>/dev/null; then
  if jq -e '.scripts.typecheck' package.json &>/dev/null; then
    TYPECHECK_CMD="$PACKAGE_MANAGER run typecheck"
  fi
  if ! jq -e '.scripts.test' package.json &>/dev/null; then
    TEST_CMD=""
  fi
  if ! jq -e '.scripts.build' package.json &>/dev/null; then
    BUILD_CMD=""
  fi
fi

# Output JSON
cat <<EOF
{
  "packageManager": "$PACKAGE_MANAGER",
  "installCmd": "$INSTALL_CMD",
  "testCmd": "$TEST_CMD",
  "testCmdRoot": "$TEST_CMD_ROOT",
  "typecheckCmd": "$TYPECHECK_CMD",
  "typecheckCmdRoot": "$TYPECHECK_CMD_ROOT",
  "buildCmd": "$BUILD_CMD",
  "monorepo": $MONOREPO,
  "docker": $DOCKER,
  "dockerBuildCmd": "$DOCKER_BUILD_CMD",
  "typescript": $TYPESCRIPT,
  "tsconfig": "$TSCONFIG",
  "projectPath": "$PROJECT_PATH"
}
EOF
