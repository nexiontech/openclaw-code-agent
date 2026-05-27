# Autonomous Development Methodology

Deep background on the frameworks combined in this skill.

## Operating Modes

### Fully Autonomous
- Supervisor runs start-to-finish without human intervention
- Phase reviews happen automatically
- Only alerts on **critical blockers**
- Best for: Well-defined PRDs, established codebases

### Human Assisted
- Pauses at phase boundaries for approval
- More frequent check-ins
- Human reviews phase results before continuing
- Best for: First runs, complex projects, learning the system

## Agent Hierarchy

```
SUPERVISOR (long-running)
    │
    ├── PHASE AGENT 1 ──► REVIEW AGENT 1
    │
    ├── PHASE AGENT 2 ──► REVIEW AGENT 2
    │
    ├── PHASE AGENT N ──► REVIEW AGENT N
    │
    └── FINAL E2E REVIEW AGENT
```

- **Supervisor**: Orchestrates everything, reports every 5 min, helps stuck agents
- **Phase Agent**: Fresh context, implements all stories in one phase
- **Review Agent**: Verifies tests, adds smoke/API/integration tests
- **Final E2E**: Comprehensive integration verification

## NO SHORTCUTS — Critical Rule

All agents MUST follow these rules:

```
⛔ NEVER:
├── Manually patch containers/deployments
├── Skip tests to "unblock"
├── Hardcode values to pass tests
├── Comment out failing tests
├── Direct fixes to production
└── Suppress errors without fixing

✅ ALWAYS:
├── Fix issues in source code
├── Commit changes to git
├── Write tests for fixes
├── Ensure CI/CD would pass
├── Document learnings
└── Fix root causes
```

Why? Shortcuts create tech debt that compounds across stories.
A "quick fix" in Story 5 breaks Stories 15, 23, and 41.

## Breaking Changes — Flag Upfront

During PRD analysis, BEFORE creating stories:

1. **Identify** potential breaking changes
2. **Flag** them explicitly to the user
3. **Wait** for approval before proceeding
4. **Document** approved changes in prd.json

```
Breaking Change Types:
├── API contract changes
├── Database schema changes
├── Interface/type changes
├── Feature removals
├── Auth changes
└── Config format changes
```

## External API — Golden Rule

```
🔒 EXTERNAL APIs: NEVER BREAK BACKWARDS COMPATIBILITY

⛔ NEVER:
├── Remove endpoints
├── Change response structure
├── Change required parameters
├── Remove fields from responses
└── Change authentication requirements

✅ ALWAYS:
├── ADD new optional fields
├── ADD new versioned endpoints (/api/v2/)
├── DEPRECATE with warning headers
├── MAINTAIN old endpoints
└── DOCUMENT migration paths
```

If a breaking change is truly unavoidable:
1. Create new versioned endpoint
2. Keep old endpoint working indefinitely
3. Add deprecation warning header
4. Document migration in CHANGELOG
5. Communicate timeline to consumers

## Test Compatibility Rules

New tests must NOT break existing tests unless:

| Scenario | Action |
|----------|--------|
| Valid refactor | Update test + code together, document |
| Approved breaking change | Flagged in planning, approved by human |
| Old test was wrong | Document why, get approval |
| Unexpected failure | STOP, investigate, report |

Review agents verify:
- All existing tests still pass
- New tests don't conflict
- UI tests cover new components
- API tests verify backwards compat

## Ralph Loop (snarktank/ralph)

Core insight: **Fresh context each iteration**. Memory persists via files, not conversation.

### Why Fresh Context Works
- Each iteration starts clean — no accumulated confusion
- Git history provides code context
- progress.txt provides learnings
- prd.json provides task state
- AGENTS.md provides conventions

### Context Budget Per Story

Target: Use <50% of context window to leave room for code generation.

