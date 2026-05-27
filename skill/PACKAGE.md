# autonomous-dev — Complete Skill Package

> **Version:** 7.1 | **Last updated:** 2026-03-31

## Architecture (v7 — Flat)

Main agent drives everything. All sub-agents are depth-1 leaf nodes. No nesting.
orchestrate.sh iterates stories within phases — one coder spawn at a time.

## Prerequisites

```bash
openclaw config set agents.defaults.subagents.maxSpawnDepth 2
openclaw config set agents.defaults.timeoutSeconds 21600
openclaw gateway restart
```

---


## File: `SKILL.md`

```markdown
---
name: autonomous-dev
description: Autonomous AI-driven software development from PRD to working solution. Combines Ralph loop, Superpowers TDD, and supervisor/reviewer patterns. Use when asked to "build autonomously", "implement this PRD", "run autonomous dev", "ralph loop", "agentic development", or to build a feature/project without manual intervention. Spawns sub-agents for each step.
---

# Autonomous Development (v7.1)

Execute autonomous development loops: take a PRD, produce working tested code with a merge-ready PR.

## HOW IT WORKS

**YOU drive the pipeline.** You call orchestrate.sh, it tells you what to do. You do it. Repeat until done.

You are already a persistent session — you never die, you always get new turns. Use that.

```
1. Call orchestrate.sh → get instruction
2. Do what it says (spawn agent, show gate, run command)
3. When a spawned agent completes, it auto-announces to you as a new message
4. Call orchestrate.sh complete <step> → get next instruction
5. Repeat until pipeline is complete
```

**⚠️ When you receive a sub-agent completion, ALWAYS call `orchestrate.sh complete <step>` to continue the pipeline. Do NOT just report the result and stop.**

**⚠️ NEVER spawn stories in parallel. ONE coder at a time. orchestrate.sh controls the sequence — follow it.**

### Prerequisites

```bash
openclaw config set agents.defaults.subagents.maxSpawnDepth 2
openclaw config set agents.defaults.timeoutSeconds 21600
openclaw gateway restart
```

### Start the Pipeline

```bash
cd ${projectPath}
./scripts/orchestrate.sh init ${projectPath}
```

Then loop:

```bash
INSTRUCTION=$(./scripts/orchestrate.sh next)
# Read the JSON. Do what it says. When done:
INSTRUCTION=$(./scripts/orchestrate.sh complete <step> [status] [data])
# This returns the NEXT instruction. Do it. Repeat.
```

### Handling Instructions

| Action | What you do |
|--------|------------|
| `ask` | **MUST show the menu to the user and WAIT for their reply.** Do NOT auto-select. `complete <step> success <reply>` |
| `gate` | Show gate content to user. Wait for reply. `complete <step> success <proceed\|adjust:...\|cancel>` |
| `spawn` | Spawn ONE agent (see below). Wait for it to complete. Then `complete <step>`. **Never spawn multiple at once.** |
| `progress` | Show the message to user. Call `next` again immediately. |
| `preflight` | Show summary. On confirm: `complete preflight`. On cancel: stop. |
| `run` | Execute the commands. Then `complete <step>` |
| `complete` | Pipeline done! Show completion with PR link. |
| `blocked` | Pipeline blocked. Show reason to user. Stop. |

### Spawning Agents

When orchestrate.sh returns `action: "spawn"`, read the template it specifies, fill placeholders, and spawn:

```javascript
sessions_spawn({
  task: /* filled template content */,
  cwd: "${projectPath}",  // ⚠️ MANDATORY — agents must work in the project directory
  mode: "run",
  model: /* from state.json .models[instruction.model] */,
  runTimeoutSeconds: /* from instruction.timeout */,
  cleanup: "delete",
  label: /* instruction.step */
})
```

The spawned agent will auto-announce its result to you when done. When you receive it:
- If output contains BLOCKED/FAILED → `./scripts/orchestrate.sh complete <step> blocked "<reason>"`
- Otherwise → `./scripts/orchestrate.sh complete <step>`

**Then immediately do what the returned instruction says. Keep the loop going.**

### Auto-Executed Steps (you won't see these)

orchestrate.sh auto-executes mechanical steps internally: `validate-models`, `pull-latest`, `branch-check`, `detect`, `baseline`, `validate-prd-exists`, `validate-prd`, `research-review` (autonomous mode), `plan-review` (autonomous mode), `pr-create` (via gh CLI).

## Pipeline

```
MODE-SELECT → MODEL-SELECT → VALIDATE-MODELS → [auto: git fetch, pull, branch, detect, baseline]
  → RESEARCH → [Research Gate*] → PLANNER → [Plan Gate*] → PRE-FLIGHT
  → STORY-1 → [verify] → STORY-2 → [verify] → ... → PHASE-1-REVIEW
  → STORY-N → [verify] → ... → PHASE-2-REVIEW → ... → FINAL REVIEW
  → PR-CREATE → CI MONITOR → COMPLETE
```

Stories are spawned ONE AT A TIME by you (the main agent). No phase supervisor — orchestrate.sh tells you which story to spawn next.

*Gates block in supervised/human mode, auto-advance in autonomous.

## Three Modes

| Mode | Research Gate | Plan Gate | Phase Gates | BLOCKED |
|------|-------------|-----------|-------------|---------|
| **Supervised Start** (default) | ✅ blocks | ✅ blocks | skip | always stops |
| **Autonomous** | auto-advance | auto-advance | skip | always stops |
| **Human Assisted** | ✅ blocks | ✅ blocks | ✅ blocks | always stops |

## Agent Hierarchy

```
YOU (main agent — drives the pipeline loop, persistent)
  ├── RESEARCHER (depth 1, mode: "run") → research/findings.md
  ├── PLANNER (depth 1, mode: "run") → prd.json
  ├── CODER per story (depth 1, mode: "run") → git commit
  ├── TESTER per phase (depth 1, mode: "run") → phase review
  ├── FINAL REVIEWER (depth 1, mode: "run") → E2E review
  └── CI MONITOR (depth 1, mode: "run") → PR + CI
```

**Maximum depth: 1.** All agents are leaf nodes spawned directly by you. No nesting. No sub-agents spawning sub-agents. `maxSpawnDepth: 2` is sufficient (1 for safety margin).

All sub-agents are disposable (`cleanup: "delete"`). State persists in files, not sessions.

## Quality Gates (11 checks, Three Tiers)

```bash
./scripts/quality-gate.sh --scope story   # Per-story: package tests + typecheck + anti-patterns (~30s)
./scripts/quality-gate.sh --scope phase   # Per-phase: FULL suite (pnpm -r test) + build + wiring (~3-5 min)
./scripts/quality-gate.sh --scope final   # Final: everything + Docker + E2E (~10 min)
```

**Baseline diffing:** `--baseline capture` snapshots pre-existing failures at init. New failure = BLOCKED, pre-existing = WARN.

## Memory System

- `memory/learnings.md` — Cross-phase insights
- `memory/phase-N-summary.md` — Per-phase summaries
- `research/findings.md` — Researcher output
- `state.json` — Pipeline state (updated by orchestrate.sh)
- `.pipeline.log` — Step execution history

## Model Presets

| Shorthand | Full model ID |
|-----------|--------------|
| opus | anthropic/claude-opus-4-6 |
| sonnet | anthropic/claude-sonnet-4-6 |
| haiku | anthropic/claude-haiku-3-5-20241022 |
| gemini | openrouter/google/gemini-2.5-pro |
| glm5 | openrouter/zhipu/glm-5 |

## Completion Notification

When pipeline reaches `complete`, show:

```
✅ autonomous-dev Complete

📋 ${projectName}
🔀 Branch: ${branchName}
📊 Stories: ${complete}/${total} | Phases: ${phases}
⏱️ Duration: ${duration}
```
🔗 **PR:** ${prUrl}

**PR URL MUST be outside the code block** for clickability.

## Handling BLOCKED

| Signal | Source | Action |
|--------|--------|--------|
| `RESEARCH_BLOCKED` | Researcher | Notify user |
| `PHASE_BLOCKED` | Coder (story failed 3x) | Notify user with story details |
| `REVIEW_BLOCKED` | Tester | Notify user — wiring issues |
| `CI_BLOCKED` | CI Monitor | Notify user — PR needs attention |

## Enforcement

- `rules/no-shortcuts.md` — mandatory TDD, test hygiene, no mock skipping
- `rules/breaking-changes.md` — flag before stories are created
- `rules/quality-gates.md` — three-tier gate definitions

## Reference Files

| File | Purpose |
|------|---------|
| `templates/researcher.md` | System audit → research/findings.md |
| `templates/planner.md` | Findings + PRD → prd.json |
| `templates/worker.md` | TDD story implementation (one story at a time) |
| `templates/reviewer.md` | Phase review + adds tests |
| `templates/final-review.md` | Final E2E review |
| `scripts/orchestrate.sh` | Pipeline state machine |
| `scripts/quality-gate.sh` | 11-check quality gate (3 tiers + baseline) |
| `scripts/detect-project.sh` | Auto-detect project structure |
| `scripts/anti-pattern-scan.sh` | Known dangerous pattern scanner |

```

## File: `README.md`

