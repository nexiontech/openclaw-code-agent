# Container Setup

Running autonomous-dev in a containerised OpenClaw instance.

## Dockerfile

```dockerfile
FROM node:22-slim

# System deps
RUN apt-get update && apt-get install -y \
  git curl jq bash ca-certificates gnupg \
  && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | gpg --dearmor -o /usr/share/keyrings/githubcli.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" \
  > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y gh && rm -rf /var/lib/apt/lists/*

# GitLab CLI (optional — include if working with GitLab repos)
RUN curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/permalink/latest/downloads/glab_$(dpkg --print-architecture).deb" -o /tmp/glab.deb \
  && dpkg -i /tmp/glab.deb && rm /tmp/glab.deb

# OpenClaw
RUN npm install -g openclaw

# Git identity (override via env vars)
RUN git config --global user.name "OpenClaw Dev Agent" \
  && git config --global user.email "agent@openclaw.local"

# Co-author commit-msg hook (appends Yash's trailer if missing)
RUN mkdir -p /root/.config/git/hooks
COPY hooks/commit-msg /root/.config/git/hooks/commit-msg
RUN chmod +x /root/.config/git/hooks/commit-msg \
  && git config --global core.hooksPath /root/.config/git/hooks

# Workspace
RUN mkdir -p /root/.openclaw/workspace/skills
COPY . /root/.openclaw/workspace/skills/autonomous-dev/
RUN chmod +x /root/.openclaw/workspace/skills/autonomous-dev/scripts/*.sh

WORKDIR /root/.openclaw/workspace

ENTRYPOINT ["openclaw", "gateway", "start"]
```

## commit-msg hook

Save as `hooks/commit-msg`:

```bash
#!/bin/bash
# Append co-author trailer if missing
TRAILER="Co-authored-by: Yashiel Sookdeo <yashiel@skyner.co.za>"
if ! grep -qF "$TRAILER" "$1"; then
  echo "" >> "$1"
  echo "$TRAILER" >> "$1"
fi
```

## Environment Variables

```bash
# Required
ANTHROPIC_API_KEY=sk-ant-...        # For Claude models (agent + subagents)
GH_TOKEN=ghp_...                    # GitHub CLI auth
GLAB_TOKEN=glpat-...                # GitLab CLI auth (if using GitLab)

# Optional
GIT_AUTHOR_NAME="OpenClaw Dev Agent"
GIT_AUTHOR_EMAIL="agent@openclaw.local"
```

## docker-compose.yml

```yaml
services:
  openclaw-dev:
    build: .
    environment:
      - ANTHROPIC_API_KEY
      - GH_TOKEN
      - GLAB_TOKEN
    volumes:
      # Persistent workspace (memory, lessons, state)
      - openclaw-workspace:/root/.openclaw/workspace
      # Mount your repos
      - ./repos:/repos
    ports:
      - "18789:18789"  # Dashboard

volumes:
  openclaw-workspace:
```

## OpenClaw Config (post-start)

```bash
# Inside the container
openclaw config set agents.defaults.subagents.maxSpawnDepth 2
openclaw config set agents.defaults.timeoutSeconds 21600
openclaw gateway restart
```

Or mount a pre-configured `config.yaml`.

## Usage

```bash
docker compose up -d
# Then via dashboard, Discord, or any connected channel:
# "Run autonomous-dev on /repos/my-project"
```

## Volumes

| Path | Purpose | Persistence |
|------|---------|-------------|
| `/root/.openclaw/workspace` | Agent memory, skills, lessons | **Yes** — mount a named volume |
| `/repos` | Your project repositories | **Yes** — bind mount from host |
| `/root/.openclaw/workspace/skills/autonomous-dev` | This skill | Baked into image |

## Notes

- The container needs network access for git push/pull, GitHub/GitLab API, and Anthropic API
- For private repos, ensure GH_TOKEN/GLAB_TOKEN have appropriate scopes
- The co-author hook ensures every commit includes the required trailer regardless of which subagent makes it
- Repos should be cloned inside the container or bind-mounted with write access