```
Bootstrap reads (ALWAYS):
├── prd.json (single story)     ~500 tokens
├── progress.txt (tail -50)     ~1000 tokens
├── AGENTS.md                   ~1000 tokens
├── ARCHITECTURE.md             ~1000 tokens
└── Total bootstrap             ~3500 tokens

On-demand reads:
├── Relevant source files       ~5000-10000 tokens
├── Test files                  ~2000 tokens
└── Total working set           ~15000 tokens

Reserved for generation:        ~50000+ tokens
```

### Documentation Updates

Workers must update docs when relevant:

**AGENTS.md** — Codebase conventions
- Patterns: "Use X for Y"
- Utilities: "Auth helpers in src/lib/auth.ts"
- Gotchas: "Must run db:generate after schema changes"

**ARCHITECTURE.md** — System design
- Components: What exists and where
- Data flow: How things connect
- Decisions: Why things are the way they are

### Anti-Patterns (Cause Compaction)

```
❌ Read entire src/ directory upfront
❌ Load all tests before knowing what to change
❌ Pass full prd.json in spawn task
❌ Keep chat history between stories
❌ Read files "just in case"
```

### Correct Patterns

```
✅ Read only assigned story ID from prd.json
✅ Use grep to find relevant files
✅ Load files incrementally as needed
✅ Each story = new session (sessions_spawn)
✅ cleanup: 'delete' to clear after
```

### Key Principles
1. **Small tasks** — Must complete in one context window
2. **Quality gates** — Typecheck + tests before marking done
3. **Learnings capture** — Append to progress.txt for future iterations
4. **Convention discovery** — Update AGENTS.md with patterns found

### prd.json Structure
```json
{
  "name": "feature-name",
  "branchName": "feature/feature-name", 
  "userStories": [
    {
      "id": "STORY-001",
      "title": "Add user login form",
      "description": "Create a login form component with email/password fields",
      "acceptanceCriteria": [
        "Form has email input with validation",
        "Form has password input",
        "Submit button calls auth API",
        "Error states displayed properly"
      ],
      "priority": 1,
      "passes": false
    }
  ]
}
```

## Superpowers TDD (obra/superpowers)

Core insight: **Mandatory workflows, not suggestions**. Agent checks for relevant skills before any task.

### The RED-GREEN-REFACTOR Cycle

1. **RED**: Write a failing test first
   - Test should fail for the right reason
   - Test should actually test the acceptance criteria
   
2. **GREEN**: Write minimal code to pass
   - Don't over-engineer
   - Just make the test pass
   
3. **REFACTOR**: Clean up if needed
   - Only if tests still pass
   - Improve readability/structure

### Two-Stage Code Review

**Stage 1: Spec Compliance**
- Does it do what the story asks?
- Are ALL acceptance criteria met?
- Do tests cover the criteria?

**Stage 2: Code Quality**
- Is code clean and readable?
- Does it follow project patterns?
- Any obvious bugs or security issues?
- Proper error handling?

### Subagent-Driven Development

Fresh agent per task because:
- Avoids context pollution
- Each task gets full attention
- Failures don't cascade
- Easy to retry specific stories

## Multi-Agent Architecture

### Role Separation

**Supervisor (Main Session)**
- Orchestrates the overall process
- Converts PRD to stories
- Assigns work to workers
- Reviews completed work
- Handles escalations
- Notifies user

**Worker (Sub-Agent)**
- Implements single story
- Follows TDD strictly
- Reports completion/blocking
- Updates progress.txt

**Monitor (Cron Job)**
- Periodic health checks
- Stuck detection
- Progress reporting
- Alerts on issues

### Communication Flow

```
User ──► Supervisor ──► Worker
              │            │
              │            ▼
              │      [implements]
              │            │
              ◄────────────┘
              │
              ▼
        [reviews]
              │
              ▼
        [next story or done]
```

## Story Sizing Guidelines

### Right-Sized Stories (~15-30 min)
- Add a database column and migration
- Create a UI component
- Add an API endpoint
- Implement a utility function
- Add form validation
- Write integration test for feature