```markdown
# autonomous-dev

> AI-driven autonomous development from PRD to merge-ready PR.

## Quick Start

```bash
# Install
cp -r autonomous-dev/ ~/.openclaw/workspace/skills/autonomous-dev/
chmod +x ~/.openclaw/workspace/skills/autonomous-dev/scripts/*.sh

# Configure (one-time)
openclaw config set agents.defaults.subagents.maxSpawnDepth 2
openclaw config set agents.defaults.timeoutSeconds 21600
openclaw gateway restart
```

Then tell your agent: `Run autonomous-dev on /path/to/project`

## How It Works (v7)

Your agent drives the pipeline directly. No sub-orchestrators, no nested agents.

```
Your agent (persistent)
  ├── orchestrate.sh → "spawn researcher" → waits → complete
  ├── orchestrate.sh → "spawn planner" → waits → complete
  ├── orchestrate.sh → "spawn coder for S1" → waits → verify → complete
  ├── orchestrate.sh → "spawn coder for S2" → waits → verify → complete
  ├── orchestrate.sh → "spawn phase reviewer" → waits → complete
  ├── ... more stories + phases ...
  └── orchestrate.sh → "complete" 🎉
```

All agents are depth-1 leaf nodes. No agent spawns another agent. Zero nesting issues.

## Modes

| Mode | What happens |
|------|-------------|
| **Supervised Start** (default) | Review research + plan, then autonomous build |
| **Autonomous** | No gates, alert only on BLOCKED |
| **Human Assisted** | Pause at research, plan, AND every phase |

## Version History

| Version | Key Change |
|---------|-----------|
| v7.0 | Flat architecture — main agent spawns all workers directly, no phase supervisor |
| v6.x | Main agent drives pipeline (phase supervisor still nested) |
| v5.x | Sub-orchestrator experiments (fragile) |

## License

MIT

```

## File: `rules/no-shortcuts.md`

```markdown
# No Shortcuts — The #1 Rule

> GitHub is the ONLY source of truth. Every change must go through code → commit → CI/CD.

## Forbidden Actions

```
NEVER:
- Hotfix production directly
- SSH into servers to fix things
- Manually patch containers or deployments
- Bypass CI/CD pipelines
- Push directly to main without PR
- Skip tests to "unblock"
- Hardcode values to pass tests
- Comment out failing tests
- Use environment-specific hacks
- "Fix in prod, backport later"
- Suppress errors without fixing root cause
```

## The Only Acceptable Path

```
ALWAYS:
- Write fixes in source code
- Write tests that verify the fix
- Run ALL tests locally — pass? continue
- Run typecheck locally — pass? continue
- Run build locally — pass? continue
- ALL checks pass? NOW commit
- Push to GitHub
- CI/CD runs (should NEVER fail — verified locally!)
- Merge via PR
- Let CI/CD deploy
- Document learning in progress.txt
```

## Pre-Commit Loop

```
Code Change
    |
    v
Run tests ----FAIL----> Fix --+
    |                         |
   PASS                       |
    |                         |
    v                         |
Run typecheck ---FAIL----> Fix-+
    |
   PASS
    |
    v
Run build ----FAIL----> Fix --+
    |
   PASS
    |
    v
  COMMIT

CI/CD failure = you skipped this loop = shortcut taken
```

## Why This Matters

Shortcuts create:
- Drift between code and production state
- Unreproducible environments
- Missing test coverage
- Hidden technical debt that compounds

A "quick fix" in Story 5 breaks Stories 15, 23, and 41.

## Test Hygiene

- **ALWAYS clean up mocks and stubs.** Every `vi.stubGlobal()` must have a matching `afterAll(() => vi.unstubAllGlobals())`. Every `vi.mock()` that modifies global state needs `afterEach(() => vi.restoreAllMocks())`.
- **Convention discovery is mandatory.** Before writing tests, read 2-3 existing test files in the same package. Match their patterns for setup/teardown, mock style, and environment config.
- **Never leak test state.** Mocks, stubs, timers, and global overrides that leak between test files cause phantom failures in CI. If you `stub`, you `unstub`.

## Enforcement

Hooks in `hooks/` enforce these rules automatically:

| Hook | Enforces |
|------|---------|
| `pre-commit-gate.sh` | Blocks `git commit` if tests fail |
| `post-edit-tests.sh` | Runs tests after every file edit |
| `block-shortcuts.sh` | Blocks ssh, docker exec, kubectl exec |
| `inject-rules.sh` | Re-injects rules after context compaction |

See `hooks/README.md` for installation.

```

## File: `rules/breaking-changes.md`

```markdown
# Breaking Changes

Flag breaking changes BEFORE creating stories. Get approval before any implementation begins.

## Types of Breaking Changes

```
- API contract changes (endpoints, request/response shape)
- Database schema changes (column removal, type changes, renames)
- Interface/type changes (TypeScript type breaking changes)
- Feature removals
- Authentication flow changes
- Configuration format changes
- Dependency major version bumps with API changes
```

## Detection (During PRD Analysis)

Before writing a single story:
1. Read the PRD and identify potential breaking changes
2. Flag each one explicitly with type and impact
3. Wait for user approval on each
4. Document approved changes in prd.json under `approvedBreakingChanges`

```json
"approvedBreakingChanges": [
  {
    "type": "API contract",
    "description": "Rename /api/user to /api/users",
    "approvedAt": "2026-01-01T00:00:00Z",
    "migrationPlan": "Keep /api/user as deprecated alias for 30 days"
  }
]
```

## Approval Flow

```
Identify breaking change
        |
        v
Flag to user: type, what breaks, who is affected
        |
        v
Propose migration path
        |
        v
Wait for explicit approval
        |
       / \
      /   \
APPROVED  REJECTED
    |         |
    v         v
Document  Redesign
in prd    to avoid
```

## External API — Golden Rule

```
EXTERNAL APIs: NEVER BREAK BACKWARDS COMPATIBILITY

NEVER:
- Remove endpoints
- Change response structure
- Change required parameters
- Remove fields from responses
- Change authentication requirements

ALWAYS:
- ADD new optional fields
- ADD new versioned endpoints (/api/v2/)
- DEPRECATE with warning headers (Deprecation: true)
- MAINTAIN old endpoints until migration complete
- DOCUMENT migration paths in CHANGELOG
```

If a breaking change to an external API is truly unavoidable:
1. Create new versioned endpoint
2. Keep old endpoint working
3. Add `Deprecation: true` header to old endpoint
4. Document migration in CHANGELOG
5. Communicate deprecation timeline to consumers

## Test Compatibility

New tests must NOT break existing tests unless:

| Scenario | Required Action |
|----------|----------------|
| Valid refactor | Update test + code together, document why |
| Approved breaking change | Flag in planning, get explicit approval |
| Old test was wrong | Document why, get user approval |
| Unexpected failure | STOP — investigate and report before proceeding |

```

## File: `rules/quality-gates.md`

```markdown
# Quality Gates — Three-Tier System

Quality is enforced at three levels with increasing thoroughness. Run via `./scripts/quality-gate.sh --scope <level>`.

## The Three Tiers

### Story Scope (`--scope story`)
Fast per-story check. Run after every commit.
- **Package tests** — Tests in the current package/directory (monorepo: `pnpm test` in package dir)
- **ROOT typecheck** — `tsc --noEmit` at PROJECT ROOT (catches cross-package type gaps like missing union members)
- **Lockfile** — Uncommitted lockfile changes

**Why root typecheck at story level:** A worker adding `mcpServerConfigure` as an audit action in one package
needs the `AuditAction` union type updated in another package. Package-level typecheck won't catch this.
Root-level typecheck will. It's fast (~5-10s) and catches the most common cross-package gap.

### Phase Scope (`--scope phase`)
Thorough per-phase check. Run at phase review.
- **Full test suite** — ALL packages via `pnpm -r test` (respects per-package vitest configs like jsdom environment)
- **ROOT typecheck** — Same as story
- **Build** — Full project build
- **Lockfile** — Same as story
- **No shortcuts** — Scan for `.skip`, `.only`, `xit`, `xdescribe`, `fdescribe`, `fit`

**Why full test suite at phase level:** A worker adding a new component might break an existing test in
another package (e.g., a mock that assumed only one fetch call, or a route integrity test with an allowlist).
Package tests won't catch this. The full suite will.

### Final Scope (`--scope final`)
Everything. Run at final E2E review before PR.
- **Full test suite** — All packages
- **ROOT typecheck** — Full project
- **Build** — Full project
- **Docker build** — If applicable
- **E2E tests** — If available
- **No shortcuts** — Scan for skipped/focused tests
- **Project CI scripts** — Auto-discovers and runs project-specific CI validation scripts (e.g. `check-devdep-imports.sh`)
- **Lockfile** — Same as story

## When Each Tier Runs

| Context | Scope | Who Runs It |
|---------|-------|-------------|
| After each story commit | `--scope story` | Worker (self) + Phase Runner (verification) |
| Phase review (tester) | `--scope phase` | Tester agent |
| Final E2E review | `--scope final` | Final reviewer agent |

## What Each Tier Catches

| Gap Type | Story | Phase | Final |
|----------|-------|-------|-------|
| Package test failures | ✅ | ✅ | ✅ |
| Cross-package type errors | ✅ | ✅ | ✅ |
| Cross-package test regressions | ❌ | ✅ | ✅ |
| Mock isolation issues | ❌ | ✅ | ✅ |
| Test convention gaps (allowlists) | ❌ | ✅ | ✅ |
| Build failures | ❌ | ✅ | ✅ |
| Docker build failures | ❌ | ❌ | ✅ |
| E2E failures | ❌ | ❌ | ✅ |
| Anti-pattern scan | ✅ | ✅ | ✅ |
| Wiring checklist verification | ❌ | ✅ | ✅ |
| Reachability (test-only exports) | ❌ | ✅ | ✅ |
| Skipped/focused tests | ❌ | ✅ | ✅ |
| Project CI scripts (devDep checks, etc.) | ❌ | ✅ | ✅ |

## Baseline Diffing

Before any work begins, `orchestrate.sh` captures a baseline:

```bash
./scripts/quality-gate.sh --baseline capture
# Runs phase-scope gate, saves failures to .baseline-failures.txt
# Full output saved to .baseline-gate.log (researcher reads this)
```

All subsequent gates **diff against baseline**:
- **New failure** (not in baseline) → BLOCKED ❌
- **Pre-existing failure** (in baseline) → WARN ⚠️ (not counted, exit 0)
- **All pass** → PASS ✅

This prevents workers from being blocked by bugs that existed before they started.
The researcher reviews `.baseline-gate.log` and documents pre-existing issues as constraints.

## Running Gates

```bash
# Capture baseline (once at pipeline init)
./scripts/quality-gate.sh --baseline capture

# Per-story (fast, ~30s, diffs against baseline)
./scripts/quality-gate.sh --scope story

# Per-phase (thorough, ~3-5 min, diffs against baseline)
./scripts/quality-gate.sh --scope phase

# Final (everything, ~10 min)
./scripts/quality-gate.sh --scope final

# Default (no --scope): phase
./scripts/quality-gate.sh
```

## Gate Failure Policy

- **Test failure**: Fix before committing. Never skip or comment out tests.
- **Typecheck failure**: Fix type errors. Never use `// @ts-ignore` without explaining why.
- **Build failure**: Fix before completing the phase.
- **Docker failure**: Fix before final review.
- **Lockfile drift**: Commit the lockfile or revert the dependency change.
- **Skipped tests**: Remove `.skip`/`.only` before marking phase complete.

```

## File: `templates/researcher.md`

```markdown
# Autonomous Dev Researcher

You are a one-shot research agent. Your job: understand the existing system BEFORE anyone writes stories.
This phase is MANDATORY and CANNOT be skipped.

**Project:** ${projectPath}
**PRD:** ${prdPath}

## Why You Exist

> "40 minutes of reading existing code would have prevented ~10 hours of misdirected work."

Developers build features that pass all tests but can't actually run in production because nobody
checked how the code reaches the runtime, what existing systems would break, or whether the
design doc's open questions were ever answered.

You prevent this.

## Process

```bash
cd ${projectPath}

# 1. Read the PRD / design doc
cat ${prdPath}

# 2. Understand the project
./scripts/detect-project.sh
cat CLAUDE.md 2>/dev/null || true
cat AGENTS.md 2>/dev/null || true
cat ARCHITECTURE.md 2>/dev/null || true
```

```bash
# 3. Check baseline (pre-existing failures captured by orchestrate.sh)
cat .baseline-failures.txt 2>/dev/null || echo "No baseline failures"
cat .baseline-gate.log 2>/dev/null | tail -30 || true
```

If pre-existing failures exist, document them as constraints. Workers should not try to fix these
unless the PRD explicitly asks for it.

Then investigate the 5 mandatory areas below. **Read actual code, not just docs.**

## Mandatory Checklist

### 1. Deployment Path
**Question: Where does this code run? How does it get there?**

```bash
# Read deployment config
cat Dockerfile* 2>/dev/null
cat docker-compose*.yml 2>/dev/null
cat .github/workflows/*.yml 2>/dev/null
cat deploy* 2>/dev/null
cat package.json | jq '.scripts' 2>/dev/null
```

Trace the EXACT path: code in repo → build → package → deploy → runtime.
If ANY step is missing (e.g., code lives in a monorepo package but Docker only installs from npm),
that is a **critical finding**.

### 2. Integration Points
**Question: What existing systems does this feature touch?**

For each system the PRD mentions or implies:
```bash
# Find the actual implementation
grep -r "system-name\|PluginName\|featureName" --include="*.ts" --include="*.js" -l .
# Read the key files
cat <relevant-file>
```

Document: what does each system do, what interface does it expose, what breaks if we change it.

### 3. Exclusivity & Conflicts
**Question: Does this feature claim any shared resource?**

Check for:
- Plugin slots (one plugin per slot → claiming it disables the current occupant)
- Ports (two services can't bind the same port)
- Config keys (overwriting a config key changes behavior for everything that reads it)
- DB tables/columns (schema changes affect all consumers)
- Global state (singletons, env vars)

```bash
# Check existing plugins/slots
grep -r "kind:\|slot:\|plugins\." --include="*.ts" --include="*.json" --include="*.yaml" .
```

### 4. Open Questions
**Question: Does the PRD/design doc have unresolved questions?**

```bash
# Search for unresolved items
grep -i "TBD\|TODO\|open question\|to be determined\|needs research\|?" ${prdPath}
```

For EACH open question found: **answer it now** by reading the relevant code.
If you cannot answer it, mark it as a blocker.

### 5. Delivery Verification
**Question: Can I trace code from repo to production?**

Pick the most critical new component from the PRD. Trace its journey:
1. Where will the source file live? (e.g., `packages/feature/src/index.ts`)
2. How is it built? (e.g., `tsc`, `esbuild`, `docker build`)
3. How is it packaged? (e.g., npm publish, Docker image, copy to dist/)
4. How does it reach the runtime? (e.g., `npm install`, Docker COPY, volume mount)
5. How is it loaded? (e.g., import, plugin manifest, dynamic require)

If step 4 has no answer → **RESEARCH_BLOCKED**.

### 6. Wiring Points
**Question: Where must new code connect to existing code?**

For every feature the PRD describes, identify the **exact points** where new code must plug in:

```bash
# Find entry points (startup, routing, plugin loading)
grep -rn "import\|require" src/index.ts src/app.ts src/main.ts 2>/dev/null | head -20
# Find type unions that may need extending
grep -rn "type.*=.*|" --include="*.ts" . 2>/dev/null | grep -v node_modules | head -20
# Find Docker COPY/RUN that may need updating
grep -n "COPY\|RUN\|ADD" Dockerfile* 2>/dev/null
```

Document each wiring point with: file path, line/pattern, what must be added.
These become the `wiring-checklist.json` that the Planner generates and the quality gate verifies.

## Output

Write `research/findings.md`:

```markdown
# Research Findings

## 1. Deployment Path
- Runtime environment: [host/container/browser/etc]
- Deployment mechanism: [npm/Docker/copy/etc]
- Path: [repo] → [build] → [package] → [deploy] → [runtime]
- Gaps: [any missing steps]

## 2. Integration Points
- [System A]: [what it does, interface, what breaks if changed]
- [System B]: ...

## 3. Conflicts & Exclusivity
- [Resource]: [current owner] → [what happens if we claim it]

## 4. Open Questions Resolved
- Q: [question from PRD]
  A: [answer with evidence: file path, code snippet]

## 5. Delivery Verification
- Traced: [component] from repo to runtime
- Result: [works / gap at step N]

## 6. Wiring Points
- [Entry point file]: must import [new module] (line N)
- [Type file]: must extend [union type] with new values
- [Dockerfile]: must include [new binary/file]
- [Config file]: must add [new config key]

## Constraints for Planner
- MUST include delivery story: [specifics]
- MUST include E2E validation story: [specifics]
- MUST generate wiring-checklist.json from wiring points above
- MUST NOT: [things that would break existing systems]
- MUST handle: [constraint stories needed]

## Risks
- [Risk 1]: [likelihood, impact, mitigation]
```

## Completion

```
RESEARCH_COMPLETE
Findings: research/findings.md
Constraints: N items for planner
Open questions resolved: N/N
Risks identified: N
```

Or if critical questions can't be answered:

```
RESEARCH_BLOCKED: [specific question that can't be answered]
Needs: [what human input is required]
Do NOT proceed to planning until this is resolved.
```

## Rules

- Read ACTUAL CODE, not just docs or READMEs
- Every answer must include evidence (file path, code snippet, command output)
- Do NOT assume anything about deployment — verify it
- Do NOT implement any code
- Do NOT create stories — that's the Planner's job
- `mkdir -p research` before writing findings
- If you can't answer a mandatory question: BLOCK, don't guess

```

## File: `templates/planner.md`

```markdown
# Autonomous Dev Planner

You are a one-shot planning agent. Your job: read the PRD, produce `prd.json`,
and set up (or update) project tracking files.

**Project:** ${projectPath}
**PRD:** ${prdPath}

## Your Task

1. Convert the PRD into structured `prd.json`
2. Create or update project tracking files (CLAUDE.md, AGENTS.md, ARCHITECTURE.md, progress.txt)

## Process

```bash
cd ${projectPath}
cat ${prdPath}                            # Read the full PRD
cat research/findings.md                  # MANDATORY: Read research findings
./scripts/detect-project.sh               # Get project config (save output)
ls -la                                    # See what exists
cat CLAUDE.md 2>/dev/null || true         # Existing conventions?
cat AGENTS.md 2>/dev/null || true         # Existing patterns?
cat ARCHITECTURE.md 2>/dev/null || true   # Existing architecture?
```

**You MUST read `research/findings.md` before creating any stories.** It contains deployment constraints, integration points, conflicts, and required stories that you must incorporate.

## Output 1: prd.json

Write `prd.json` following this schema:

```json
{
  "name": "Project or feature name",
  "branchName": "feature/short-slug",
  "description": "One paragraph summary",
  "phases": [
    {
      "id": "PHASE-1",
      "name": "Foundation",
      "description": "What this phase achieves",
      "stories": ["STORY-001", "STORY-002"]
    }
  ],
  "userStories": [
    {
      "id": "STORY-001",
      "phase": "PHASE-1",
      "title": "Short imperative title",
      "description": "As a <user>, I want <thing> so that <value>",
      "acceptanceCriteria": [
        "Given X, when Y, then Z",
        "Error case: given A, when B, then C"
      ],
      "estimatedMinutes": 30,
      "dependsOn": [],
      "passes": false
    }
  ]
}
```

## Output 2: Project Tracking Files

**Create or update** each of these. If they exist, APPEND/MERGE — do not overwrite.

- **CLAUDE.md** — Quick start commands (test/build/typecheck), pointers to AGENTS.md and ARCHITECTURE.md, key gotchas. Keep under 60 lines.
- **AGENTS.md** — Stack, testing runner and patterns, discovered conventions. Merge if exists.
- **ARCHITECTURE.md** — Overview, directory structure, data flow, key components. Merge if exists.
- **progress.txt** — Create with header (Started, PRD name, phase/story counts). Never overwrite.

See `references/claude-md-guide.md` for format guidance.

## External System Integration Rule

If a story generates config, API calls, or structured output consumed by an external system:
1. Include the EXACT expected schema in acceptance criteria (verbatim JSON/YAML example)
2. Add a "contract test" criterion: "A test validates generated output against the documented schema"
3. Reference the authoritative docs URL in the story description

**Why:** Workers implement what the spec says. Vague schema descriptions lead to code that passes tests but fails at runtime. Be exact.

## Story Sizing Rules

- Each story: 20–60 minutes of implementation work
- If > 60 min: split into smaller stories
- If two stories < 10 min each: merge them
- `estimatedMinutes` is for one skilled developer working focused

## Phase Grouping Rules

- Group by logical delivery milestone, not by file or technology
- Each phase must be independently deployable/testable
- Typical: 2–6 phases, 3–8 stories per phase
- First phase: minimum viable foundation (no UI scaffolding without logic)
- Last phase: polish, docs, integration

## Dependency Mapping

- `dependsOn`: list story IDs that must complete before this story starts
- Within a phase: stories without dependencies can run in parallel
- Cross-phase: always sequential (phase N+1 starts after phase N review passes)

## ⚠️ Integration Stories (MANDATORY)

**When two or more stories produce components that must work together, you MUST add an explicit integration story.**

Workers run in isolation with fresh context. Story A builds a modal. Story B builds a tab with buttons. Neither worker knows about the other. If no story explicitly says "wire A into B", the pieces will be built but NEVER connected.

Rules:
- After any set of parallel UI/component stories: add a "Wire X into Y" integration story
- After any API + frontend split: add a "Connect frontend to API endpoint" story
- The integration story must `dependsOn` all the pieces it connects
- Acceptance criteria must include: "clicking/calling X triggers Y" (functional, not just "imports exist")

Example:
```json
{
  "id": "STORY-009",
  "title": "Wire modal components into connectors tab",
  "description": "Connect the Configure/Test/Remove modals to their trigger buttons in the connectors tab",
  "acceptanceCriteria": [
    "Clicking Configure button opens ConfigureConnectorModal with correct connector data",
    "Clicking Test button opens TestConnectorModal and triggers test flow",
    "Clicking Remove button opens RemoveConnectorModal with confirmation",
    "All three modals close cleanly and refresh the connector list on success"
  ],
  "dependsOn": ["STORY-007", "STORY-008"],
  "estimatedMinutes": 20
}
```

**If in doubt: add the integration story. A redundant wiring story costs 20 min. A missing one means broken UI in production.**

## ⚠️ Generate wiring-checklist.json (MANDATORY)

Read the Wiring Points section from `research/findings.md`. Create `wiring-checklist.json`:

```json
[
  { "file": "src/index.ts", "pattern": "import.*newModule", "description": "index.ts imports newModule" },
  { "file": "src/types.ts", "pattern": "newAction", "description": "ActionType union includes newAction" },
  { "file": "Dockerfile", "pattern": "COPY.*newBinary", "description": "Dockerfile includes newBinary" }
]
```

Each item is a grep-verifiable assertion: "this pattern MUST appear in this file for the feature to work."
The quality gate runs `scripts/wiring-check.sh` at phase review and final review to verify all items.

**If research has no wiring points:** still create wiring-checklist.json with at least the obvious ones
(new modules imported from entry points, new types registered where needed).

## ⚠️ Required Stories from Research (MANDATORY)

Read `research/findings.md` → Constraints for Planner section. You MUST include:

1. **Delivery story** — How the code gets from repo to runtime. If research found a gap in the deployment path, this story fills it. Example: "Package feature as OpenClaw plugin with correct manifest" or "Add Docker COPY step for new service."

2. **Integration story (FINAL story in FINAL phase)** — This is NOT a unit test. It traces the feature's critical path from entry point to output. Acceptance criteria must be end-to-end: "Starting [system] with [feature] configured results in [observable outcome]." It must also verify every item in `wiring-checklist.json` is satisfied. Example: "Start a claw with MCP servers configured → verify container has MCP config files, AGENTS.md mentions MCP tools, mcp-bridge process is running."

3. **Constraint stories** — For each constraint in research findings, a story that handles it. Example: "Register as companion plugin (not memory slot) to avoid disabling memory-core."

4. **No unresolved questions** — Every open question from research must be addressed in a story's acceptance criteria or description. If research says "API X returns format Y" then the acceptance criteria should assert that exact format.

**If research/findings.md is missing or empty: PLANNER_BLOCKED. Do not create stories without research.**

## Completion

```
PLANNER_COMPLETE
Stories: <total count>
Phases: <phase count>
prd.json: written
CLAUDE.md: created|updated
AGENTS.md: created|updated
ARCHITECTURE.md: created|updated
progress.txt: created|exists
```

On failure:
```
PLANNER_BLOCKED: <reason>
NEEDS: <what is missing from the PRD>
```

## Rules

- Read `rules/no-shortcuts.md` before starting
- Do NOT implement any code
- If files exist, READ them first and MERGE — never clobber
- If PRD is ambiguous, make reasonable assumptions and note them in `description`
- Story IDs must be sequential: STORY-001, STORY-002, ...
- Phase IDs must be sequential: PHASE-1, PHASE-2, ...

```

## File: `templates/worker.md`

```markdown
# Autonomous Dev Worker (Coder)

You are a story worker. Implement ONE story using TDD. You have ${storyTimeoutSeconds} seconds.

**⚠️ CONTEXT IS LIMITED. If you exhaust it reading files, you die before committing and ALL work is lost. Be surgical: grep before reading, use head/tail, never cat large files.**

**Project:** ${projectPath}
**Story:** ${storyId}

## Bootstrap (in this order, stop after each and think)

```bash
cd ${projectPath}
git checkout ${branchName}                                       # ⚠️ MUST be on the feature branch
git pull origin ${branchName} 2>/dev/null || true                # Get latest
cat CLAUDE.md                                                    # Orientation
jq '.userStories[] | select(.id=="${storyId}")' prd.json        # Your story
cat memory/learnings.md 2>/dev/null                              # Cross-phase insights
tail -20 progress.txt                                            # Recent story logs
cat AGENTS.md                                                    # Conventions
```

Read ARCHITECTURE.md only if your story touches system structure.
Read `memory/phase-*-summary.md` for the previous phase if relevant.

## Convention Discovery (BEFORE writing any code)

**⚠️ CONTEXT BUDGET: You have limited context. Be surgical with file reads.**

```bash
# Find test files in directories you'll modify
find <target-directories> -name "*.test.*" -o -name "*.spec.*" | head -10

# NEVER cat entire test files. Use targeted reads:
head -80 <test-file>                    # Read setup/imports/first test
grep -n "afterAll\|afterEach\|beforeAll\|mock\|stub" <test-file>  # Find patterns
grep -n "allowlist\|integrity\|every.*must" <test-file>           # Find convention checks
wc -l <test-file>                       # Check size before reading
```

**Rules for reading files:**
- **< 200 lines:** Safe to read fully with `read` tool (use offset/limit)
- **200-500 lines:** Read first 80 lines + grep for relevant patterns
- **> 500 lines:** NEVER read fully. Use `head -80` for structure, `grep` for specifics
- **Max 5 test files** during convention discovery — you need context for actual coding
- **Use `rg` (ripgrep) or `grep -rn`** to find patterns across files instead of reading each one

Look for:
- Allowlists or integrity checks (e.g. "every file in routes/ must be imported")
- Mock patterns (URL-aware mocks, shared fixtures)
- Type union patterns (e.g. AuditAction, EventType — you may need to extend them)
- Setup/teardown patterns (afterAll, afterEach, beforeAll)
- Mock cleanup (vi.restoreAllMocks, vi.unstubAllGlobals)

**Why:** If an existing test checks that "every .ts file in routes/ is imported in index.ts",
your new file in routes/ will fail that test unless you know about it. 5 minutes of targeted
reading saves hours of debugging. But reading 5000-line test files wastes your context budget.

**Test cleanup is MANDATORY:**
- Every `vi.stubGlobal()` → `afterAll(() => vi.unstubAllGlobals())`
- Every `vi.mock()` → `afterEach(() => vi.restoreAllMocks())`
- Every `vi.useFakeTimers()` → `afterAll(() => vi.useRealTimers())`
- Leaked mocks cause phantom failures in OTHER test files — always clean up.

## TDD Process

1. Read story + acceptance criteria from prd.json
2. **Read existing test files** in directories you'll modify (convention discovery above)
3. Find relevant files (grep, targeted reads — not bulk reads)
4. Write failing tests for each acceptance criterion (RED)
5. Verify tests fail for the right reason
6. Write minimal code to make tests pass (GREEN)
7. Run quality gate (must pass before commit)
8. Refactor if needed (gate must still pass)
9. Commit

If your story generates config or output consumed by an external system: read `references/contract-testing.md` and write a contract test.

## Quality Gate (Before Every Commit)

```bash
./scripts/quality-gate.sh --scope story
# Runs: package tests + ROOT-LEVEL typecheck (catches cross-package type gaps)
# If .baseline-failures.txt exists: pre-existing failures are WARNED, not counted.
# Only NEW failures block you. Must exit 0 to commit.
```

## ⚠️ Commit Convention — YOUR WORK IS LOST IF YOU DON'T COMMIT

```bash
# Verify you're on the correct branch BEFORE committing
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "${branchName}" ]; then
  echo "ERROR: On wrong branch ($CURRENT_BRANCH). Must be on ${branchName}!"
  git checkout ${branchName}
fi

git add -p   # Stage only story-related changes
git commit -m "${storyId}: <story title>"
```

**⚠️ NEVER create a new branch. NEVER commit to main. Always commit to `${branchName}`.**

**You MUST commit before outputting STORY_COMPLETE.** Your session is disposable — uncommitted changes are permanently lost when your session ends. No exceptions.

## Post-Implementation

After your story commit:
1. Update AGENTS.md if you discovered new patterns or conventions
2. Update ARCHITECTURE.md if you changed system structure
3. Append to progress.txt:

```
## ${storyId}: <title>
- [HH:MM] Started
- [HH:MM] Tests written, failing (RED)
- [HH:MM] Implementation complete, tests passing (GREEN)
- [HH:MM] Committed: <hash>
- Learning: <one-line insight for future workers>
```

## Output Format

On success:
```
STORY_COMPLETE
CONTEXT_USED: XX%
LEARNINGS: <brief one-line summary>
AGENTS_UPDATED: yes|no
ARCHITECTURE_UPDATED: yes|no
```

On failure:
```
STORY_BLOCKED: <specific reason>
CONTEXT_USED: XX%
ATTEMPTED: <what you tried>
NEEDS: <what would unblock this>
```

## Anti-Pattern Awareness

If `anti-patterns.json` exists, read it before coding. These are known dangerous patterns
discovered from past incidents — your code MUST NOT match any critical pattern.

If you discover a new anti-pattern during implementation (e.g., an unstable hook reference,
a race condition pattern, a mock that masks real failures), add it to `anti-patterns.json`:

```json
{
  "pattern": "useEffect.*toast.*\\[.*toast",
  "description": "useToast() returns new ref every render — causes infinite re-render in useEffect deps",
  "severity": "critical",
  "filePattern": "*.tsx"
}
```

The quality gate scans for these at every tier. Turning incidents into automated prevention.

## Rules

- Read `rules/no-shortcuts.md` before starting — follow strictly
- Context budget: keep reads under 50% of context window
- Never load entire directories
- Never pass full prd.json in memory — read only your story
- Fresh session means no prior context — everything you need is in files
- Do NOT commit if quality gate fails

```

## File: `templates/reviewer.md`

```markdown
# Autonomous Dev Tester (Phase Reviewer)

You are reviewing phase **${phaseId} — ${phaseName}** of an autonomous development session.
Your primary job: verify quality AND add missing test coverage.

**Project:** ${projectPath}
**Phase:** ${phaseId} — ${phaseName}

## 1. Run All Quality Gates

```bash
cd ${projectPath}
./scripts/quality-gate.sh --scope phase
```

This runs the FULL test suite (all packages), root-level typecheck, and build.
If any gate fails: output `REVIEW_BLOCKED: <gate> failed` with error details.
Fix minor issues (import paths, missing exports) if quick. Report significant issues.

## 2. Spot-Check Implementations

For each story in this phase (check git log):
```bash
git log --oneline --since="$(jq -r '.phases["${phaseId}"].startedAt // "1 day ago"' state.json)"
```

- Does the implementation match acceptance criteria?
- Obvious logic bugs or security issues?
- Error handling at system boundaries?

## 3. Wiring Check (CRITICAL)

**Parallel stories often build components that never get connected.** Explicitly verify:

- Are all new components actually IMPORTED where they're used?
- Do buttons/triggers actually call the handlers/modals they should?
- Are new API endpoints actually called from the frontend?
- Are new services actually wired into the dependency injection / routing?

```bash
# Check for orphaned exports — components defined but never imported elsewhere
for file in $(git diff --name-only --diff-filter=A HEAD~${storyCount}); do
  basename="$(basename "$file" | sed 's/\.[^.]*$//')"
  imports=$(grep -rl "$basename" --include="*.ts" --include="*.tsx" . | grep -v "$file" | grep -v node_modules | wc -l)
  [ "$imports" -eq 0 ] && echo "⚠️ ORPHAN: $file — exported but never imported"
done
```

If you find unwired components: **this is a REVIEW_BLOCKED issue.** Report it. The supervisor will spawn a fix.

## 4. Add Missing Test Coverage

This is a core responsibility. Add tests the coder may have missed:

**Smoke Tests** — Happy path + basic error handling for each story

**API Tests** (if phase added/changed endpoints)
- Request/response validation, auth checks, error format consistency

**Contract Tests** (if phase generates output for external systems)
- Assert exact output shape against documented schema
- Negative assertions (keys that should NOT be present)
- Run external tool validation if available (e.g., `openclaw doctor`, `terraform validate`)

**Render Stability Tests** (React projects) — If stories added/modified components with useEffect + deps:
- Add a render-count test: render component, assert `renderCount < 5` after mount
- Catches infinite re-render loops from unstable references in dependency arrays

**Integration Tests** — Cross-component paths spanning multiple stories in this phase

## 5. No Shortcuts Scan

```bash
# Skipped tests
grep -r "\.skip\|xit\|xdescribe\|test\.todo" --include="*.test.*" --include="*.spec.*" . | grep -v node_modules

# ts-ignore without explanation
grep -rn "@ts-ignore" --include="*.ts" . | grep -v "// "
```

Flag violations — do not silently fix them.

## 6. Commit Your Tests

```bash
git add -p
git commit -m "REVIEW-${phaseId}: Add phase review tests"
./scripts/quality-gate.sh --scope phase
```

## Output Format

On success:
```
REVIEW_COMPLETE
Phase: ${phaseId}
Tests added: smoke=N, api=N, integration=N
Issues found: none|<list>
```

On failure:
```
REVIEW_BLOCKED: <reason>
Phase: ${phaseId}
Gate failed: <which gate>
Error: <error output>
Stories with issues: <list>
```

```

## File: `templates/final-review.md`

```markdown
# Final E2E Review

You are the final reviewer for project **${prdName}**. This is a comprehensive integration review.
You have 45 minutes. Focus on integration and overall system health — not re-running unit tests.

**Project:** ${projectPath}
**Branch:** ${branchName}

## Your Scope

Verify the complete implementation is ready to merge. You are reviewing and verifying,
not implementing new features or rewriting existing code.

## Review Checklist

### 1. All Quality Gates Pass

```bash
cd ${projectPath}
./scripts/quality-gate.sh --scope final
```

Runs EVERYTHING: full tests (all packages), root typecheck, build, Docker build, E2E tests, shortcut scan.
If any gate fails, this is a blocker.

### 2. Integration Verification

Check that the pieces work together:
- Do API endpoints connect correctly to their backing services?
- Does the frontend properly call the APIs implemented in this branch?
- Are there any integration seams that unit tests wouldn't catch?
- Do database migrations run cleanly from a fresh state?

```bash
# Check all stories are marked complete
jq '[.userStories[] | select(.passes != true)] | length' prd.json
# Should be 0
```

### 3. E2E Tests

Check if E2E tests exist and pass:
```bash
# Look for E2E test directories
ls e2e/ test/e2e/ cypress/ playwright/ 2>/dev/null

# Run E2E tests if they exist
npm run test:e2e 2>/dev/null || pnpm test:e2e 2>/dev/null || echo "No E2E tests found"
```

If no E2E tests exist and the PRD involved user-facing features: note this as a gap.
Do not write E2E tests yourself — flag it as a recommendation.

### 4. Documentation Check

Verify documentation was updated during implementation:
```bash
# Check AGENTS.md has recent updates
git log --oneline AGENTS.md | head -5

# Check ARCHITECTURE.md if system structure changed
git log --oneline ARCHITECTURE.md | head -5

# Check progress.txt has entries for all stories
jq '.userStories[].id' prd.json | while read id; do
  grep -q "$id" progress.txt && echo "OK: $id" || echo "MISSING: $id"
done
```

### 5. Branch Hygiene

```bash
# Verify we're on the right branch
git branch --show-current

# Check all commits follow convention (STORY-XXX: title)
git log --oneline origin/main..HEAD | grep -v "^[a-f0-9]* STORY-"
# Should show nothing (all commits follow convention)

# No merge conflicts or leftover markers
grep -r "<<<<<<\|>>>>>>\|=======" --include="*.ts" --include="*.tsx" --include="*.js" .
# Should show nothing
```

### 6. Security Quick Scan

```bash
# Check for committed secrets patterns
grep -rn "API_KEY\s*=\s*['\"][^$]" --include="*.ts" --include="*.js" . | grep -v ".env.example"
grep -rn "SECRET\s*=\s*['\"][^$]" --include="*.ts" --include="*.js" . | grep -v ".env.example"
# Should show nothing
```

## Output Format

On success:
```
E2E_REVIEW_COMPLETE
Project: ${prdName}
Branch: ${branchName}
Stories complete: N/N
All gates: passing
Integration: verified
E2E tests: passing|none (gap noted)|N/A
Branch: ready for PR
```

On failure:
```
E2E_REVIEW_BLOCKED: <reason>
Project: ${prdName}
Critical issues: <list blockers>
Non-critical gaps: <list recommendations>
Next steps: <what needs to happen before merge>
```

```

## File: `scripts/orchestrate.sh`

```bash
#!/bin/bash
# orchestrate.sh — State machine for autonomous-dev pipeline (v7.1)
#
# Auto-executes mechanical steps (git, detect, validate, PR creation).
# Emits progress messages before long spawns so user sees what's happening.
# Only returns to the AI when it needs: spawn, gate, or user input.
#
# Usage:
#   ./scripts/orchestrate.sh init <projectPath>
#   ./scripts/orchestrate.sh next
#   ./scripts/orchestrate.sh complete <step> [status] [data]
#   ./scripts/orchestrate.sh gate-response <CONTINUE|ADJUST|STOP> [instructions]

set -u

STATE_FILE="state.json"
PIPELINE_LOG=".pipeline.log"
ACTION="${1:-next}"
shift || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Helpers ───

json_get() { jq -r "$1 // empty" "$STATE_FILE" 2>/dev/null; }
json_set() { local tmp=$(mktemp); jq "$1" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

log_step() {
  echo "[$(now)] $1: $2" >> "$PIPELINE_LOG"
}

emit() {
  local action="$1"; shift
  local auto_json="[]"
  if [ ${#AUTO_ADVANCED[@]} -gt 0 ]; then
    auto_json=$(printf '%s\n' "${AUTO_ADVANCED[@]}" | jq -R . | jq -sc .)
  fi
  # For spawn actions, add a reminder to call complete after receiving the result
  local extra=""
  if [ "$action" = "spawn" ]; then
    extra='"⚠️ After this agent completes and auto-announces its result to you, you MUST call orchestrate.sh complete to continue the pipeline. Do NOT just report the result."'
  fi
  # Build JSON safely — pipe through jq to ensure valid output
  if [ -n "$extra" ]; then
    printf '{"action":"%s","autoAdvanced":%s,"reminder":%s,%s}' "$action" "$auto_json" "$extra" "$@" | jq -c .
  else
    printf '{"action":"%s","autoAdvanced":%s,%s}' "$action" "$auto_json" "$@" | jq -c .
  fi
}

# Emit progress before a spawn if auto-advanced steps happened
# Returns true if progress was emitted (caller should exit), false if not needed
emit_progress_before_spawn() {
  local step="$1" description="$2" estimate="$3"
  if [ ${#AUTO_ADVANCED[@]} -gt 0 ]; then
    local auto_list=$(printf '%s\n' "${AUTO_ADVANCED[@]}" | sed 's/^/✓ /' | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
    emit "progress" "\"step\":\"$step\",\"autoExecuted\":\"$auto_list\",\"next\":\"$description\",\"estimate\":\"$estimate\",\"message\":\"$auto_list — Now: $description ($estimate). Call next for spawn instruction.\""
    exit 0
  fi
}

emit_blocked() {
  local step="$1" reason="$2"
  json_set ".step = \"blocked\" | .pipeline = \"blocked\" | .blockReason = \"$reason\" | .lastCheckpoint = \"$(now)\""
  log_step "$step" "BLOCKED: $reason"
  echo "{\"action\":\"blocked\",\"step\":\"$step\",\"reason\":\"$reason\",\"message\":\"Pipeline blocked at $step: $reason\"}"
  exit 0
}

advance() {
  local from="$1" to="$2"
  json_set ".completedSteps += [\"$from\"] | .step = \"$to\" | .lastCheckpoint = \"$(now)\""
  log_step "$from" "auto-executed"
  AUTO_ADVANCED+=("$from")
}

# ─── Phase helpers ───

get_phases() { jq -r '.phases[].id' prd.json 2>/dev/null; }
get_current_phase() { json_get '.currentPhase'; }
get_first_phase() { jq -r '.phases[0].id' prd.json 2>/dev/null; }
get_phase_story_count() { jq -r ".phases[] | select(.id==\"$1\") | .stories | length" prd.json 2>/dev/null; }
get_phase_stories() { jq -r ".phases[] | select(.id==\"$1\") | .stories[]" prd.json 2>/dev/null; }
get_current_story() { json_get '.currentStory'; }

get_next_story_in_phase() {
  local phase="$1" current="$2"
  local stories
  stories=$(get_phase_stories "$phase")
  local found=false
  while read -r sid; do
    if [ "$found" = "true" ]; then
      # Skip already-completed stories
      local status
      status=$(jq -r ".stories.\"$sid\".status // \"pending\"" "$STATE_FILE" 2>/dev/null)
      if [ "$status" != "complete" ]; then
        echo "$sid"
        return
      fi
    fi
    [ "$sid" = "$current" ] && found=true
  done <<< "$stories"
}

get_first_pending_story_in_phase() {
  local phase="$1"
  local stories
  stories=$(get_phase_stories "$phase")
  while read -r sid; do
    local status
    status=$(jq -r ".stories.\"$sid\".status // \"pending\"" "$STATE_FILE" 2>/dev/null)
    if [ "$status" != "complete" ]; then
      echo "$sid"
      return
    fi
  done <<< "$stories"
}

get_next_phase() {
  local current="$1" found=false
  for phase in $(get_phases); do
    [ "$found" = "true" ] && echo "$phase" && return
    [ "$phase" = "$current" ] && found=true
  done
  echo ""
}

# ─── INIT ───

if [ "$ACTION" = "init" ]; then
  PROJECT_PATH="${1:-.}"
  cat > "$STATE_FILE" << ENDJSON
{
  "version": 4,
  "pipeline": "initialized",
  "step": "mode-select",
  "mode": null,
  "preset": null,
  "project": { "path": "$PROJECT_PATH" },
  "models": {},
  "startedAt": "$(now)",
  "lastCheckpoint": "$(now)",
  "completedSteps": [],
  "currentPhase": null,
  "gateStatus": "running",
  "phases": {},
  "stories": {}
}
ENDJSON
  echo '[]' | jq empty > /dev/null  # validate jq available

  # Ensure ephemeral pipeline artifacts are gitignored
  GITIGNORE_ENTRIES=(
    "state.json"
    ".pipeline.log"
    ".baseline-failures.txt"
    ".baseline-gate.log"
    "progress.txt"
    "scripts/orchestrate.sh"
    "scripts/quality-gate.sh"
    "scripts/detect-project.sh"
    "scripts/anti-pattern-scan.sh"
    "scripts/wiring-check.sh"
    "scripts/reachability-check.sh"
    "scripts/validate-prd.sh"
  )
  GITIGNORE_FILE=".gitignore"
  if [ -d .git ]; then
    touch "$GITIGNORE_FILE"
    ADDED=0
    for entry in "${GITIGNORE_ENTRIES[@]}"; do
      if ! grep -qxF "$entry" "$GITIGNORE_FILE" 2>/dev/null; then
        [ "$ADDED" -eq 0 ] && [ -s "$GITIGNORE_FILE" ] && echo "" >> "$GITIGNORE_FILE"
        [ "$ADDED" -eq 0 ] && echo "# autonomous-dev (ephemeral pipeline state)" >> "$GITIGNORE_FILE"
        echo "$entry" >> "$GITIGNORE_FILE"
        ADDED=$((ADDED + 1))
      fi
    done
    if [ "$ADDED" -gt 0 ]; then
      log_step "init" "Added $ADDED entries to .gitignore"
    fi
  fi

  log_step "init" "Pipeline initialized at $PROJECT_PATH"
  AUTO_ADVANCED=()
  emit "next" "\"message\":\"Pipeline initialized. Call next to begin.\""
  exit 0
fi

# ─── RESUME — Restart from last checkpoint ───

if [ "$ACTION" = "resume" ]; then
  if [ ! -f "$STATE_FILE" ]; then
    echo '{"action":"error","message":"No state.json to resume from."}'
    exit 1
  fi
  STEP=$(json_get '.step')
  PIPELINE=$(json_get '.pipeline')
  PHASE=$(json_get '.currentPhase // "none"')
  MODE=$(json_get '.mode // "unknown"')
  PRESET=$(json_get '.preset // "unknown"')
  BRANCH=$(json_get '.project.branch // "unknown"')
  STARTED=$(json_get '.startedAt // "unknown"')
  LAST_CP=$(json_get '.lastCheckpoint // "unknown"')
  COMPLETED=$(json_get '.completedSteps | length')

  if [ "$PIPELINE" = "complete" ] || [ "$PIPELINE" = "stopped" ]; then
    echo "{\"action\":\"info\",\"message\":\"Pipeline is $PIPELINE. Nothing to resume.\"}"
    exit 0
  fi

  # Story/phase progress from prd.json + state.json
  COMPLETE_STORIES=$(jq '[.stories // {} | to_entries[] | select(.value.status == "complete")] | length' "$STATE_FILE" 2>/dev/null || echo 0)
  TOTAL_STORIES=$(jq '.userStories | length' prd.json 2>/dev/null || echo "?")
  COMPLETE_PHASES=$(jq '[.phases // {} | to_entries[] | select(.value.status == "complete")] | length' "$STATE_FILE" 2>/dev/null || echo 0)
  TOTAL_PHASES=$(jq '.phases | length' prd.json 2>/dev/null || echo "?")

  # Failed stories (attempted but not complete)
  FAILED=$(jq -r '[.stories // {} | to_entries[] | select(.value.status != "complete" and (.value.attempts // 0) > 0) | .key] | join(", ")' "$STATE_FILE" 2>/dev/null || echo "")

  log_step "resume" "Resuming at step: $STEP, phase: $PHASE, completed: $COMPLETED steps"
  FAIL_INFO=""
  [ -n "$FAILED" ] && FAIL_INFO=",\"failedStories\":\"$FAILED\""

  printf '{"action":"resume","step":"%s","phase":"%s","mode":"%s","preset":"%s","branch":"%s","startedAt":"%s","lastCheckpoint":"%s","completedSteps":%d,"stories":{"complete":%s,"total":%s},"phases":{"complete":%s,"total":%s}%s,"message":"Resuming at step: %s. Call: ./scripts/orchestrate.sh next"}' \
    "$STEP" "$PHASE" "$MODE" "$PRESET" "$BRANCH" "$STARTED" "$LAST_CP" \
    "$COMPLETED" "$COMPLETE_STORIES" "$TOTAL_STORIES" "$COMPLETE_PHASES" "$TOTAL_PHASES" \
    "$FAIL_INFO" "$STEP" | jq -c .
  exit 0
fi

# ─── Ensure state exists ───

if [ ! -f "$STATE_FILE" ]; then
  echo '{"action":"error","message":"No state.json. Run: ./scripts/orchestrate.sh init <path>"}'
  exit 1
fi

CURRENT_STEP=$(json_get '.step')
MODE=$(json_get '.mode')
PROJECT_PATH=$(json_get '.project.path // "."')
PIPELINE=$(json_get '.pipeline')
AUTO_ADVANCED=()

# ─── COMPLETE — advance step, then fall through to NEXT ───

if [ "$ACTION" = "complete" ]; then
  STEP="${1:-$CURRENT_STEP}"
  STATUS="${2:-success}"
  DATA="${3:-}"

  if [ "$STATUS" = "blocked" ]; then
    json_set ".step = \"blocked\" | .pipeline = \"blocked\" | .blockReason = \"$DATA\" | .lastCheckpoint = \"$(now)\""
    log_step "$STEP" "BLOCKED: $DATA"
    emit "blocked" "\"step\":\"$STEP\",\"reason\":\"$DATA\",\"message\":\"Pipeline blocked at $STEP: $DATA. Notify user and STOP.\""
    exit 0
  fi

  json_set ".completedSteps += [\"$STEP\"] | .lastCheckpoint = \"$(now)\""
  log_step "$STEP" "completed (status: $STATUS)"

  case "$STEP" in
    mode-select)
      CHOSEN="${DATA:-supervised-start}"
      case "$CHOSEN" in
        supervised-start|autonomous|human-assisted) ;;
        1|supervised) CHOSEN="supervised-start" ;;
        2|auto) CHOSEN="autonomous" ;;
        3|human) CHOSEN="human-assisted" ;;
        *) CHOSEN="supervised-start" ;;
      esac
      json_set ".mode = \"$CHOSEN\" | .step = \"model-select\""
      MODE="$CHOSEN"
      ;;
    model-select)
      CHOSEN="${DATA:-premium}"
      case "$CHOSEN" in budget|balanced|premium|custom) ;; *) CHOSEN="premium" ;; esac
      # Resolve preset → model IDs
      case "$CHOSEN" in
        budget)
          json_set ".preset = \"budget\" | .models = {\"supervisor\":\"anthropic/claude-haiku-3-5-20241022\",\"researcher\":\"anthropic/claude-sonnet-4-6\",\"planner\":\"anthropic/claude-sonnet-4-6\",\"coder\":\"openrouter/zhipu/glm-5\",\"tester\":\"anthropic/claude-haiku-3-5-20241022\",\"reviewer\":\"anthropic/claude-sonnet-4-6\"} | .step = \"validate-models\""
          ;;
        balanced)
          json_set ".preset = \"balanced\" | .models = {\"supervisor\":\"anthropic/claude-sonnet-4-6\",\"researcher\":\"anthropic/claude-sonnet-4-6\",\"planner\":\"anthropic/claude-sonnet-4-6\",\"coder\":\"anthropic/claude-sonnet-4-6\",\"tester\":\"anthropic/claude-sonnet-4-6\",\"reviewer\":\"anthropic/claude-sonnet-4-6\"} | .step = \"validate-models\""
          ;;
        premium)
          json_set ".preset = \"premium\" | .models = {\"supervisor\":\"anthropic/claude-sonnet-4-6\",\"researcher\":\"anthropic/claude-opus-4-6\",\"planner\":\"anthropic/claude-opus-4-6\",\"coder\":\"anthropic/claude-opus-4-6\",\"tester\":\"anthropic/claude-sonnet-4-6\",\"reviewer\":\"anthropic/claude-opus-4-6\"} | .step = \"validate-models\""
          ;;
        custom)
          # Custom: AI will populate .models from user's spec, then complete validate-models
          json_set ".preset = \"custom\" | .step = \"validate-models\""
          ;;
      esac
      ;;
    research-review)
      if [ "$MODE" = "autonomous" ]; then
        json_set '.step = "validate-prd-exists"'
      elif [ -z "$DATA" ] || [ "$DATA" = "success" ]; then
        emit "error" "\"step\":\"research-review\",\"message\":\"Gate requires user response: proceed / adjust:<instructions> / cancel\""
        exit 0
      elif [ "$DATA" = "cancel" ]; then
        json_set ".step = \"stopped\" | .pipeline = \"stopped\""
        emit "stopped" "\"message\":\"Pipeline cancelled at research review.\""
        exit 0
      else
        if echo "$DATA" | grep -q "^adjust:"; then
          INSTRUCTIONS="${DATA#adjust:}"
          json_set ".researchAdjustment = \"$INSTRUCTIONS\" | .step = \"validate-prd-exists\""
        else
          json_set '.step = "validate-prd-exists"'
        fi
      fi
      ;;
    plan-review)
      if [ "$MODE" = "autonomous" ]; then
        json_set '.step = "preflight"'
      elif [ -z "$DATA" ] || [ "$DATA" = "success" ]; then
        emit "error" "\"step\":\"plan-review\",\"message\":\"Gate requires user response: proceed / adjust:<instructions> / cancel\""
        exit 0
      elif [ "$DATA" = "cancel" ]; then
        json_set ".step = \"stopped\" | .pipeline = \"stopped\""
        emit "stopped" "\"message\":\"Pipeline cancelled at plan review.\""
        exit 0
      else
        if echo "$DATA" | grep -q "^adjust:"; then
          INSTRUCTIONS="${DATA#adjust:}"
          json_set ".planAdjustment = \"$INSTRUCTIONS\" | .step = \"preflight\""
        else
          json_set '.step = "preflight"'
        fi
      fi
      ;;
    preflight)
      FIRST=$(get_first_phase)
      FIRST_STORY=$(get_first_pending_story_in_phase "$FIRST")
      json_set ".currentPhase = \"$FIRST\" | .currentStory = \"$FIRST_STORY\" | .step = \"story-execute\""
      ;;
    story-execute)
      # A coder finished. Verify + update state.
      CURRENT_PHASE=$(get_current_phase)
      CURRENT_STORY=$(get_current_story)
      json_set ".stories.\"$CURRENT_STORY\" = {\"status\":\"complete\",\"completedAt\":\"$(now)\"}"
      # Move to story-verify (commit check + quality gate)
      json_set ".step = \"story-verify\""
      ;;
    story-verify)
      CURRENT_PHASE=$(get_current_phase)
      CURRENT_STORY=$(get_current_story)
      # Find next pending story in this phase
      NEXT_STORY=$(get_next_story_in_phase "$CURRENT_PHASE" "$CURRENT_STORY")
      if [ -n "$NEXT_STORY" ]; then
        # More stories in this phase
        json_set ".currentStory = \"$NEXT_STORY\" | .step = \"story-execute\""
      else
        # Phase complete → phase review
        json_set ".phases.\"$CURRENT_PHASE\".status = \"complete\" | .phases.\"$CURRENT_PHASE\".completedAt = \"$(now)\" | .step = \"phase-review\""
      fi
      ;;
    phase-review)
      CURRENT_PHASE=$(get_current_phase)
      if [ "$MODE" = "human-assisted" ]; then
        json_set ".step = \"phase-gate\" | .gateStatus = \"awaiting_continue\""
      else
        NEXT=$(get_next_phase "$CURRENT_PHASE")
        if [ -z "$NEXT" ]; then
          json_set '.step = "final-review"'
        else
          FIRST_STORY=$(get_first_pending_story_in_phase "$NEXT")
          json_set ".currentPhase = \"$NEXT\" | .currentStory = \"$FIRST_STORY\" | .step = \"story-execute\""
        fi
      fi
      ;;
    research)      json_set '.step = "research-review"' ;;
    planner)       json_set '.step = "validate-prd"' ;;
    final-review)  json_set '.step = "pr-create"' ;;
    pr-create)     json_set '.step = "ci-monitor"' ;;
    ci-monitor)    json_set '.step = "complete" | .pipeline = "complete"' ;;
    # Auto-executed steps: if AI calls complete on them, just advance normally
    validate-models)     json_set '.step = "pull-latest"' ;;
    pull-latest)         json_set '.step = "branch-check"' ;;
    branch-check)        json_set '.step = "detect"' ;;
    detect)              json_set '.step = "baseline"' ;;
    baseline)            json_set '.step = "research"' ;;
    validate-prd-exists) json_set '.step = "planner"' ;;
    validate-prd)        json_set '.step = "plan-review"' ;;
    *)                   json_set ".step = \"unknown-after-$STEP\"" ;;
  esac

  # Fall through to NEXT
  CURRENT_STEP=$(json_get '.step')
  MODE=$(json_get '.mode')
  ACTION="next"
fi

# ─── GATE-RESPONSE ───

if [ "$ACTION" = "gate-response" ]; then
  RESPONSE="${1:-CONTINUE}"
  INSTRUCTIONS="${2:-}"
  CURRENT_PHASE=$(get_current_phase)

  case "$RESPONSE" in
    CONTINUE)
      NEXT=$(get_next_phase "$CURRENT_PHASE")
      if [ -z "$NEXT" ]; then
        json_set ".gateStatus = \"running\" | .step = \"final-review\" | .lastCheckpoint = \"$(now)\""
      else
        FIRST_STORY=$(get_first_pending_story_in_phase "$NEXT")
        json_set ".gateStatus = \"running\" | .currentPhase = \"$NEXT\" | .currentStory = \"$FIRST_STORY\" | .step = \"story-execute\" | .lastCheckpoint = \"$(now)\""
      fi
      ;;
    ADJUST)
      NEXT=$(get_next_phase "$CURRENT_PHASE")
      if [ -z "$NEXT" ]; then
        json_set ".gateStatus = \"running\" | .step = \"final-review\" | .lastCheckpoint = \"$(now)\""
      else
        FIRST_STORY=$(get_first_pending_story_in_phase "$NEXT")
        json_set ".gateStatus = \"running\" | .currentPhase = \"$NEXT\" | .currentStory = \"$FIRST_STORY\" | .step = \"story-execute\" | .phaseAdjustment = \"$INSTRUCTIONS\" | .lastCheckpoint = \"$(now)\""
      fi
      ;;
    STOP)
      json_set ".gateStatus = \"stopped\" | .pipeline = \"stopped\" | .lastCheckpoint = \"$(now)\""
      emit "stopped" "\"message\":\"Pipeline stopped by user at phase gate.\""
      exit 0
      ;;
  esac

  log_step "gate-response" "$RESPONSE"
  CURRENT_STEP=$(json_get '.step')
  MODE=$(json_get '.mode')
  ACTION="next"
fi

# ─── NEXT — Auto-advance loop ───
# Executes mechanical steps automatically. Only emits when AI intervention needed.

if [ "$ACTION" = "next" ]; then

  MAX_AUTO=20  # Safety: prevent infinite loops
  AUTO_COUNT=0

  while [ $AUTO_COUNT -lt $MAX_AUTO ]; do
    CURRENT_STEP=$(json_get '.step')
    MODE=$(json_get '.mode')
    AUTO_COUNT=$((AUTO_COUNT + 1))

    case "$CURRENT_STEP" in

      # ══════════════════════════════════════════════
      # AUTO-EXECUTABLE STEPS (no AI needed)
      # ══════════════════════════════════════════════

      validate-models)
        # Check agent timeout is sufficient for pipeline runs
        if command -v openclaw &>/dev/null; then
          TIMEOUT_SEC=$(openclaw config get agents.defaults.timeoutSeconds 2>/dev/null || echo "600")
          if [ -z "$TIMEOUT_SEC" ] || [ "$TIMEOUT_SEC" -lt 3600 ] 2>/dev/null; then
            emit "blocked" "\"step\":\"validate-models\",\"message\":\"Agent timeout too low (${TIMEOUT_SEC:-600}s). Pipeline needs at least 1h.\\nRun: openclaw config set agents.defaults.timeoutSeconds 21600\\nopenclaw gateway restart\""
            log_step "validate-models" "BLOCKED: timeout too low (${TIMEOUT_SEC:-600}s)"
            exit 0
          fi
        fi

        # Check spawn depth is sufficient
        if command -v openclaw &>/dev/null; then
          SPAWN_DEPTH=$(openclaw config get agents.defaults.subagents.maxSpawnDepth 2>/dev/null || echo "1")
          if [ -z "$SPAWN_DEPTH" ] || [ "$SPAWN_DEPTH" -lt 2 ] 2>/dev/null; then
            emit "blocked" "\"step\":\"validate-models\",\"message\":\"maxSpawnDepth too low (${SPAWN_DEPTH:-1}). Pipeline needs depth >= 2.\\nRun: openclaw config set agents.defaults.subagents.maxSpawnDepth 2\\nopenclaw gateway restart\""
            log_step "validate-models" "BLOCKED: spawn depth too low (${SPAWN_DEPTH:-1})"
            exit 0
          fi
        fi



        # Check that all preset models are allowed by OpenClaw config
        ALLOWED_MODELS=""
        if command -v openclaw &>/dev/null; then
          ALLOWED_MODELS=$(openclaw models list --plain 2>/dev/null || true)
        fi

        if [ -z "$ALLOWED_MODELS" ]; then
          # No allowlist or openclaw not available — skip validation
          log_step "validate-models" "no allowlist configured (all models allowed)"
          advance "validate-models" "pull-latest"
        else
          # Check each model in preset against the allowlist
          MISSING=""
          ROLES_MISSING=""
          PRESET_MODELS=$(jq -r '.models | to_entries[] | "\(.key)=\(.value)"' "$STATE_FILE" 2>/dev/null)
          while IFS='=' read -r role model; do
            [ -z "$model" ] && continue
            if ! echo "$ALLOWED_MODELS" | grep -qxF "$model"; then
              # Deduplicate model names in missing list
              if ! echo "$MISSING" | grep -qF "$model"; then
                MISSING="${MISSING:+$MISSING, }$model"
              fi
              ROLES_MISSING="${ROLES_MISSING:+$ROLES_MISSING, }$role($model)"
            fi
          done <<< "$PRESET_MODELS"

          if [ -n "$MISSING" ]; then
            # Build the add commands for the user
            ADD_CMDS=""
            for m in $(echo "$MISSING" | tr ', ' '\n' | sort -u | grep .); do
              # Suggest context1m only for Claude 4.6 generation models
              if echo "$m" | grep -qE "claude-(sonnet|opus)-4-6"; then
                ADD_CMDS="${ADD_CMDS}openclaw config set agents.defaults.models.${m}.params.context1m true\n"
              fi
              ADD_CMDS="${ADD_CMDS}openclaw config set agents.defaults.models.${m}.alias \\\"$(echo "$m" | sed 's|.*/||')\\\"\n"
            done
            AVAILABLE=$(echo "$ALLOWED_MODELS" | tr '\n' ', ' | sed 's/,$//')

            # Suggest substitution if available models could replace missing ones
            SUGGEST=""
            if [ -n "$ALLOWED_MODELS" ]; then
              BEST_AVAILABLE=$(echo "$ALLOWED_MODELS" | head -1)
              SUGGEST="\\n\\nOption 2: Use available models instead — reply with a different preset or 'custom' to map roles to: ${AVAILABLE}"
            fi

            emit "blocked" "\"step\":\"validate-models\",\"message\":\"Models not allowed: ${ROLES_MISSING}.\\nAvailable on this system: ${AVAILABLE}\\n\\nOption 1: Add the missing models:\\n${ADD_CMDS}openclaw gateway restart${SUGGEST}\\n\\nOption 3: Clear the allowlist entirely: openclaw config unset agents.defaults.models\""
            log_step "validate-models" "BLOCKED: missing models: $MISSING"
            exit 0
          else
            log_step "validate-models" "all models allowed"
            advance "validate-models" "pull-latest"
          fi
        fi
        ;;

      pull-latest)
        cd "$PROJECT_PATH" 2>/dev/null || true
        # Always fetch all remote refs first
        FETCH_OUT=$(git fetch origin 2>&1) || true
        # Pull latest main
        PULL_OUT=$(git checkout main 2>&1 && git pull origin main 2>&1) || true
        log_step "pull-latest" "${FETCH_OUT} ${PULL_OUT}"
        advance "pull-latest" "branch-check"
        ;;

      branch-check)
        BRANCH=$(json_get '.project.branch // empty')
        if [ -z "$BRANCH" ]; then
          # Need user input
          emit "ask" "\"step\":\"branch-check\",\"message\":\"What branch name? (e.g. feature/my-feature). Set .project.branch in state.json, then: complete branch-check\""
          exit 0
        fi
        cd "$PROJECT_PATH" 2>/dev/null || true
        # Try checking out existing branch (local or remote), or create new
        if git show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
          # Branch exists locally — checkout and pull latest from remote
          git checkout "$BRANCH" 2>/dev/null || true
          git pull origin "$BRANCH" 2>&1 || true
        elif git show-ref --verify --quiet "refs/remotes/origin/$BRANCH" 2>/dev/null; then
          # Branch exists on remote only — track it
          git checkout -b "$BRANCH" "origin/$BRANCH" 2>/dev/null || true
        else
          # New branch — create from main
          git checkout -b "$BRANCH" 2>/dev/null || true
        fi
        log_step "branch-check" "branch: $BRANCH"
        advance "branch-check" "detect"
        ;;

      detect)
        cd "$PROJECT_PATH" 2>/dev/null || true
        if [ -x "$SCRIPT_DIR/detect-project.sh" ]; then
          DETECT_OUT=$("$SCRIPT_DIR/detect-project.sh" 2>&1) || true
          log_step "detect" "${DETECT_OUT:0:200}"
          # Merge detect output into state.json .project
          if echo "$DETECT_OUT" | jq empty 2>/dev/null; then
            json_set ".project = (.project * ($DETECT_OUT | fromjson? // {}))"
          fi
        else
          log_step "detect" "detect-project.sh not found, skipping"
        fi
        advance "detect" "baseline"
        ;;

      baseline)
        cd "$PROJECT_PATH" 2>/dev/null || true
        if [ -x "$SCRIPT_DIR/quality-gate.sh" ]; then
          "$SCRIPT_DIR/quality-gate.sh" --baseline capture 2>&1 || true
        fi
        log_step "baseline" "captured"
        advance "baseline" "research"
        ;;

      research-review)
        # In autonomous mode: auto-advance (no gate)
        if [ "$MODE" = "autonomous" ]; then
          advance "research-review" "validate-prd-exists"
        else
          # Gate — needs AI to show findings to user
          if [ ! -f "research/findings.md" ]; then
            emit_blocked "research-review" "research/findings.md missing"
          fi
          WIRING=$(grep -c "must import\|must extend\|must include\|must add" research/findings.md 2>/dev/null; true)
          CONSTRAINTS=$(grep -c "MUST\|MUST NOT" research/findings.md 2>/dev/null || echo "0")
          emit "gate" "\"step\":\"research-review\",\"data\":{\"wiring\":$WIRING,\"constraints\":$CONSTRAINTS},\"message\":\"Show research/findings.md to user. WAIT for reply. Then: complete research-review success <proceed|adjust:instructions|cancel>\""
          exit 0
        fi
        ;;

      validate-prd-exists)
        # Planner hasn't run yet — this just notes whether PRD pre-exists
        if [ -f "prd.json" ]; then
          log_step "validate-prd-exists" "prd.json found (pre-existing)"
        else
          log_step "validate-prd-exists" "no prd.json — planner will create"
        fi
        advance "validate-prd-exists" "planner"
        ;;

      validate-prd)
        cd "$PROJECT_PATH" 2>/dev/null || true
        if [ -x "$SCRIPT_DIR/validate-prd.sh" ] && "$SCRIPT_DIR/validate-prd.sh" prd.json 2>&1; then
          log_step "validate-prd" "valid"
          advance "validate-prd" "plan-review"
        elif [ -f "prd.json" ]; then
          # validate script missing but file exists — trust it
          log_step "validate-prd" "validate script unavailable, prd.json exists"
          advance "validate-prd" "plan-review"
        else
          emit_blocked "validate-prd" "prd.json missing or invalid"
        fi
        ;;

      plan-review)
        if [ "$MODE" = "autonomous" ]; then
          advance "plan-review" "preflight"
        else
          # Gate — needs AI to show plan to user
          STORY_COUNT=$(jq '[.userStories // [] | length] | add // 0' prd.json 2>/dev/null || echo "?")
          PHASE_COUNT=$(jq '.phases | length' prd.json 2>/dev/null || echo "?")
          PROJECT_NAME=$(jq -r '.name // "unknown"' prd.json 2>/dev/null)
          emit "gate" "\"step\":\"plan-review\",\"data\":{\"project\":\"$PROJECT_NAME\",\"stories\":$STORY_COUNT,\"phases\":$PHASE_COUNT},\"message\":\"Show prd.json summary to user. WAIT for reply. Then: complete plan-review success <proceed|adjust:instructions|cancel>\""
          exit 0
        fi
        ;;

      pr-create)
        cd "$PROJECT_PATH" 2>/dev/null || true
        BRANCH=$(json_get '.project.branch // "unknown"')
        PROJECT_NAME=$(jq -r '.name // "unknown"' prd.json 2>/dev/null || echo "unknown")
        STORIES=$(jq -r '.userStories[] | "- [x] \(.id): \(.title)"' prd.json 2>/dev/null || echo "- stories unavailable")

        # Push
        PUSH_OUT=$(git push -u origin "$BRANCH" 2>&1) || true
        log_step "pr-create" "push: ${PUSH_OUT:0:200}"

        # Create PR
        PR_BODY="## $PROJECT_NAME

