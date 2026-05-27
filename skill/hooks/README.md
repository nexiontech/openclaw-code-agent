# autonomous-dev Claude Code Hooks

These hooks enforce quality gates via code, not prompts. They run automatically and **cannot be bypassed**.

## Installation

Copy the hooks configuration to your project:

```bash
# Copy hooks scripts
cp -r skills/autonomous-dev/hooks/.claude/hooks /path/to/your/project/.claude/

# Copy settings (or merge with existing)
cp skills/autonomous-dev/hooks/.claude/settings.json /path/to/your/project/.claude/

# Make scripts executable
chmod +x /path/to/your/project/.claude/hooks/*.sh
```

## What's Enforced

| Hook | Event | What It Does |
|------|-------|--------------|
| `pre-commit-gate.sh` | PreToolUse (Bash) | Blocks `git commit` if tests/typecheck fail |
| `post-edit-tests.sh` | PostToolUse (Edit/Write) | Runs tests after file changes |
| `block-shortcuts.sh` | PreToolUse (Bash) | Blocks forbidden commands (ssh, docker exec, etc.) |
| `inject-rules.sh` | SessionStart | Re-injects NO SHORTCUTS rules after compaction |

## Hook Details

### 1. Pre-Commit Gate
Blocks any `git commit` command unless tests pass first.

```
git commit → Hook intercepts → Runs tests → 
  PASS? → Allow commit
  FAIL? → Block with "Tests must pass before commit"
```

### 2. Post-Edit Tests
After any file edit, automatically runs the test suite to catch issues immediately.

### 3. Block Shortcuts
Prevents forbidden commands that bypass proper CI/CD:
- `ssh` into servers
- `docker exec` into containers
- `kubectl exec` into pods
- Direct database commands
- Manual deployments

### 4. Inject Rules
On session start (including after compaction), re-injects critical rules so Claude never "forgets" them.

## Exit Codes

- `Exit 0` → Proceed
- `Exit 2` → Block (reason sent to Claude as feedback)
