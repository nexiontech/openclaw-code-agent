# Quick Commands — autonomous-dev v7.3

## Prerequisites

```bash
openclaw config set agents.defaults.subagents.maxSpawnDepth 2
openclaw config set agents.defaults.timeoutSeconds 21600
openclaw gateway restart
```

## Pipeline Commands

```bash
./scripts/orchestrate.sh init <path>           # Start pipeline
./scripts/orchestrate.sh next                  # Get next instruction (JSON)
./scripts/orchestrate.sh complete <step> [s] [d]  # Advance + get next
./scripts/orchestrate.sh resume                # Resume from crash → returns next instruction
./scripts/orchestrate.sh doctor                # Diagnose issues
```

## State Inspection

```bash
jq '{step, mode, preset, currentPhase, currentStory}' state.json
jq '.models' state.json
jq '.stories' state.json
cat .pipeline.log | tail -20
```

## Quality Gates

```bash
./scripts/quality-gate.sh --scope story     # ~30s
./scripts/quality-gate.sh --scope phase     # ~3-5 min
./scripts/quality-gate.sh --scope final     # ~10 min
./scripts/quality-gate.sh --baseline capture
./scripts/quality-gate.sh --baseline diff
```