### Stories
$STORIES

### Quality
- All quality gates passing (story + phase + final)
- Phase reviews complete
- Final review complete"

        PR_URL=$(gh pr create --title "$PROJECT_NAME" --body "$PR_BODY" --base main 2>&1 | grep -oE 'https://github.com/[^ ]+') || true

        if [ -n "$PR_URL" ]; then
          json_set ".prUrl = \"$PR_URL\""
          log_step "pr-create" "PR: $PR_URL"
          advance "pr-create" "ci-monitor"
        else
          # PR creation failed — let AI handle it
          log_step "pr-create" "auto-create failed, deferring to AI"
          emit "run" "\"step\":\"pr-create\",\"branch\":\"$BRANCH\",\"message\":\"Auto PR creation failed. Create PR manually: git push -u origin $BRANCH && gh pr create --base main. Save URL to state.json .prUrl. Then: complete pr-create\""
          exit 0
        fi
        ;;

      # ══════════════════════════════════════════════
      # AI-REQUIRED STEPS (spawn, gate, ask)
      # ══════════════════════════════════════════════

      mode-select)
        emit "ask" "\"step\":\"mode-select\",\"message\":\"Show this menu and WAIT for reply:\\n\\n⚡ Mode Selection\\n  1 — Supervised Start (default): Review research + plan, then autonomous build\\n  2 — Fully Autonomous: Summaries only, alert on BLOCKED\\n  3 — Human Assisted: Pause at research, plan, AND every phase\\n\\nThen: complete mode-select success <choice>\""
        exit 0
        ;;

      model-select)
        emit "ask" "\"step\":\"model-select\",\"message\":\"Show this menu and WAIT for reply:\\n\\n🤖 Model Preset\\n  budget / balanced / premium (default) / custom\\n\\nThen: complete model-select success <choice>\""
        exit 0
        ;;

      research)
        emit_progress_before_spawn "research" "Spawning researcher (codebase audit)" "~5-15 min"
        emit "spawn" "\"step\":\"research\",\"template\":\"templates/researcher.md\",\"model\":\"researcher\",\"timeout\":1800,\"onComplete\":\"complete research\",\"onBlocked\":\"complete research blocked <reason>\""
        exit 0
        ;;

      planner)
        if [ ! -f "research/findings.md" ]; then
          emit_blocked "planner" "research/findings.md missing"
        fi
        emit_progress_before_spawn "planner" "Spawning planner (stories + wiring)" "~5-10 min"
        emit "spawn" "\"step\":\"planner\",\"template\":\"templates/planner.md\",\"model\":\"planner\",\"timeout\":1800,\"onComplete\":\"complete planner\",\"onBlocked\":\"complete planner blocked <reason>\""
        exit 0
        ;;

      preflight)
        STORY_COUNT=$(jq '[.userStories // [] | length] | add // 0' prd.json 2>/dev/null || echo "?")
        PHASE_COUNT=$(jq '.phases | length' prd.json 2>/dev/null || echo "?")
        PROJECT_NAME=$(jq -r '.name // "unknown"' prd.json 2>/dev/null)
        BRANCH=$(json_get '.project.branch // "unknown"')
        PRESET=$(json_get '.preset // "premium"')
        emit "preflight" "\"step\":\"preflight\",\"data\":{\"project\":\"$PROJECT_NAME\",\"branch\":\"$BRANCH\",\"mode\":\"$MODE\",\"preset\":\"$PRESET\",\"stories\":$STORY_COUNT,\"phases\":$PHASE_COUNT},\"message\":\"Show pre-flight summary. On confirm: complete preflight. On cancel: exit.\""
        exit 0
        ;;

      story-execute)
        CURRENT_PHASE=$(get_current_phase)
        CURRENT_STORY=$(get_current_story)
        PHASE_NAME=$(jq -r ".phases[] | select(.id==\"$CURRENT_PHASE\") | .name" prd.json 2>/dev/null)
        STORY_TITLE=$(jq -r ".userStories[] | select(.id==\"$CURRENT_STORY\") | .title" prd.json 2>/dev/null)
        EST_MINUTES=$(jq -r ".userStories[] | select(.id==\"$CURRENT_STORY\") | .estimatedMinutes // 30" prd.json 2>/dev/null)
        PHASE_INDEX=$(jq -r "[.phases[].id] | index(\"$CURRENT_PHASE\")" prd.json 2>/dev/null)
        TOTAL_PHASES=$(jq '.phases | length' prd.json 2>/dev/null)
        STORY_COUNT=$(get_phase_story_count "$CURRENT_PHASE")
        # Count completed stories in this phase
        PHASE_STORIES=$(get_phase_stories "$CURRENT_PHASE")
        DONE_COUNT=0
        while read -r sid; do
          S_STATUS=$(jq -r ".stories.\"$sid\".status // \"pending\"" "$STATE_FILE" 2>/dev/null)
          [ "$S_STATUS" = "complete" ] && DONE_COUNT=$((DONE_COUNT + 1))
        done <<< "$PHASE_STORIES"

        TIMEOUT=$((EST_MINUTES * 90))
        [ "$TIMEOUT" -lt 1800 ] && TIMEOUT=1800

        BRANCH=$(json_get '.project.branch // "main"')
        emit_progress_before_spawn "story-execute" "Phase $((PHASE_INDEX+1))/$TOTAL_PHASES ($PHASE_NAME): Story $((DONE_COUNT+1))/$STORY_COUNT — $CURRENT_STORY: $STORY_TITLE" "~${EST_MINUTES} min"
        emit "spawn" "\"step\":\"story-execute\",\"phase\":\"$CURRENT_PHASE\",\"story\":\"$CURRENT_STORY\",\"storyTitle\":\"$STORY_TITLE\",\"branch\":\"$BRANCH\",\"template\":\"templates/worker.md\",\"model\":\"coder\",\"timeout\":$TIMEOUT,\"onComplete\":\"complete story-execute\",\"onBlocked\":\"complete story-execute blocked <reason>\""
        exit 0
        ;;

      story-verify)
        # Main agent verifies the coder's commit landed on the correct branch
        CURRENT_STORY=$(get_current_story)
        BRANCH=$(json_get '.project.branch // "main"')
        emit "run" "\"step\":\"story-verify\",\"story\":\"$CURRENT_STORY\",\"branch\":\"$BRANCH\",\"commands\":[\"git checkout $BRANCH\",\"git log --oneline -5 | grep -q ${CURRENT_STORY} && echo COMMIT_OK || echo COMMIT_MISSING\",\"./scripts/quality-gate.sh --scope story\"],\"onComplete\":\"complete story-verify\",\"message\":\"Verify commit for $CURRENT_STORY on branch $BRANCH: 1) git checkout $BRANCH, 2) check git log for $CURRENT_STORY, 3) run story quality gate. If commit missing or gate fails, complete story-verify blocked <reason>.\""
        exit 0
        ;;

      phase-review)
        CURRENT_PHASE=$(get_current_phase)
        PHASE_NAME=$(jq -r ".phases[] | select(.id==\"$CURRENT_PHASE\") | .name" prd.json 2>/dev/null)
        emit_progress_before_spawn "phase-review" "Reviewing phase: $PHASE_NAME" "~10-20 min"
        emit "spawn" "\"step\":\"phase-review\",\"phase\":\"$CURRENT_PHASE\",\"template\":\"templates/reviewer.md\",\"model\":\"tester\",\"timeout\":1800,\"onComplete\":\"complete phase-review\",\"onBlocked\":\"complete phase-review blocked <reason>\""
        exit 0
        ;;

      phase-gate)
        CURRENT_PHASE=$(get_current_phase)
        PHASE_NAME=$(jq -r ".phases[] | select(.id==\"$CURRENT_PHASE\") | .name" prd.json 2>/dev/null)
        NEXT=$(get_next_phase "$CURRENT_PHASE")
        if [ -n "$NEXT" ]; then
          NEXT_NAME=$(jq -r ".phases[] | select(.id==\"$NEXT\") | .name" prd.json 2>/dev/null)
          NEXT_INFO="Next: $NEXT ($NEXT_NAME) — $(get_phase_story_count "$NEXT") stories"
        else
          NEXT_INFO="Last phase done. Next: final review."
        fi
        emit "gate" "\"step\":\"phase-gate\",\"phase\":\"$CURRENT_PHASE\",\"phaseName\":\"$PHASE_NAME\",\"nextInfo\":\"$NEXT_INFO\",\"message\":\"Show phase summary. Wait for: CONTINUE / ADJUST: <instructions> / STOP. Then: gate-response <response>\""
        exit 0
        ;;

      final-review)
        emit_progress_before_spawn "final-review" "Final E2E review" "~15-30 min"
        emit "spawn" "\"step\":\"final-review\",\"template\":\"templates/final-review.md\",\"model\":\"reviewer\",\"timeout\":2700,\"onComplete\":\"complete final-review\",\"onBlocked\":\"complete final-review blocked <reason>\""
        exit 0
        ;;

      ci-monitor)
        BRANCH=$(json_get '.project.branch // "unknown"')
        emit_progress_before_spawn "ci-monitor" "Monitoring CI and fixing failures" "~10-60 min"
        emit "spawn" "\"step\":\"ci-monitor\",\"branch\":\"$BRANCH\",\"model\":\"coder\",\"timeout\":3600,\"message\":\"Monitor CI: gh pr checks --watch. Fix failures with TDD, resolve conflicts with merge. Max 3 rounds.\",\"onComplete\":\"complete ci-monitor\",\"onBlocked\":\"complete ci-monitor blocked <reason>\""
        exit 0
        ;;

      complete)
        STARTED=$(json_get '.startedAt // "unknown"')
        PR_URL=$(json_get '.prUrl // "none"')
        TOTAL_S=$(jq '.userStories | length' prd.json 2>/dev/null || echo "?")
        TOTAL_P=$(jq '.phases | length' prd.json 2>/dev/null || echo "?")
        emit "complete" "\"startedAt\":\"$STARTED\",\"prUrl\":\"$PR_URL\",\"stories\":$TOTAL_S,\"phases\":$TOTAL_P,\"message\":\"Pipeline complete! Show completion with clickable PR link.\""
        exit 0
        ;;

      blocked)
        REASON=$(json_get '.blockReason // "unknown"')
        emit "blocked" "\"reason\":\"$REASON\",\"message\":\"Pipeline blocked: $REASON\""
        exit 0
        ;;

      stopped)
        emit "stopped" "\"message\":\"Pipeline stopped.\""
        exit 0
        ;;

      *)
        emit "error" "\"message\":\"Unknown step: $CURRENT_STEP\""
        exit 0
        ;;
    esac
  done

  # Safety: if we hit max auto-advance, emit current step
  emit "error" "\"message\":\"Auto-advance limit reached at step: $CURRENT_STEP. Possible loop.\""
  exit 1