### Too Big (Split These)
- "Build the dashboard" → Split into individual widgets
- "Add authentication" → Split into login, register, session, logout
- "Refactor the API" → Split into specific endpoints
- "Improve performance" → Split into specific bottlenecks

### Splitting Strategy
Ask: "What's the smallest useful increment?"

Example: "Add user authentication"
1. STORY-001: Add User model and migration
2. STORY-002: Add password hashing utility
3. STORY-003: Add register API endpoint
4. STORY-004: Add login API endpoint  
5. STORY-005: Add session management
6. STORY-006: Add logout endpoint
7. STORY-007: Add auth middleware
8. STORY-008: Add login form UI
9. STORY-009: Add register form UI

## Handling Edge Cases

### Flaky Tests
- Worker should retry once
- If still flaky, note in progress.txt
- Supervisor decides: fix or skip

### Missing Dependencies
- Worker should document what's needed
- Supervisor may need to install/configure
- Or create prerequisite story

### Architectural Decisions
- Worker shouldn't make big architectural calls
- Flag for supervisor review
- Supervisor asks user if unclear

### External API Issues
- Mock for tests where possible
- Document external dependencies
- Note rate limits or auth requirements

## Progress.txt Format

```markdown
# Progress Log

Started: 2026-02-18 15:00

## STORY-001: Add login form
- [15:05] Started implementation
- [15:12] Tests written, all failing (RED)
- [15:18] Form component created, 2/4 tests pass
- [15:22] All tests passing (GREEN)
- [15:23] Committed: abc123
- Learning: Project uses react-hook-form, not controlled inputs

## STORY-002: Add login API
- [15:30] Started
- [15:35] Discovered auth utility already exists in src/lib/auth
- Learning: Check src/lib/ for existing utilities before creating new ones
- [15:45] Complete, committed: def456

## STORY-003: Session management
- [15:50] Started
- [15:55] BLOCKED: Need Redis config for session store
- Waiting for: Environment variable REDIS_URL
```

## AGENTS.md Conventions

Add discovered patterns to help future iterations:

```markdown
# Project Conventions

## Stack
- Framework: Next.js 15 (App Router)
- Language: TypeScript strict mode
- Database: Prisma + PostgreSQL
- Styling: Tailwind CSS

## Testing
- Use vitest, not jest
- Test files: `*.test.ts` next to source
- Run: `npm test`
- E2E: Playwright in /e2e/

## Code Style
- Functional components with hooks
- Use react-hook-form for forms
- Server actions for mutations
- Zod for validation

## Utilities
- Auth helpers: src/lib/auth.ts
- API client: src/lib/api.ts
- Date formatting: src/lib/dates.ts
- Validation schemas: src/lib/schemas/

## Gotchas
- Must run `npm run db:generate` after schema changes
- API routes need auth middleware wrapper
- Forms need client-side "use client" directive
- Redis required for sessions (REDIS_URL env var)
```

## ARCHITECTURE.md Structure

Document system design for future workers:

```markdown
# Architecture

## Overview
E-commerce platform with Next.js frontend, Prisma ORM, 
PostgreSQL database, and Redis for sessions/caching.

## Directory Structure
src/
├── app/           # Next.js App Router pages
│   ├── api/       # API routes
│   └── (shop)/    # Public shop pages
├── components/    # React components
│   ├── ui/        # Primitives (button, input)
│   └── features/  # Feature-specific (cart, checkout)
├── lib/           # Shared utilities
├── services/      # Business logic
└── types/         # TypeScript types

## Data Flow
1. User action → Server Action or API Route
2. Route → Service layer (business logic)
3. Service → Prisma (database)
4. Response → Client (revalidate if needed)

## Key Components
- **Auth**: JWT in httpOnly cookie, refresh tokens in Redis
- **Cart**: Server-side sessions, synced to DB for logged-in users
- **Payments**: Stripe integration via webhooks
- **Search**: PostgreSQL full-text, considering Algolia

## Design Decisions
- Server Components by default, "use client" only when needed
- Optimistic UI updates for cart operations
- Background jobs via Inngest for order processing
```
