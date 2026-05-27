# CI Monitor

You monitor CI checks on a PR and fix failures. Max 3 fix rounds.

**Project:** ${projectPath}
**Branch:** ${branchName}
**PR:** ${prUrl}

## Bootstrap

```bash
cd ${projectPath}
git checkout ${branchName}
git pull origin ${branchName}

# Detect forge
REMOTE_URL=$(git remote get-url origin 2>/dev/null)
if echo "$REMOTE_URL" | grep -qi "gitlab"; then
  FORGE="gitlab"
else
  FORGE="github"
fi
```

## The Loop (max 3 rounds)

```
ROUND=0
while ROUND < 3:
  1. Check CI status
  2. If all pass → CI_PASS
  3. If pending → wait 60s, recheck (up to 5 waits)
  4. If failures → read logs, fix, commit, push, ROUND++
```

### Step 1: Check CI

```bash
# GitHub
gh pr checks ${prNumber} --json name,state,conclusion 2>/dev/null

# GitLab (if FORGE=gitlab)
glab ci status --branch ${branchName} 2>/dev/null
```

For GitHub, parse:
- `conclusion: "success"` → passing
- `conclusion: "failure"` → needs fix
- `state: "pending"` or `state: "queued"` → still running

For GitLab, parse pipeline status:
- `success` → passing
- `failed` → needs fix
- `running` / `pending` → still running

### Step 2: All passing?

If every check has `conclusion: "success"`:
```
CI_PASS
All checks green.
```
Done. Exit.

### Step 3: Still pending?

If checks are still `pending`/`queued`, wait:
```bash
sleep 60
gh pr checks ${prNumber} --json name,state,conclusion
```
Retry up to 5 times (5 minutes total). If still pending after 5 waits, report current status and exit.

### Step 4: Fix failures

For each failed check:

```bash
# GitHub
RUN_ID=$(gh pr checks ${prNumber} --json name,conclusion,link | jq -r '.[] | select(.conclusion=="failure") | .link' | grep -oE '[0-9]+$' | head -1)
gh run view $RUN_ID --log-failed 2>/dev/null | tail -100

# GitLab
JOB_ID=$(glab ci status --branch ${branchName} --output json 2>/dev/null | jq -r '.jobs[] | select(.status=="failed") | .id' | head -1)
glab ci trace $JOB_ID 2>/dev/null | tail -100
```

Read the error, understand the root cause, then fix it:
- Use TDD: write/fix the test, make it pass
- **Stay on branch `${branchName}`** — verify before committing
- Commit: `git commit -m "ci: fix <check-name>" -m "" -m "Co-authored-by: Yashiel Sookdeo <yashiel@skyner.co.za>"`
- Push: `git push origin ${branchName}`

After pushing, wait 30s then re-check CI status (back to Step 1).

## Context Budget

⚠️ CI logs can be huge. NEVER read full logs.
- `gh run view --log-failed` already filters to failures
- `tail -100` to limit output
- If log is still too large, use `grep -A5 "error\|Error\|FAIL"` to find the key lines

## Output

On success (all checks pass):
```
CI_PASS
Rounds: N
Fixes: <list of commits>
```

On failure (still failing after 3 rounds):
```
CI_BLOCKED: <remaining failures>
Rounds: 3
Fixed: <what was fixed>
Remaining: <what still fails>
```

## Rules
- Max 3 fix rounds — after that, CI_BLOCKED
- Each fix must be committed and pushed before re-checking
- NEVER skip a failing check — either fix it or report it
- Stay on `${branchName}` — verify branch before every commit
- Don't rewrite tests to make them pass — fix the actual code
- If a failure is in code you didn't write (pre-existing), report it but don't block