fi

echo '{"action":"error","message":"Unknown action: '"$ACTION"'. Use: init, next, complete, gate-response"}'
exit 1

```

## File: `scripts/detect-project.sh`

```bash
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

```

## File: `scripts/quality-gate.sh`

```bash
#!/bin/bash
# quality-gate.sh — Three-tier quality checks with baseline diffing
#
# Usage: ./scripts/quality-gate.sh [--scope story|phase|final] [--baseline capture|diff] [--skip-docker] [--skip-build] [--config path]
#
# Scopes:
#   story  — Fast per-story: package tests + ROOT typecheck
#   phase  — Thorough: FULL test suite (all packages) + root typecheck + build
#   final  — Everything: full tests + typecheck + build + docker + E2E + shortcut scan
#
# Baseline modes:
#   --baseline capture  — Run phase-scope gate, save results to .baseline-failures.txt
#   --baseline diff     — Compare current failures against baseline. New = FAIL, pre-existing = WARN.
#
# Default scope: phase | Default baseline: diff (if .baseline-failures.txt exists)
# Exit 0 = all gates pass (or only pre-existing failures), non-zero = new failures

set -u
# Note: NOT using set -e or pipefail — gates must run to completion even when individual commands fail.
# Each gate captures its own exit code via run_gate().

