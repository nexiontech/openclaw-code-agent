---
name: autonomous-dev
description: Autonomous AI-driven software development from PRD to working solution. Spawns one worker at a time. Never spawn agents yourself — orchestrate.sh provides the full task text.
---

# Autonomous Development (v7.3)

## HOW IT WORKS

Call orchestrate.sh. It returns a JSON instruction. Do exactly what it says. Repeat.

```bash
cd ${projectPath}
./scripts/orchestrate.sh init ${projectPath}
# Then loop:
INSTRUCTION=$(./scripts/orchestrate.sh next)
# Do what it says...
INSTRUCTION=$(./scripts/orchestrate.sh complete <step> [status] [data])
# This returns the NEXT instruction. Do it. Repeat.
```

## RULES

1. **orchestrate.sh is the brain.** It tells you what to do. Follow it.
2. **When it says spawn:** use the `task`, `model`, `timeout`, `cwd`, `label` from the JSON EXACTLY.
3. **When a sub-agent completes:** call `./scripts/orchestrate.sh complete <step>` IMMEDIATELY.
4. **NEVER improvise.** Don't create your own loops, supervisors, threads, or orchestration.
5. **If something breaks:** call `./scripts/orchestrate.sh doctor` and show the result to the user.
6. **ONE agent at a time.** Never spawn multiple agents in parallel.

## HANDLING INSTRUCTIONS

| Action | What you do |
|--------|------------|
| `spawn` | `sessions_spawn({ task: instruction.task, model: instruction.model, runTimeoutSeconds: instruction.timeout, cwd: instruction.cwd, label: instruction.label, mode: "run", cleanup: "delete" })` — then wait for result, then call complete. |
| `ask` | **MUST show the menu to the user and WAIT for their reply.** Do NOT auto-select. `complete <step> success <reply>` |
| `gate` | Show content to user. Wait for reply. `complete <step> success <proceed\|adjust:...\|cancel>` |
| `run` | Execute the commands described in the message. Then `complete <step>` |
| `progress` | Show the message. Call `next` immediately. |
| `preflight` | Show summary. On confirm: `complete preflight`. On cancel: stop. |
| `complete` | Pipeline done! Show the PR link to the user. |
| `blocked` | Pipeline blocked. Show reason to user. Stop. |
| `error` | Show error to user. Call `./scripts/orchestrate.sh doctor` for diagnosis. Do NOT redesign the pipeline. |

## SPAWN EXAMPLE

orchestrate.sh returns:
```json
{
  "action": "spawn",
  "step": "story-execute",
  "task": "You are a story worker...(full agent prompt)...",
  "model": "anthropic/claude-opus-4-6",
  "timeout": 1800,
  "cwd": "/projects/myapp",
  "label": "coder-STORY-001",
  "onComplete": "complete story-execute",
  "onBlocked": "complete story-execute blocked <reason>"
}
```

You do:
```javascript
sessions_spawn({
  task: instruction.task,
  model: instruction.model,
  runTimeoutSeconds: instruction.timeout,
  cwd: instruction.cwd,
  label: instruction.label,
  mode: "run",
  cleanup: "delete"
})
```

When the agent result arrives → `./scripts/orchestrate.sh complete story-execute`

## PIPELINE

```
MODE-SELECT → MODEL-SELECT → VALIDATE-MODELS → [auto: git, detect, baseline]
  → RESEARCH → [Research Gate*] → PLANNER → [Plan Gate*] → PRE-FLIGHT
  → STORY-1 → [verify] → STORY-2 → ... → PHASE-1-REVIEW
  → ... → FINAL REVIEW → PR-CREATE → PR-REVIEW → CI-MONITOR → COMPLETE
```

## COMMANDS

```bash
./scripts/orchestrate.sh init <path>     # Start pipeline
./scripts/orchestrate.sh next            # Get next instruction
./scripts/orchestrate.sh complete <step> [status] [data]  # Advance pipeline
./scripts/orchestrate.sh resume          # Resume from crash (returns next instruction)
./scripts/orchestrate.sh doctor          # Diagnose issues
```

## PREREQUISITES

```bash
openclaw config set agents.defaults.subagents.maxSpawnDepth 2
openclaw config set agents.defaults.timeoutSeconds 21600
openclaw gateway restart
```
