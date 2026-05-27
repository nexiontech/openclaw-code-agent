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