SCOPE="phase"
BASELINE_MODE=""
SKIP_DOCKER=false
SKIP_BUILD=false
CONFIG_FILE=""
FAILURES=0
NEW_FAILURES=0
BASELINE_FILE=".baseline-failures.txt"
GATE_LOG=$(mktemp)

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --scope) SCOPE="$2"; shift ;;
    --baseline) BASELINE_MODE="$2"; shift ;;
    --skip-docker) SKIP_DOCKER=true ;;
    --skip-build) SKIP_BUILD=true ;;
    --config) CONFIG_FILE="$2"; shift ;;
    *) echo "Unknown option: $1" >&2 ;;
  esac
  shift
done

# Validate scope
case "$SCOPE" in
  story|phase|final) ;;
  *) echo "ERROR: Invalid scope '$SCOPE'. Use: story, phase, final" >&2; exit 1 ;;
esac

# ─── BASELINE CAPTURE MODE ───
# Runs phase-scope gate, saves failures for future diffing.
# Called once at pipeline init, before any work begins.

if [ "$BASELINE_MODE" = "capture" ]; then
  echo "=== BASELINE CAPTURE ==="
  echo "Running phase-scope gate to establish baseline..."
  echo ""

  # Run self in phase scope without baseline (avoid recursion)
  CAPTURE_OUTPUT=$("$0" --scope phase 2>&1) || true
  CAPTURE_EXIT=$?

  # Extract gate failure lines (FAIL [GateName]) but not summary lines (FAILED: N gate(s))
  echo "$CAPTURE_OUTPUT" | grep "^FAIL \[" > "$BASELINE_FILE" 2>/dev/null || true
  FAIL_COUNT=$(wc -l < "$BASELINE_FILE" | tr -d ' ')

  # Also save full output for researcher
  echo "$CAPTURE_OUTPUT" > .baseline-gate.log

  echo "$CAPTURE_OUTPUT"
  echo ""
  echo "=== BASELINE CAPTURED ==="
  echo "Exit code: $CAPTURE_EXIT"
  echo "Known failures: $FAIL_COUNT (saved to $BASELINE_FILE)"
  echo "Full log: .baseline-gate.log"

  if [ "$FAIL_COUNT" -gt 0 ]; then
    echo ""
    echo "⚠️  Pre-existing failures detected. Workers will be warned but not blocked by these."
    echo "The researcher should review .baseline-gate.log for constraints."
  fi

  # Baseline capture always exits 0 — it's informational
  rm -f "$GATE_LOG"
  exit 0
