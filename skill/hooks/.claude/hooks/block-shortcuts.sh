#!/bin/bash
# block-shortcuts.sh
# Blocks commands that bypass proper CI/CD
# Exit 2 = block, Exit 0 = allow

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Skip if no command
if [ -z "$COMMAND" ]; then
  exit 0
fi

# ============================================
# BLOCKED COMMANDS - These bypass CI/CD
# ============================================

# SSH into servers (hotfixing production)
if echo "$COMMAND" | grep -qE "^ssh\s"; then
  echo "🚨 BLOCKED: SSH into servers is forbidden." >&2
  echo "Fix issues through code → commit → CI/CD → deploy" >&2
  echo "GitHub is the source of truth. No hotfixes." >&2
  exit 2
fi

# Docker exec (patching running containers)
if echo "$COMMAND" | grep -qE "docker\s+(exec|attach)"; then
  echo "🚨 BLOCKED: docker exec/attach is forbidden." >&2
  echo "Don't patch running containers. Fix in code and redeploy." >&2
  exit 2
fi

# Kubectl exec (patching running pods)
if echo "$COMMAND" | grep -qE "kubectl\s+exec"; then
  echo "🚨 BLOCKED: kubectl exec is forbidden." >&2
  echo "Don't patch running pods. Fix in code and redeploy." >&2
  exit 2
fi

# Direct database modifications in production
if echo "$COMMAND" | grep -qE "(psql|mysql|mongo|redis-cli).*prod"; then
  echo "🚨 BLOCKED: Direct production database access is forbidden." >&2
  echo "Use migrations and proper deployment processes." >&2
  exit 2
fi

# Manual deployment commands
if echo "$COMMAND" | grep -qE "(kubectl\s+apply|helm\s+install|terraform\s+apply).*--auto-approve"; then
  echo "🚨 BLOCKED: Manual deployments are forbidden." >&2
  echo "Deployments must go through CI/CD pipeline." >&2
  exit 2
fi

# Force push to main/master
if echo "$COMMAND" | grep -qE "git\s+push.*(-f|--force).*(main|master)"; then
  echo "🚨 BLOCKED: Force push to main/master is forbidden." >&2
  echo "Use proper PR workflow." >&2
  exit 2
fi

# Push directly to main/master (should use PR)
if echo "$COMMAND" | grep -qE "git\s+push\s+(origin\s+)?(main|master)$"; then
  echo "🚨 BLOCKED: Direct push to main/master is forbidden." >&2
  echo "Create a feature branch and use PR workflow." >&2
  exit 2
fi

# Skip CI flags
if echo "$COMMAND" | grep -qE "\[skip ci\]|\[ci skip\]|--no-verify"; then
  echo "🚨 BLOCKED: Skipping CI is forbidden." >&2
  echo "All changes must pass CI/CD pipeline." >&2
  exit 2
fi

# Curl/wget to modify production
if echo "$COMMAND" | grep -qE "(curl|wget).*(POST|PUT|DELETE|PATCH).*prod"; then
  echo "🚨 BLOCKED: Direct API calls to production are forbidden." >&2
  echo "Changes must go through proper deployment." >&2
  exit 2
fi

# All checks passed
exit 0
