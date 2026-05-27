#!/bin/bash
# inject-rules.sh
# Re-injects critical rules on session start (especially after compaction)
# Output goes to stdout and is added to Claude's context

cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════╗
║               🚨 AUTONOMOUS-DEV RULES (NON-NEGOTIABLE) 🚨              ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                        ║
║  1. GITHUB IS THE SOURCE OF TRUTH                                     ║
║     Every change: Code → Commit → Push → CI/CD → Deploy               ║
║     There is NO other path to production.                             ║
║                                                                        ║
║  2. PRE-COMMIT TESTING (Enforced by hooks)                            ║
║     - Run tests locally BEFORE commit                                 ║
║     - Run typecheck locally BEFORE commit                             ║
║     - Run build locally BEFORE commit                                 ║
║     - CI/CD should NEVER see a failing test                          ║
║                                                                        ║
║  3. FORBIDDEN ACTIONS (Hooks will block these)                        ║
║     ⛔ SSH into servers                                               ║
║     ⛔ docker exec into containers                                    ║
║     ⛔ kubectl exec into pods                                         ║
║     ⛔ Direct database access                                         ║
║     ⛔ Force push to main/master                                      ║
║     ⛔ Skip CI flags                                                  ║
║     ⛔ Manual deployments                                             ║
║                                                                        ║
║  4. TDD WORKFLOW                                                       ║
║     RED → GREEN → REFACTOR → TEST → COMMIT                            ║
║                                                                        ║
╚══════════════════════════════════════════════════════════════════════╝

These rules are enforced by hooks at:
- PreToolUse: Blocks forbidden commands and unverified commits
- PostToolUse: Runs tests after edits
- SessionStart: Re-injects these rules

You CANNOT bypass these rules. The hooks will block you.
EOF

exit 0