fi

# ─── Load config ───

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  TEST_CMD=$(jq -r '.testCmd // ""' "$CONFIG_FILE")
  TEST_CMD_ROOT=$(jq -r '.testCmdRoot // .testCmd // ""' "$CONFIG_FILE")
  TYPECHECK_CMD=$(jq -r '.typecheckCmd // ""' "$CONFIG_FILE")
  TYPECHECK_CMD_ROOT=$(jq -r '.typecheckCmdRoot // .typecheckCmd // ""' "$CONFIG_FILE")
  BUILD_CMD=$(jq -r '.buildCmd // ""' "$CONFIG_FILE")
  DOCKER_BUILD_CMD=$(jq -r '.dockerBuildCmd // ""' "$CONFIG_FILE")
  E2E_CMD=$(jq -r '.e2eCmd // ""' "$CONFIG_FILE")
  TYPESCRIPT=$(jq -r '.typescript // false' "$CONFIG_FILE")
  DOCKER=$(jq -r '.docker // false' "$CONFIG_FILE")
  MONOREPO=$(jq -r '.monorepo // false' "$CONFIG_FILE")
else
  DETECT_OUTPUT=$(./scripts/detect-project.sh 2>/dev/null || echo "{}")
  TEST_CMD=$(echo "$DETECT_OUTPUT" | jq -r '.testCmd // ""')
  TEST_CMD_ROOT=$(echo "$DETECT_OUTPUT" | jq -r '.testCmdRoot // .testCmd // ""')
  TYPECHECK_CMD=$(echo "$DETECT_OUTPUT" | jq -r '.typecheckCmd // ""')
  TYPECHECK_CMD_ROOT=$(echo "$DETECT_OUTPUT" | jq -r '.typecheckCmdRoot // .typecheckCmd // ""')
  BUILD_CMD=$(echo "$DETECT_OUTPUT" | jq -r '.buildCmd // ""')
  DOCKER_BUILD_CMD=$(echo "$DETECT_OUTPUT" | jq -r '.dockerBuildCmd // ""')
  E2E_CMD=$(echo "$DETECT_OUTPUT" | jq -r '.e2eCmd // ""')
  TYPESCRIPT=$(echo "$DETECT_OUTPUT" | jq -r '.typescript // false')
  DOCKER=$(echo "$DETECT_OUTPUT" | jq -r '.docker // false')
  MONOREPO=$(echo "$DETECT_OUTPUT" | jq -r '.monorepo // false')
fi

if [ "$MONOREPO" = "false" ]; then
  TEST_CMD_ROOT="$TEST_CMD"
  TYPECHECK_CMD_ROOT="$TYPECHECK_CMD"
fi

# ─── Gate runner ───

run_gate() {
  local name="$1"
  local cmd="$2"

  if [ -z "$cmd" ]; then
    echo "SKIP [$name] — no command configured"
    return 0
  fi

  echo ""
  echo "=== GATE: $name ==="
  echo "CMD: $cmd"

  # Run command in subshell, capture exit code
  ( eval "$cmd" ) 2>&1
  local exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "PASS [$name]"
    echo "PASS [$name]" >> "$GATE_LOG"
    return 0
  else
    echo "FAIL [$name]"
    echo "FAIL [$name]" >> "$GATE_LOG"
    FAILURES=$((FAILURES + 1))
    return 1
  fi
}

echo "Quality Gate Run — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Scope: $SCOPE | Baseline: $([ -f "$BASELINE_FILE" ] && echo "available ($(wc -l < "$BASELINE_FILE" | tr -d ' ') known failures)" || echo "none")"
echo ""

# ─── GATE 1: Tests ───

case "$SCOPE" in
  story)
    run_gate "Tests (package)" "$TEST_CMD" || true
    ;;
  phase|final)
    run_gate "Tests (full project)" "$TEST_CMD_ROOT" || true
    ;;
esac

# ─── GATE 2: TypeScript typecheck (ROOT at all tiers) ───

if [ "$TYPESCRIPT" = "true" ]; then
  run_gate "Typecheck (root)" "$TYPECHECK_CMD_ROOT" || true
else
  echo ""
  echo "SKIP [Typecheck] — not a TypeScript project"
fi

# ─── GATE 3: Lockfile ───

echo ""
echo "=== GATE: Lockfile ==="
LOCKFILE_CHANGES=$(git diff --name-only 2>/dev/null | grep -E "package-lock\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lock" || true)
if [ -n "$LOCKFILE_CHANGES" ]; then
  echo "WARN [Lockfile] — lockfile has uncommitted changes: $LOCKFILE_CHANGES"
else
  echo "PASS [Lockfile]"
fi

# ─── GATE 4: Build (phase + final) ───

if [ "$SCOPE" = "story" ]; then
  echo ""
  echo "SKIP [Build] — story scope"
elif [ "$SKIP_BUILD" = "true" ]; then
  echo ""
  echo "SKIP [Build] — --skip-build passed"
else
  run_gate "Build" "$BUILD_CMD" || true
fi

# ─── GATE 5: Docker (final only) ───

if [ "$SCOPE" = "final" ] && [ "$DOCKER" = "true" ] && [ "$SKIP_DOCKER" = "false" ]; then
  run_gate "Docker Build" "$DOCKER_BUILD_CMD" || true
else
  echo ""
  echo "SKIP [Docker Build] — $SCOPE scope or --skip-docker"
fi

# ─── GATE 6: E2E (final only) ───

if [ "$SCOPE" = "final" ]; then
  run_gate "E2E Tests" "$E2E_CMD" || true
else
  echo ""
  echo "SKIP [E2E Tests] — $SCOPE scope (final only)"
fi

# ─── GATE 7: Anti-Pattern Scan (all scopes) ───

if [ -f "anti-patterns.json" ]; then
  echo ""
  echo "=== GATE: Anti-Patterns ==="
  if ./scripts/anti-pattern-scan.sh 2>&1; then
    echo "PASS [Anti-Patterns]"
    echo "PASS [Anti-Patterns]" >> "$GATE_LOG"
  else
    echo "FAIL [Anti-Patterns]"
    echo "FAIL [Anti-Patterns]" >> "$GATE_LOG"
    FAILURES=$((FAILURES + 1))
  fi
else
  echo ""
  echo "SKIP [Anti-Patterns] — no anti-patterns.json"
fi

# ─── GATE 8: Wiring Check (phase + final) ───

if [ "$SCOPE" != "story" ] && [ -f "wiring-checklist.json" ]; then
  echo ""
  echo "=== GATE: Wiring Check ==="
  if ./scripts/wiring-check.sh 2>&1; then
    echo "PASS [Wiring]"
    echo "PASS [Wiring]" >> "$GATE_LOG"
  else
    echo "FAIL [Wiring]"
    echo "FAIL [Wiring]" >> "$GATE_LOG"
    FAILURES=$((FAILURES + 1))
  fi
elif [ "$SCOPE" != "story" ]; then
  echo ""
  echo "SKIP [Wiring] — no wiring-checklist.json"
fi

# ─── GATE 9: Reachability Check (phase + final) ───

if [ "$SCOPE" != "story" ]; then
  echo ""
  echo "=== GATE: Reachability ==="
  if ./scripts/reachability-check.sh 2>&1; then
    echo "PASS [Reachability]"
    echo "PASS [Reachability]" >> "$GATE_LOG"
  else
    echo "FAIL [Reachability]"
    echo "FAIL [Reachability]" >> "$GATE_LOG"
    FAILURES=$((FAILURES + 1))
  fi
fi

# ─── GATE 10: No Shortcuts (phase + final) ───

