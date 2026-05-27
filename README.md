# openclaw-code-agent

OpenClaw plugin that launches Claude Code or Codex as managed background coding sessions, bundled with the autonomous-dev pipeline skill.

## What's in the box

**Plugin** (`src/`) — Registers agent tools for delegating coding work:

| Tool | Description |
|------|-------------|
| `agent_launch` | Start a Claude Code or Codex session with a prompt |
| `agent_output` | Read output from a running or completed session |
| `agent_respond` | Send input to a running session (answer questions, approve plans) |
| `agent_sessions` | List all active and recent sessions |
| `agent_kill` | Kill a running session |
| `agent_merge` | Merge a worktree branch back and clean up |
| `agent_pr` | Create a PR/MR (auto-detects GitHub/GitLab) |

**Pipeline Skill** (`skill/`) — Autonomous dev pipeline that takes a PRD and produces a merge-ready PR:

```
Research → Plan → TDD Stories → Phase Review → Final Review → PR → CI Monitor
```

## Prerequisites

- **Claude Code CLI** (`claude`) — `npm i -g @anthropic-ai/claude-code`
- **Codex CLI** (`codex`) — `npm i -g @openai/codex`
- **`gh`** and/or **`glab`** for PR/MR creation
- API keys: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` (if using Codex)

## Install

```bash
# Clone
git clone https://github.com/nexiontech/openclaw-code-agent.git
cd openclaw-code-agent

# Build plugin
npm install
npm run build

# Install into OpenClaw
openclaw plugins install --link . --dangerously-force-unsafe-install
openclaw plugins enable code-agent

# Install skill
cp -r skill/ ~/.openclaw/workspace/skills/autonomous-dev/
chmod +x ~/.openclaw/workspace/skills/autonomous-dev/scripts/*.sh

# Configure
openclaw config set agents.defaults.subagents.maxSpawnDepth 2
openclaw config set agents.defaults.timeoutSeconds 21600
openclaw gateway restart

# Verify
openclaw plugins inspect code-agent --runtime
```

## Plugin Configuration

```yaml
plugins:
  entries:
    code-agent:
      enabled: true
      config:
        claudePath: claude
        codexPath: codex
        defaultHarness: claude-code
        defaultTimeoutSeconds: 1800
```

## Usage

**Direct tool use** — delegate a coding task:
```
agent_launch(
  prompt: "Implement auth middleware with TDD",
  name: "story-S1-auth",
  workdir: "/path/to/repo",
  harness: "claude-code",
  permission_mode: "bypassPermissions"
)
```

**Full pipeline** — give your agent a PRD:
```
Run autonomous-dev on /path/to/project
```

## Container Setup

See [CONTAINER.md](CONTAINER.md) for running in a containerised OpenClaw.

## Model Presets (Pipeline)

| Preset | Coders | Coordination | Cost |
|--------|--------|-------------|------|
| **Premium** | Claude Opus | Claude Sonnet | $$$ |
| **Balanced** | Claude Sonnet | Claude Sonnet | $$ |
| **Budget** | Claude Haiku 4.5 | Haiku + Sonnet | $ |

## Based on

Pipeline skill forked from [moltpill/autonomous-dev](https://github.com/moltpill/autonomous-dev) v7.3.

## License

MIT
