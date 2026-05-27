#!/bin/bash
# orchestrate.sh — State machine for autonomous-dev pipeline (v7.3)
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
  # Build JSON using jq to handle all escaping properly
  local result
  result=$(jq -nc --arg action "$action" --argjson auto "$auto_json" '{action: $action, autoAdvanced: $auto} + (input // {})' <<< "{$@}" 2>/dev/null)
  if [ -z "$result" ]; then
    # Fallback: try simple printf approach
    result=$(printf '{"action":"%s","autoAdvanced":%s,%s}' "$action" "$auto_json" "$@" | jq -c . 2>/dev/null)
  fi
  if [ -z "$result" ]; then
    echo "{\"action\":\"error\",\"step\":\"unknown\",\"message\":\"orchestrate.sh emit failed. Call doctor.\"}"
    exit 1
  fi
  echo "$result"
}


# Emit a spawn with filled template — the agent just copies the values
emit_spawn() {
  local step="$1" template="$2" model_role="$3" timeout="$4" label="$5"

  # Resolve model ID from state.json
  local model_id
  model_id=$(jq -r ".models.\"$model_role\" // \"\"" "$STATE_FILE" 2>/dev/null)
  if [ -z "$model_id" ]; then
    model_id=$(jq -r ".models.coder // .models.researcher // \"\"" "$STATE_FILE" 2>/dev/null)
  fi

  local project_path=$(json_get '.project.path // "."')
  local branch=$(json_get '.project.branch // "main"')

  # Fill template directly to temp file (avoids shell variable mangling of Unicode)
  local template_path="$SCRIPT_DIR/../$template"
  if [ ! -f "$template_path" ]; then
    echo "{\"action\":\"error\",\"step\":\"$step\",\"message\":\"Template not found: $template. Report this to user.\"}"
    exit 1
  fi

  local task_file
  task_file=$(mktemp)
  
  # Get placeholder values
  local BRANCH_NAME=$(json_get '.project.branch // "main"')
  local CURRENT_STORY=$(json_get '.currentStory // ""')
  local CURRENT_PHASE=$(json_get '.currentPhase // ""')
  local PR_URL=$(json_get '.prUrl // ""')
  local PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$' || true)
  local PRD_NAME=$(jq -r '.name // "unknown"' prd.json 2>/dev/null || echo "unknown")
  local EST_MINUTES=$(jq -r ".userStories[] | select(.id==\"$CURRENT_STORY\") | .estimatedMinutes // 30" prd.json 2>/dev/null || echo "30")
  local STORY_TIMEOUT=$((EST_MINUTES * 90))
  [ "$STORY_TIMEOUT" -lt 1800 ] && STORY_TIMEOUT=1800
  local PHASE_NAME=$(jq -r ".phases[] | select(.id==\"$CURRENT_PHASE\") | .name // \"\"" prd.json 2>/dev/null || true)
  local STORY_COUNT=$(jq -r ".phases[] | select(.id==\"$CURRENT_PHASE\") | .stories | length" prd.json 2>/dev/null || echo "0")

  # sed directly to file (preserves UTF-8)
  sed \
    -e "s|\${projectPath}|$project_path|g" \
    -e "s|\${branchName}|$BRANCH_NAME|g" \
    -e "s|\${storyId}|$CURRENT_STORY|g" \
    -e "s|\${storyTimeoutSeconds}|$STORY_TIMEOUT|g" \
    -e "s|\${estimatedMinutes}|$EST_MINUTES|g" \
    -e "s|\${phaseId}|$CURRENT_PHASE|g" \
    -e "s|\${phaseName}|$PHASE_NAME|g" \
    -e "s|\${storyCount}|$STORY_COUNT|g" \
    -e "s|\${prUrl}|$PR_URL|g" \
    -e "s|\${prNumber}|$PR_NUMBER|g" \
    -e "s|\${prdName}|$PRD_NAME|g" \
    -e "s|\${prdPath}|prd.json|g" \
    "$template_path" > "$task_file"

  jq -nc \
    --arg action "spawn" \
    --arg step "$step" \
    --rawfile task "$task_file" \
    --arg model "$model_id" \
    --argjson timeout "$timeout" \
    --arg cwd "$project_path" \
    --arg label "$label" \
    --arg branch "$branch" \
    --arg onComplete "complete $step" \
    --arg onBlocked "complete $step blocked <reason>" \
    '{action:$action, step:$step, task:$task, model:$model, timeout:$timeout, cwd:$cwd, label:$label, branch:$branch, onComplete:$onComplete, onBlocked:$onBlocked}'

  rm -f "$task_file"
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

  # Resume now falls through to the normal next loop — returns the actual instruction
  # instead of just a summary. The agent gets the spawn/run/gate it needs immediately.
  ACTION="next"
  # Fall through to next
fi

# ─── DOCTOR — Validate pipeline state ───

if [ "$ACTION" = "doctor" ]; then
  ISSUES=0
  MSGS=""
  
  # state.json
  if [ ! -f "$STATE_FILE" ]; then
    MSGS="${MSGS}FAIL: state.json missing\n"
    ISSUES=$((ISSUES + 1))
  elif ! jq empty "$STATE_FILE" 2>/dev/null; then
    MSGS="${MSGS}FAIL: state.json is invalid JSON\n"
    ISSUES=$((ISSUES + 1))
  else
    STEP=$(json_get '.step')
    MSGS="${MSGS}OK: state.json valid (step: $STEP)\n"
  fi

  # prd.json (needed after planner)
  STEP=$(json_get '.step // "mode-select"')
  case "$STEP" in story-execute|story-verify|phase-review|phase-gate|final-review|pr-create|pr-review|ci-monitor|complete)
    if [ ! -f "prd.json" ]; then
      MSGS="${MSGS}FAIL: prd.json missing (needed for step: $STEP)\n"
      ISSUES=$((ISSUES + 1))
    elif ! jq empty prd.json 2>/dev/null; then
      MSGS="${MSGS}FAIL: prd.json is invalid JSON\n"
      ISSUES=$((ISSUES + 1))
    else
      MSGS="${MSGS}OK: prd.json valid\n"
    fi
    ;; *)
    MSGS="${MSGS}OK: prd.json not yet needed (step: $STEP)\n"
    ;; esac

  # research/findings.md (needed after research)
  case "$STEP" in planner|validate-prd*|plan-review|preflight|story-*|phase-*|final-*|pr-*|ci-*|complete)
    if [ ! -f "research/findings.md" ]; then
      MSGS="${MSGS}FAIL: research/findings.md missing\n"
      ISSUES=$((ISSUES + 1))
    else
      MSGS="${MSGS}OK: research/findings.md exists\n"
    fi
    ;; esac

  # Git branch
  BRANCH=$(json_get '.project.branch // ""')
  if [ -n "$BRANCH" ]; then
    ACTUAL=$(git branch --show-current 2>/dev/null || echo "unknown")
    if [ "$ACTUAL" = "$BRANCH" ]; then
      MSGS="${MSGS}OK: on correct branch ($BRANCH)\n"
    else
      MSGS="${MSGS}WARN: on branch $ACTUAL, expected $BRANCH\n"
    fi
  fi

  jq -nc --arg issues "$ISSUES" --arg message "$(echo -e "$MSGS")" '{action:"doctor", issues:($issues|tonumber), message:$message}'
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
          json_set ".preset = \"budget\" | .models = {\"supervisor\":\"anthropic/claude-haiku-4-5\",\"researcher\":\"anthropic/claude-sonnet-4-6\",\"planner\":\"anthropic/claude-sonnet-4-6\",\"coder\":\"anthropic/claude-haiku-4-5\",\"tester\":\"anthropic/claude-haiku-4-5\",\"reviewer\":\"anthropic/claude-sonnet-4-6\"} | .step = \"validate-models\""
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
      # A coder finished. Mark complete + advance to verify (single atomic write)
      CURRENT_PHASE=$(get_current_phase)
      CURRENT_STORY=$(get_current_story)
      json_set ".stories.\"$CURRENT_STORY\" = {\"status\":\"complete\",\"completedAt\":\"$(now)\"} | .step = \"story-verify\""
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
    pr-create)     json_set '.step = "pr-review"' ;;
    pr-review)     json_set '.step = "ci-monitor"' ;;
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

        # Detect forge (GitHub vs GitLab) from remote URL
        REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
        FORGE="github"
        if echo "$REMOTE_URL" | grep -qi "gitlab"; then
          FORGE="gitlab"
        fi
        log_step "pr-create" "forge: $FORGE (remote: $REMOTE_URL)"

        # Push
        PUSH_OUT=$(git push -u origin "$BRANCH" 2>&1) || true
        log_step "pr-create" "push: ${PUSH_OUT:0:200}"

        # Detect default branch
        DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@') || true
        [ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH="main"

        # Create PR/MR
        PR_BODY="## $PROJECT_NAME

### Stories
$STORIES

### Quality
- All quality gates passing (story + phase + final)
- Phase reviews complete
- Final review complete"

        if [ "$FORGE" = "gitlab" ]; then
          PR_URL=$(glab mr create --title "$PROJECT_NAME" --description "$PR_BODY" --target-branch "$DEFAULT_BRANCH" --remove-source-branch --yes 2>&1 | grep -oE 'https://[^ ]+') || true
        else
          PR_URL=$(gh pr create --title "$PROJECT_NAME" --body "$PR_BODY" --base "$DEFAULT_BRANCH" 2>&1 | grep -oE 'https://github.com/[^ ]+') || true
        fi

        if [ -n "$PR_URL" ]; then
          json_set ".prUrl = \"$PR_URL\" | .forge = \"$FORGE\""
          log_step "pr-create" "PR: $PR_URL"
          advance "pr-create" "pr-review"
        else
          # PR/MR creation failed — let AI handle it
          log_step "pr-create" "auto-create failed, deferring to AI"
          if [ "$FORGE" = "gitlab" ]; then
            emit "run" "\"step\":\"pr-create\",\"branch\":\"$BRANCH\",\"forge\":\"gitlab\",\"message\":\"Auto MR creation failed. Create MR manually: git push -u origin $BRANCH && glab mr create --target-branch $DEFAULT_BRANCH. Save URL to state.json .prUrl. Then: complete pr-create\""
          else
            emit "run" "\"step\":\"pr-create\",\"branch\":\"$BRANCH\",\"forge\":\"github\",\"message\":\"Auto PR creation failed. Create PR manually: git push -u origin $BRANCH && gh pr create --base $DEFAULT_BRANCH. Save URL to state.json .prUrl. Then: complete pr-create\""
          fi
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
        emit_spawn "research" "templates/researcher.md" "researcher" 1800 "researcher"
        exit 0
        ;;

      planner)
        if [ ! -f "research/findings.md" ]; then
          emit_blocked "planner" "research/findings.md missing"
        fi
        emit_progress_before_spawn "planner" "Spawning planner (stories + wiring)" "~5-10 min"
        emit_spawn "planner" "templates/planner.md" "planner" 1800 "planner"
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

        emit_progress_before_spawn "story-execute" "Phase $((PHASE_INDEX+1))/$TOTAL_PHASES ($PHASE_NAME): Story $((DONE_COUNT+1))/$STORY_COUNT — $CURRENT_STORY: $STORY_TITLE" "~${EST_MINUTES} min"
        emit_spawn "story-execute" "templates/worker.md" "coder" "$TIMEOUT" "coder-$CURRENT_STORY"
        exit 0
        ;;

      story-verify)
        # Main agent verifies: correct branch + commit exists + quality gate passes
        CURRENT_STORY=$(get_current_story)
        BRANCH=$(json_get '.project.branch // "main"')
        emit "run" "\"step\":\"story-verify\",\"story\":\"$CURRENT_STORY\",\"branch\":\"$BRANCH\",\"message\":\"Verify $CURRENT_STORY on branch $BRANCH: 1) Run: git checkout $BRANCH 2) Run: git branch --show-current (must output $BRANCH) 3) Run: git log --oneline -5 and check $CURRENT_STORY appears 4) Run: ./scripts/quality-gate.sh --scope story. If branch wrong, commit missing, or gate fails → complete story-verify blocked <reason>. If all good → complete story-verify.\",\"onComplete\":\"complete story-verify\",\"onBlocked\":\"complete story-verify blocked <reason>\""
        exit 0
        ;;

      phase-review)
        CURRENT_PHASE=$(get_current_phase)
        PHASE_NAME=$(jq -r ".phases[] | select(.id==\"$CURRENT_PHASE\") | .name" prd.json 2>/dev/null)
        emit_progress_before_spawn "phase-review" "Reviewing phase: $PHASE_NAME" "~10-20 min"
        emit_spawn "phase-review" "templates/reviewer.md" "tester" 1800 "reviewer-$CURRENT_PHASE"
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
        emit_spawn "final-review" "templates/final-review.md" "reviewer" 2700 "final-reviewer"
        exit 0
        ;;

      pr-review)
        PR_URL=$(json_get '.prUrl // ""')
        PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$' || true)
        if [ -z "$PR_NUMBER" ]; then
          emit_blocked "pr-review" "Could not extract PR number from URL: $PR_URL"
        fi
        emit_progress_before_spawn "pr-review" "Fresh PR review (honest diff check)" "~10-15 min"
        emit_spawn "pr-review" "templates/pr-reviewer.md" "reviewer" 1800 "pr-reviewer"
        exit 0
        ;;

      ci-monitor)
        PR_URL=$(json_get '.prUrl // ""')
        PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$' || true)
        if [ -z "$PR_NUMBER" ]; then
          emit_blocked "ci-monitor" "Could not extract PR number from URL: $PR_URL"
        fi
        emit_progress_before_spawn "ci-monitor" "Monitoring CI and fixing failures" "~10-60 min"
        emit_spawn "ci-monitor" "templates/ci-monitor.md" "coder" 3600 "ci-monitor"
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