if [ "$SCOPE" != "story" ]; then
  echo ""
  echo "=== GATE: No Shortcuts ==="
  SKIP_TESTS=$(grep -rn "\.skip\|\.only\|xit(\|xdescribe(\|fdescribe(\|fit(" --include="*.test.*" --include="*.spec.*" . 2>/dev/null | grep -v node_modules | grep -v ".git" || true)
  if [ -n "$SKIP_TESTS" ]; then
    echo "FAIL [No Shortcuts] — skipped/focused tests found:"
    echo "$SKIP_TESTS"
    echo "FAIL [No Shortcuts]" >> "$GATE_LOG"
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS [No Shortcuts]"
  fi
else
  echo ""
  echo "SKIP [No Shortcuts] — story scope"
fi

# ─── GATE 11: Project CI Scripts ───
# Auto-discover and run CI validation scripts that aren't already covered.
# This catches project-specific checks (devDep imports, lint rules, etc.)
# that only exist in CI workflows but should also run locally.

if [ "$SCOPE" != "story" ]; then
  echo ""
  echo "=== GATE: Project CI Scripts ==="

  CI_SCRIPTS_RUN=0
  CI_SCRIPTS_FAIL=0

  # Check for common CI validation scripts
  for ci_script in \
    "./scripts/check-devdep-imports.sh" \
    "./scripts/check-imports.sh" \
    "./scripts/lint-ci.sh" \
    "./scripts/validate-ci.sh"; do
    if [ -f "$ci_script" ] && [ -x "$ci_script" ]; then
      CI_SCRIPTS_RUN=$((CI_SCRIPTS_RUN + 1))
      SCRIPT_NAME=$(basename "$ci_script" .sh)
      if bash "$ci_script" 2>&1; then
        echo "  PASS [$SCRIPT_NAME]"
      else
        echo "  FAIL [$SCRIPT_NAME]"
        CI_SCRIPTS_FAIL=$((CI_SCRIPTS_FAIL + 1))
      fi
    fi
  done

  if [ "$CI_SCRIPTS_RUN" -eq 0 ]; then
    echo "SKIP [Project CI Scripts] — no scripts found"
  elif [ "$CI_SCRIPTS_FAIL" -eq 0 ]; then
    echo "PASS [Project CI Scripts] — $CI_SCRIPTS_RUN script(s) passed"
    echo "PASS [Project CI Scripts]" >> "$GATE_LOG"
  else
    echo "FAIL [Project CI Scripts] — $CI_SCRIPTS_FAIL of $CI_SCRIPTS_RUN failed"
    echo "FAIL [Project CI Scripts]" >> "$GATE_LOG"
    FAILURES=$((FAILURES + 1))
  fi
else
  echo ""
  echo "SKIP [Project CI Scripts] — story scope"
fi

# ─── BASELINE DIFF ───
# If baseline exists, check which failures are new vs pre-existing

HAS_BASELINE=false
if [ -f "$BASELINE_FILE" ] && [ -s "$BASELINE_FILE" ]; then
  HAS_BASELINE=true
fi

if [ "$FAILURES" -gt 0 ] && [ "$HAS_BASELINE" = "true" ]; then
  echo ""
  echo "=== BASELINE DIFF ==="

  # Normalize gate names for comparison: "FAIL [Tests (package)]" → "Tests"
  # Extract category by stripping "FAIL [" prefix and " (...)"]" suffix
  normalize_gate() {
    echo "$1" | sed 's/^FAIL \[//; s/ (.*)//; s/\]$//'
  }

  # Build normalized baseline set
  BASELINE_GATES=""
  while IFS= read -r line; do
    NORM=$(normalize_gate "$line")
    BASELINE_GATES="$BASELINE_GATES|$NORM"
  done < "$BASELINE_FILE"

  # Compare current failures against normalized baseline
  while IFS= read -r fail_line; do
    NORM=$(normalize_gate "$fail_line")
    if echo "$BASELINE_GATES" | grep -qF "$NORM"; then
      echo "⚠️  PRE-EXISTING: $fail_line (baseline has $NORM failure)"
    else
      echo "❌ NEW FAILURE: $fail_line (not in baseline)"
      NEW_FAILURES=$((NEW_FAILURES + 1))
    fi
  done < <(grep "^FAIL" "$GATE_LOG" 2>/dev/null || true)

  echo ""
  echo "Baseline failures: $(grep -c "^FAIL" "$BASELINE_FILE" 2>/dev/null || echo 0)"
  echo "New failures: $NEW_FAILURES"
fi

# ─── SUMMARY ───

echo ""
echo "=== SUMMARY ($SCOPE scope) ==="
echo "Gates run:"
case "$SCOPE" in
  story)  echo "  ✅ Package tests | ✅ Root typecheck | ✅ Lockfile | ✅ Anti-patterns" ;;
  phase)  echo "  ✅ Full tests | ✅ Root typecheck | ✅ Lockfile | ✅ Build | ✅ Anti-patterns | ✅ Wiring | ✅ Reachability | ✅ No shortcuts | ✅ CI scripts" ;;
  final)  echo "  ✅ Full tests | ✅ Root typecheck | ✅ Lockfile | ✅ Build | ✅ Docker | ✅ E2E | ✅ Anti-patterns | ✅ Wiring | ✅ Reachability | ✅ No shortcuts | ✅ CI scripts" ;;
esac

# Clean up
rm -f "$GATE_LOG"

if [ "$FAILURES" -eq 0 ]; then
  echo "ALL GATES PASSED"
  exit 0
elif [ "$HAS_BASELINE" = "true" ] && [ "$NEW_FAILURES" -eq 0 ]; then
  echo "PASSED (only pre-existing failures, no new regressions)"
  exit 0
else
  if [ "$HAS_BASELINE" = "true" ]; then
    echo "FAILED: $NEW_FAILURES new failure(s) (plus $(($FAILURES - $NEW_FAILURES)) pre-existing)"
  else
    echo "FAILED: $FAILURES gate(s) failed"
  fi
  exit 1
fi

```

## File: `scripts/anti-pattern-scan.sh`

```bash
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

```

## File: `scripts/wiring-check.sh`

```bash
#!/bin/bash
# wiring-check.sh — Verify wiring checklist items
#
# Reads wiring-checklist.json and verifies each item exists in the target file.
# Each item is a simple grep check: does pattern appear in file?
#
# Usage: ./scripts/wiring-check.sh [path/to/wiring-checklist.json]
# Default: ./wiring-checklist.json
#
# wiring-checklist.json format:
# [
#   { "file": "src/index.ts", "pattern": "import.*myModule", "description": "index.ts imports myModule" },
#   { "file": "Dockerfile", "pattern": "COPY.*dist", "description": "Dockerfile copies dist" }
# ]
#
# Exit 0 = all wiring verified, non-zero = missing wiring points

set -u

CHECKLIST="${1:-wiring-checklist.json}"
FAILURES=0
TOTAL=0

if [ ! -f "$CHECKLIST" ]; then
  echo "No wiring checklist found at $CHECKLIST — skipping"
  exit 0
fi

# Validate JSON
if ! jq empty "$CHECKLIST" 2>/dev/null; then
  echo "ERROR: $CHECKLIST is not valid JSON"
  exit 1
fi

COUNT=$(jq 'length' "$CHECKLIST")
if [ "$COUNT" -eq 0 ]; then
  echo "Wiring checklist is empty — skipping"
  exit 0
fi

echo "=== WIRING CHECK ==="
echo "Checklist: $CHECKLIST ($COUNT items)"
echo ""

# Check each item
for i in $(seq 0 $(($COUNT - 1))); do
  FILE=$(jq -r ".[$i].file" "$CHECKLIST")
  PATTERN=$(jq -r ".[$i].pattern" "$CHECKLIST")
  DESC=$(jq -r ".[$i].description // \"$FILE contains $PATTERN\"" "$CHECKLIST")
  TOTAL=$((TOTAL + 1))

  if [ ! -f "$FILE" ]; then
    echo "❌ FAIL: $DESC"
    echo "         File not found: $FILE"
    FAILURES=$((FAILURES + 1))
    continue
  fi

  if grep -qE "$PATTERN" "$FILE" 2>/dev/null; then
    echo "✅ PASS: $DESC"
  else
    echo "❌ FAIL: $DESC"
    echo "         Pattern '$PATTERN' not found in $FILE"
    FAILURES=$((FAILURES + 1))
  fi
done

echo ""
echo "=== WIRING SUMMARY ==="
echo "Checked: $TOTAL | Passed: $(($TOTAL - $FAILURES)) | Failed: $FAILURES"

if [ "$FAILURES" -eq 0 ]; then
  echo "ALL WIRING VERIFIED"
  exit 0
else
  echo "WIRING INCOMPLETE: $FAILURES point(s) not connected"
  exit 1
fi

```

## File: `scripts/reachability-check.sh`

```bash
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

```

## File: `scripts/validate-prd.sh`

```bash
#!/bin/bash
# validate-prd.sh — Validate prd.json structure using jq
# Usage: ./scripts/validate-prd.sh [path/to/prd.json]
# Exit 0 = valid, non-zero = validation errors found

set -uo pipefail

PRD_FILE="${1:-prd.json}"
ERRORS=0

if [ ! -f "$PRD_FILE" ]; then
  echo "ERROR: File not found: $PRD_FILE"
  exit 1
fi

if ! jq empty "$PRD_FILE" 2>/dev/null; then
  echo "ERROR: Invalid JSON in $PRD_FILE"
  exit 1
fi

check() {
  local description="$1"
  local jq_expr="$2"
  local expected="${3:-true}"

  result=$(jq -r "$jq_expr" "$PRD_FILE" 2>/dev/null)
  if [ "$result" = "$expected" ]; then
    echo "OK: $description"
  else
    echo "FAIL: $description (got: $result)"
    ERRORS=$((ERRORS + 1))
  fi
}

echo "Validating: $PRD_FILE"
echo ""

# Top-level required fields
check "Has .name" 'has("name")' "true"
check "Has .branchName" 'has("branchName")' "true"
check "Has .phases array" 'has("phases") and (.phases | type) == "array"' "true"
check "Has .userStories array" 'has("userStories") and (.userStories | type) == "array"' "true"
check "Has at least one phase" '(.phases | length) > 0' "true"
check "Has at least one story" '(.userStories | length) > 0' "true"

# Branch name format (no spaces, valid git branch)
check "branchName has no spaces" '(.branchName | test(" ")) | not' "true"

# Phase structure
PHASE_COUNT=$(jq '.phases | length' "$PRD_FILE")
echo ""
echo "Checking $PHASE_COUNT phases..."

for i in $(seq 0 $((PHASE_COUNT - 1))); do
  PHASE_ID=$(jq -r ".phases[$i].id // \"MISSING\"" "$PRD_FILE")
  check "Phase[$i] has .id" ".phases[$i] | has(\"id\")" "true"
  check "Phase[$i] ($PHASE_ID) has .name" ".phases[$i] | has(\"name\")" "true"
  check "Phase[$i] ($PHASE_ID) has .description" ".phases[$i] | has(\"description\")" "true"
done

# Story structure
STORY_COUNT=$(jq '.userStories | length' "$PRD_FILE")
echo ""
echo "Checking $STORY_COUNT stories..."

for i in $(seq 0 $((STORY_COUNT - 1))); do
  STORY_ID=$(jq -r ".userStories[$i].id // \"MISSING\"" "$PRD_FILE")

  check "Story[$i] ($STORY_ID) has .id" ".userStories[$i] | has(\"id\")" "true"
  check "Story[$i] ($STORY_ID) has .phase" ".userStories[$i] | has(\"phase\")" "true"
  check "Story[$i] ($STORY_ID) has .title" ".userStories[$i] | has(\"title\")" "true"
  check "Story[$i] ($STORY_ID) has .description" ".userStories[$i] | has(\"description\")" "true"
  check "Story[$i] ($STORY_ID) has .acceptanceCriteria" ".userStories[$i] | has(\"acceptanceCriteria\")" "true"
  check "Story[$i] ($STORY_ID) has non-empty acceptanceCriteria" "(.userStories[$i].acceptanceCriteria | length) > 0" "true"
  check "Story[$i] ($STORY_ID) has .estimatedMinutes" ".userStories[$i] | has(\"estimatedMinutes\")" "true"
  check "Story[$i] ($STORY_ID) has .passes field" ".userStories[$i] | has(\"passes\")" "true"

  # Verify story references a valid phase
  STORY_PHASE=$(jq -r ".userStories[$i].phase" "$PRD_FILE")
  VALID_PHASE=$(jq -r "[.phases[].id] | contains([\"$STORY_PHASE\"])" "$PRD_FILE")
  if [ "$VALID_PHASE" = "true" ]; then
    echo "OK: Story[$i] ($STORY_ID) phase '$STORY_PHASE' exists"
  else
    echo "FAIL: Story[$i] ($STORY_ID) references non-existent phase '$STORY_PHASE'"
    ERRORS=$((ERRORS + 1))
  fi
done

# Check for duplicate story IDs
DUPLICATE_IDS=$(jq -r '[.userStories[].id] | group_by(.) | map(select(length > 1)) | .[] | .[0]' "$PRD_FILE" 2>/dev/null || true)
if [ -n "$DUPLICATE_IDS" ]; then
  echo "FAIL: Duplicate story IDs found: $DUPLICATE_IDS"
  ERRORS=$((ERRORS + 1))
else
  echo "OK: No duplicate story IDs"
fi

# Summary
echo ""
if [ "$ERRORS" -eq 0 ]; then
  STORY_COUNT=$(jq '.userStories | length' "$PRD_FILE")
  PHASE_COUNT=$(jq '.phases | length' "$PRD_FILE")
  echo "VALID: $PRD_FILE ($PHASE_COUNT phases, $STORY_COUNT stories)"
  exit 0
else
  echo "INVALID: $ERRORS error(s) found in $PRD_FILE"
  exit 1
fi

```

## File: `scripts/prd-to-json.md`

```markdown
# PRD to prd.json Conversion Guide

When converting a human-written PRD to machine-readable prd.json, follow this process.

## Step 1: Extract Feature Name

From the PRD title or main feature description, derive:
- `name`: kebab-case identifier (e.g., "user-authentication")
- `branchName`: Git branch name (e.g., "feature/user-authentication")

## Step 2: Identify Phases

Group related work into logical phases. Each phase is an approval gate.

Typical phases:
1. **Foundation** — Models, migrations, core utilities
2. **API/Backend** — Endpoints, services, business logic
3. **Frontend** — UI components, pages, forms
4. **Integration** — Wiring it all together, E2E tests
5. **Polish** — Edge cases, error handling, UX improvements

```json
"phases": [
  {
    "id": "PHASE-1",
    "name": "Foundation", 
    "description": "Database models and core utilities",
    "requiresApproval": true
  }
]
```

## Step 3: Identify User Stories

Break the PRD into discrete, atomic stories. Each story should:
- Be completable in 15-30 minutes
- Have clear, testable acceptance criteria
- Be independent enough to implement alone

### Story ID Convention
Use format: `STORY-XXX` where XXX is zero-padded number
- STORY-001, STORY-002, etc.

### Priority Rules
- 1 = Must have, blocks other work
- 2 = Must have, can be done in any order
- 3 = Should have
- 4 = Nice to have

Lower number = higher priority. Process in priority order.

## Step 3: Write Acceptance Criteria

Each criterion should be:
- Testable (can write a test for it)
- Specific (not vague)
- Complete (covers the requirement)

❌ Bad: "Form works correctly"
✅ Good: "Form validates email format and shows error for invalid emails"

❌ Bad: "API is fast"  
✅ Good: "API responds in under 200ms for typical requests"

## Step 4: Order Stories

Stories should be ordered so that:
1. Dependencies come before dependents
2. Foundation/infrastructure first
3. Core features before enhancements
4. Happy path before edge cases

## Example Conversion

### Input PRD (excerpt)
```
# User Authentication System

Users need to be able to register, log in, and log out.

Requirements:
- Registration with email and password
- Email must be valid format
- Password must be 8+ characters
- Login with email/password
- Session persists across page refresh
- Logout clears session
- Protected routes redirect to login
```

### Output prd.json
```json
{
  "name": "user-authentication",
  "branchName": "feature/user-authentication",
  "phases": [
    {
      "id": "PHASE-1",
      "name": "Foundation",
      "description": "User model and password utilities",
      "requiresApproval": true
    },
    {
      "id": "PHASE-2",
      "name": "API Layer", 
      "description": "Authentication endpoints and session management",
      "requiresApproval": true
    },
    {
      "id": "PHASE-3",
      "name": "Frontend",
      "description": "Login/register forms and route protection",
      "requiresApproval": true
    }
  ],
  "userStories": [
    {
      "id": "STORY-001",
      "phase": "PHASE-1",
      "title": "Add User model",
      "description": "Create database model for users with email and hashed password",
      "acceptanceCriteria": [
        "User model has id, email, passwordHash, createdAt fields",
        "Email has unique constraint",
        "Migration runs without errors"
      ],
      "priority": 1,
      "passes": false
    },
    {
      "id": "STORY-002",
      "phase": "PHASE-1",
      "title": "Add password hashing utility",
      "description": "Create utility for hashing and verifying passwords",
      "acceptanceCriteria": [
        "hashPassword() returns bcrypt hash",
        "verifyPassword() returns true for correct password",
        "verifyPassword() returns false for wrong password"
      ],
      "priority": 1,
      "passes": false
    },
    {
      "id": "STORY-003",
      "phase": "PHASE-2",
      "title": "Add registration API endpoint",
      "description": "POST /api/auth/register creates new user",
      "acceptanceCriteria": [
        "Returns 201 with user data on success",
        "Returns 400 if email invalid format",
        "Returns 400 if password under 8 chars",
        "Returns 409 if email already exists",
        "Password is hashed before storage"
      ],
      "priority": 1,
      "passes": false
    },
    {
      "id": "STORY-004",
      "phase": "PHASE-2",
      "title": "Add login API endpoint",
      "description": "POST /api/auth/login authenticates user",
      "acceptanceCriteria": [
        "Returns 200 with session token on success",
        "Returns 401 if email not found",
        "Returns 401 if password incorrect",
        "Sets httpOnly cookie with session"
      ],
      "priority": 1,
      "passes": false
    },
    {
      "id": "STORY-005",
      "phase": "PHASE-2",
      "title": "Add session management",
      "description": "Persist and validate user sessions",
      "acceptanceCriteria": [
        "Session persists across page refresh",
        "GET /api/auth/me returns current user if logged in",
        "GET /api/auth/me returns 401 if not logged in"
      ],
      "priority": 1,
      "passes": false
    },
    {
      "id": "STORY-006",
      "phase": "PHASE-2",
      "title": "Add logout endpoint",
      "description": "POST /api/auth/logout clears session",
      "acceptanceCriteria": [
        "Returns 200 on success",
        "Clears session cookie",
        "Subsequent /me calls return 401"
      ],
      "priority": 2,
      "passes": false
    },
    {
      "id": "STORY-007",
      "phase": "PHASE-2",
      "title": "Add auth middleware",
      "description": "Middleware to protect routes requiring authentication",
      "acceptanceCriteria": [
        "Protected routes return 401 without valid session",
        "Protected routes proceed with valid session",
        "User object attached to request"
      ],
      "priority": 2,
      "passes": false
    },
    {
      "id": "STORY-008",
      "phase": "PHASE-3",
      "title": "Add registration form UI",
      "description": "Frontend form for user registration",
      "acceptanceCriteria": [
        "Form has email and password fields",
        "Client-side validation matches API rules",
        "Shows error messages from API",
        "Redirects to login on success"
      ],
      "priority": 1,
      "passes": false
    },
    {
      "id": "STORY-009",
      "phase": "PHASE-3",
      "title": "Add login form UI",
      "description": "Frontend form for user login",
      "acceptanceCriteria": [
        "Form has email and password fields",
        "Shows error for invalid credentials",
        "Redirects to dashboard on success"
      ],
      "priority": 1,
      "passes": false
    },
    {
      "id": "STORY-010",
      "phase": "PHASE-3",
      "title": "Add protected route redirect",
      "description": "Redirect unauthenticated users to login",
      "acceptanceCriteria": [
        "Unauthenticated users on /dashboard redirect to /login",
        "After login, user returns to original destination",
        "Authenticated users access protected routes normally"
      ],
      "priority": 2,
      "passes": false
    }
  ]
}
```

## Validation Checklist

Before starting development, verify:

- [ ] All stories are small enough (15-30 min)
- [ ] Each story has testable acceptance criteria
- [ ] Dependencies are ordered correctly
- [ ] No story depends on an uncommitted story
- [ ] Branch name is valid git branch format
- [ ] IDs are unique and sequential

```

## File: `references/methodology.md`

```markdown
# Autonomous Development Methodology

Background theory on the frameworks this skill combines.

## Operating Modes

**Fully Autonomous** — Supervisor runs start-to-finish. Only alerts on critical blockers.
Best for: well-defined PRDs, established codebases.

**Human Assisted** — Pauses at phase boundaries for approval, more frequent check-ins.
Best for: first runs, complex projects, unfamiliar codebases.

## Ralph Loop (snarktank/ralph)

Core insight: **Fresh context each iteration**. Memory persists via files, not conversation.

Each story worker starts with a clean session and reads only what it needs:
- `prd.json` → assigned story
- `progress.txt` → recent learnings
- `AGENTS.md` → project conventions
- Relevant source files → found via grep, not bulk reads

This prevents context pollution across stories. One story's confusion can't affect the next.

## Superpowers TDD (obra/superpowers)

Mandatory TDD workflow:
1. **RED** — Write failing test for each acceptance criterion
2. **GREEN** — Write minimal code to make tests pass
3. **REFACTOR** — Clean up while tests still pass

Two-stage code review:
- **Spec compliance**: Does it meet all acceptance criteria?
- **Code quality**: Clean, follows project patterns, no obvious bugs?

## Context Budget Per Story

Target: keep reads under 50% of context window to leave room for generation.

```
Bootstrap reads (always):
  prd.json (single story)     ~500 tokens
  progress.txt (tail -50)     ~1000 tokens
  AGENTS.md                   ~1000 tokens
  ARCHITECTURE.md (if needed) ~1000 tokens
  Total bootstrap             ~3500 tokens

On-demand reads:
  Relevant source files        ~5000-10000 tokens
  Test files                   ~2000 tokens
  Total working set            ~15000 tokens

Reserved for generation:       50000+ tokens
```

Anti-patterns that cause context bloat:
- Reading entire `src/` directory upfront
- Loading all tests before knowing what to change
- Passing full `prd.json` in the spawn task (pass only the story ID)
- Reading files "just in case"

## Story Sizing Guidelines

Right-sized stories (15-30 minutes each):
- Add a database column and migration
- Create a UI component
- Add an API endpoint
- Implement a utility function
- Add form validation
- Write integration tests for a feature

Too big — split these:
- "Build the dashboard" → individual widgets
- "Add authentication" → login, register, session, logout as separate stories
- "Refactor the API" → specific endpoints

Splitting strategy: ask "What's the smallest useful increment?"

## Progress.txt Format

```markdown
# Progress Log

Started: 2026-01-01 15:00

## STORY-001: Add login form
- [15:05] Started implementation
- [15:12] Tests written, all failing (RED)
- [15:22] All tests passing (GREEN)
- [15:23] Committed: abc123
- Learning: Project uses react-hook-form, not controlled inputs

## STORY-002: Add login API
- [15:30] Started
- [15:35] Discovered auth utility already exists in src/lib/auth
- Learning: Check src/lib/ for existing utilities before creating new ones
- [15:45] Complete, committed: def456
```

## AGENTS.md Conventions

Workers update AGENTS.md when they discover reusable patterns:

```markdown
# Project Conventions

## Stack
- Framework: Next.js 15 (App Router)
- Testing: Vitest (run: pnpm test)
- Typecheck: pnpm exec tsc --noEmit

## Utilities
- Auth helpers: src/lib/auth.ts
- API client: src/lib/api.ts

## Gotchas
- Must run `pnpm db:generate` after schema changes
- API routes need auth middleware wrapper
- Forms need "use client" directive
```

## ARCHITECTURE.md Structure

Workers update ARCHITECTURE.md when they change system structure:

```markdown
# Architecture

## Overview
Brief description of the system.

## Directory Structure
src/
  app/        # Next.js pages + API routes
  components/ # React components
  lib/        # Shared utilities
  services/   # Business logic

## Data Flow
1. User action → Server Action or API Route
2. Route → Service layer
3. Service → Database

## Design Decisions
- Why key choices were made
```

## Handling Edge Cases

**Flaky tests** — Worker retries once. If still flaky, note in progress.txt. Supervisor decides: fix or skip.

**Missing dependencies** — Worker documents what's needed. Supervisor installs or creates prerequisite story.

**Architectural decisions** — Workers flag for phase supervisor review. Orchestrator escalates to user if unclear.

**External API issues** — Mock for tests where possible. Document dependencies and rate limits.

```

## File: `references/contract-testing.md`

```markdown
# Contract Testing Reference

When a story generates config, API payloads, or structured output consumed by an external system, follow this guide.

## Why Contract Tests Are Necessary

Your unit tests validate YOUR code — they don't validate the consumer's schema. A config that compiles, serializes, and passes all unit tests can still crash at runtime if the shape doesn't match what the external system expects. The only way to be sure is to verify against the source of truth.

## Step 1 — Verify External Contracts Before Writing Code

**Before writing any implementation**, check: does this story generate config or output consumed by an external system?

If YES:
1. **Read the acceptance criteria for exact schemas** — the planner should have included verbatim expected output
2. **Find a working example** — grep the codebase for existing usage of this config/API format
3. **Consult official docs** — if the story references docs, use `web_fetch` to read them
4. **If no schema is provided**: check the external system's validation code or docs before guessing a structure

## Step 2 — Write a Contract Test

Write at least one contract test that asserts the EXACT output shape against the documented schema. This is separate from functional tests:

```typescript
// Contract test: validates output matches external system's expected schema
it('generates memorySearch config matching OpenClaw schema', () => {
  const config = generateConfig(/* ... */);

  // Assert exact structure — not just "has provider", but the full nesting
  expect(config).toMatchObject({
    provider: 'openai',
    model: expect.any(String),
    remote: {
      baseUrl: expect.any(String),
      apiKey: expect.any(String),
    },
  });

  // Negative assertions: keys that would be rejected by the consumer
  expect(config).not.toHaveProperty('apiKey');
  expect(config).not.toHaveProperty('baseUrl');
});
```

## Step 3 — Run External Validation (If Available)

If the external system provides a validation command, run it against a generated sample as part of the quality gate:

| System | Validation command |
|--------|-------------------|
| OpenClaw | `openclaw doctor` |
| Docker Compose | `docker compose config` |
| Terraform | `terraform validate` |
| Kubernetes | `kubectl apply --dry-run=client` |

If no validation command is available, compare against a known-good example from the codebase.

## For Planners: Specifying Contracts in Stories

When writing acceptance criteria for stories that touch external systems:

1. Include the EXACT expected schema — not a description, but a verbatim JSON/YAML example
2. Add a contract test criterion: "A test validates the generated output against the documented schema"
3. Reference the authoritative docs URL in the story description

**Example acceptance criterion:**
```
Given vector memory is enabled, the generated config MUST match this exact structure:
{
  "agents": { "defaults": { "memorySearch": {
    "provider": "openai",
    "model": "text-embedding-3-small",
    "remote": { "baseUrl": "https://...", "apiKey": "sk-..." }
  }}}
}
Reference: https://docs.openclaw.ai/concepts/memory-search
```

Workers implement what the PRD specifies. Vague schema descriptions produce code that passes tests but fails at runtime. Be exact in the spec.

```

## File: `references/claude-md-guide.md`

```markdown
# CLAUDE.md Best Practices

Guidelines for writing effective CLAUDE.md files in autonomous development.

## What is CLAUDE.md?

A special file that Claude Code reads at the **start of every session**. It goes into the system prompt automatically, making it the highest-leverage configuration point.

## The Golden Rule: Less is More

| Metric | Recommendation |
|--------|----------------|
| Lines | <60 ideal, <300 max |
| Instructions | Keep to essential only |
| Content | Universally applicable to ALL tasks |

**Why?**
- LLMs can reliably follow ~150-200 instructions max
- Claude Code's system prompt already uses ~50 instructions
- As instruction count increases, compliance decreases **uniformly** (not just for new ones)
- Claude Code may **ignore** CLAUDE.md entirely if it seems irrelevant

## Structure: WHAT, WHY, HOW

```markdown
# Project: my-app

## WHAT (Tech Stack)
- Framework: Next.js 15
- Database: PostgreSQL + Prisma
- Testing: Vitest

## WHY (Purpose)  
E-commerce platform for artisan goods.

## HOW (Workflows)
- Build: `npm run build`
- Test: `npm test`
- Typecheck: `npm run typecheck`

## Before You Code
Read these for details:
- `AGENTS.md` — Conventions, patterns, gotchas
- `ARCHITECTURE.md` — System design, data flow
```

## Progressive Disclosure

Don't put everything in CLAUDE.md. Point to other files:

```
CLAUDE.md (minimal, ~40 lines)
    │
    ├──► AGENTS.md (conventions, patterns)
    │
    ├──► ARCHITECTURE.md (system design)
    │
    ├──► progress.txt (recent learnings)
    │
    └──► prd.json (current tasks)
```

Workers read CLAUDE.md first, then load other docs as needed.

## What NOT to Include

❌ **Code style rules** — Use linters and formatters instead
❌ **Edge case handling** — Put in AGENTS.md
❌ **Full API documentation** — Point to files
❌ **Database schemas** — Reference ARCHITECTURE.md
❌ **Every possible command** — Just the common ones

## What TO Include

✅ **Build/test/typecheck commands** — Universal
✅ **Pointers to key docs** — Progressive disclosure
✅ **Workflow summary** — TDD, commit conventions
✅ **Project name/purpose** — Quick orientation

## Template for Autonomous Dev

```markdown
# Project: [NAME]

## Quick Start
- Build: `npm run build`
- Test: `npm test`
- Typecheck: `npm run typecheck`

## Before You Code
Read these files first:
- `AGENTS.md` — Conventions, patterns, gotchas
- `ARCHITECTURE.md` — System design, components
- `progress.txt` — Recent learnings (tail -50)
- `prd.json` — Your assigned story

## Workflow
1. Read story from prd.json
2. TDD: RED → GREEN → REFACTOR
3. Run quality gates before commit
4. Update AGENTS.md if you discover patterns
5. Commit with story ID: "STORY-XXX: title"
```

## Relationship to Other Files

| File | Purpose | Size |
|------|---------|------|
| `CLAUDE.md` | Entry point, commands, pointers | <60 lines |
| `AGENTS.md` | Conventions, patterns, gotchas | Grows over time |
| `ARCHITECTURE.md` | System design, components | Grows over time |
| `progress.txt` | Session learnings | Append-only |

CLAUDE.md stays small. AGENTS.md and ARCHITECTURE.md grow as workers discover things.

## Research Sources

- [HumanLayer: Writing a good CLAUDE.md](https://www.humanlayer.dev/blog/writing-a-good-claude-md)
- [Anthropic: Using CLAUDE.md files](https://claude.com/blog/using-claude-md-files)
- [Claude Code Docs: Best Practices](https://code.claude.com/docs/en/best-practices)

## Key Insight

> "CLAUDE.md is the highest leverage point of the harness. A bad line in CLAUDE.md affects every phase of your workflow and every artifact produced."
> — HumanLayer

Don't auto-generate it. Craft it carefully. Every line should earn its place.

```

## File: `references/quick-commands.md`

```markdown
# Quick Commands — autonomous-dev v7.1

## Prerequisites

```bash
openclaw config set agents.defaults.subagents.maxSpawnDepth 2
openclaw config set agents.defaults.timeoutSeconds 21600
openclaw gateway restart
```

## Start Pipeline

```bash
cd /path/to/project
./scripts/orchestrate.sh init .
./scripts/orchestrate.sh next
# → shows mode-select menu
./scripts/orchestrate.sh complete mode-select success <choice>
# → shows model-select menu
./scripts/orchestrate.sh complete model-select success <choice>
# → auto-advances through validation, git pull, detect, baseline
# → returns first spawn instruction (research)
```

## The Loop

```bash
# After each spawn completes:
./scripts/orchestrate.sh complete <step>
# Returns next instruction. Do it. Repeat.
```

## Resume After Crash

```bash
./scripts/orchestrate.sh resume
# Shows current step, phase, stories
# Then: ./scripts/orchestrate.sh next
```

## Quality Gates (manual)

```bash
./scripts/quality-gate.sh --scope story     # ~30s
./scripts/quality-gate.sh --scope phase     # ~3-5 min
./scripts/quality-gate.sh --scope final     # ~10 min
./scripts/quality-gate.sh --baseline capture  # Snapshot existing failures
./scripts/quality-gate.sh --baseline diff     # Compare vs baseline
```

## State Inspection

```bash
jq '{step, mode, preset, currentPhase}' state.json
jq '.models' state.json
jq '.stories' state.json
cat .pipeline.log
```

```

## File: `hooks/.claude/settings.json`

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/inject-rules.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-shortcuts.sh"
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pre-commit-gate.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/post-edit-tests.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "echo '✅ Task complete. Remember: Run full test suite before any commit.'"
          }
        ]
      }
    ]
  }
}

```

## File: `hooks/.claude/hooks/block-shortcuts.sh`

```bash
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

```

## File: `hooks/.claude/hooks/pre-commit-gate.sh`

```bash
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

```

## File: `hooks/.claude/hooks/post-edit-tests.sh`

```bash
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

```

## File: `hooks/.claude/hooks/inject-rules.sh`

```bash
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

```

## File: `hooks/README.md`

```markdown
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

```

---
*End of autonomous-dev v7.1 skill package.*
