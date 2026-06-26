import { Type } from "typebox";
import { defineToolPlugin } from "openclaw/plugin-sdk/tool-plugin";
import { SessionManager, type CodeSession } from "./session-manager.js";

const sessionManager = new SessionManager();

const HarnessEnum = Type.Union([
  Type.Literal("claude-code"),
  Type.Literal("codex"),
]);

const PermissionModeEnum = Type.Union([
  Type.Literal("bypassPermissions"),
  Type.Literal("plan"),
  Type.Literal("default"),
]);

const WorktreeStrategyEnum = Type.Union([
  Type.Literal("auto"),
  Type.Literal("delegate"), // alias for "auto" — the plugin creates the worktree
  Type.Literal("off"),
]);

export default defineToolPlugin({
  id: "code-agent",
  name: "Code Agent",
  description:
    "Launch and manage Claude Code or Codex as background coding sessions. " +
    "Orchestrate autonomous coding work with plan approval, worktree isolation, and lifecycle management.",
  configSchema: Type.Object({
    claudePath: Type.Optional(
      Type.String({
        description:
          'Path to Claude Code CLI binary. Default: "claude" (from PATH).',
      }),
    ),
    codexPath: Type.Optional(
      Type.String({
        description:
          'Path to Codex CLI binary. Default: "codex" (from PATH).',
      }),
    ),
    defaultHarness: Type.Optional(
      Type.Union([Type.Literal("claude-code"), Type.Literal("codex")], {
        description: "Default coding harness. Default: claude-code.",
      }),
    ),
    defaultTimeoutSeconds: Type.Optional(
      Type.Number({
        description:
          "Default session timeout in seconds. Default: 1800 (30 min).",
      }),
    ),
    worktreeBase: Type.Optional(
      Type.String({
        description:
          'Base directory for worktrees. Default: "<repo>/.worktrees".',
      }),
    ),
  }),
  tools: (tool) => [
    // ─── agent_launch ───
    tool({
      name: "agent_launch",
      description:
        "Launch a Claude Code or Codex coding session as a background process. " +
        "Returns a session ID for monitoring. The agent works autonomously on the given prompt.",
      parameters: Type.Object({
        prompt: Type.String({
          description: "The coding task prompt for the agent.",
        }),
        name: Type.String({
          description:
            'Human-readable session name, e.g. "story-S1-auth".',
        }),
        workdir: Type.String({
          description: "Absolute path to the working directory (repo root).",
        }),
        harness: Type.Optional(
          Type.Union(
            [Type.Literal("claude-code"), Type.Literal("codex")],
            {
              description:
                'Coding harness to use. Default: config default or "claude-code".',
            },
          ),
        ),
        permission_mode: Type.Optional(
          Type.Union(
            [
              Type.Literal("bypassPermissions"),
              Type.Literal("default"),
            ],
            {
              description:
                'Permission mode. "bypassPermissions" runs unattended. Default: "bypassPermissions".',
            },
          ),
        ),
        worktree_strategy: Type.Optional(
          Type.Union([Type.Literal("auto"), Type.Literal("delegate"), Type.Literal("off")], {
            description:
              '"auto"/"delegate" creates a git worktree for isolation, "off" works in the given workdir. Default: "off".',
          }),
        ),
        branch: Type.Optional(
          Type.String({
            description:
              'Git branch to checkout/create. Required when worktree_strategy is "auto" or "delegate".',
          }),
        ),
        timeout_seconds: Type.Optional(
          Type.Number({
            description: "Session timeout in seconds. Default: 1800.",
          }),
        ),
        model: Type.Optional(
          Type.String({
            description:
              'Model override, e.g. "claude-opus-4-6" or "o3". Passed to the CLI.',
          }),
        ),
        worktree_pr_target_repo: Type.Optional(
          Type.String({
            description:
              'Target repo for PRs in fork workflows, e.g. "owner/repo". Passed to agent_pr.',
          }),
        ),
      }),
      async execute(params, config) {
        const harness =
          params.harness ?? config.defaultHarness ?? "claude-code";
        const permissionMode =
          params.permission_mode ?? "bypassPermissions";
        // Normalise "delegate" → "auto": both mean the plugin manages the worktree.
        const worktreeStrategy =
          params.worktree_strategy === "delegate"
            ? "auto"
            : (params.worktree_strategy ?? "off");
        const timeoutSeconds =
          params.timeout_seconds ??
          config.defaultTimeoutSeconds ??
          1800;

        const claudePath = config.claudePath ?? "claude";
        const codexPath = config.codexPath ?? "codex";

        let effectiveWorkdir = params.workdir;

        // Handle worktree creation
        if (worktreeStrategy === "auto") {
          // For "auto" strategy: branch is mandatory — caller controls the branch name.
          // For "delegate" strategy (normalised to "auto" above): auto-derive from session name
          // when branch is not provided, matching how the skill uses `worktree_strategy: "delegate"`.
          const effectiveBranch =
            params.branch ??
            (params.worktree_strategy === "delegate"
              ? `agent/${params.name.replace(/[^a-zA-Z0-9-_]/g, "-")}`
              : undefined);

          if (!effectiveBranch) {
            return {
              error:
                'worktree_strategy "auto" requires a "branch" parameter. Use "delegate" to auto-derive the branch from the session name.',
            };
          }

          const { execSync } = await import("node:child_process");
          const worktreeBase =
            config.worktreeBase ?? `${params.workdir}/.worktrees`;
          const slug = effectiveBranch.replace(/[^a-zA-Z0-9-_]/g, "-");
          effectiveWorkdir = `${worktreeBase}/${slug}`;

          try {
            execSync(
              `git -C "${params.workdir}" worktree add "${effectiveWorkdir}" -b "${effectiveBranch}" 2>/dev/null || git -C "${params.workdir}" worktree add "${effectiveWorkdir}" "${effectiveBranch}"`,
              { stdio: "pipe" },
            );
          } catch {
            // Worktree may already exist — continue if the path is there
            const { existsSync } = await import("node:fs");
            if (!existsSync(effectiveWorkdir)) {
              return {
                error: `Failed to create worktree at ${effectiveWorkdir}`,
              };
            }
          }
        }

        // Build CLI command
        let command: string;
        let args: string[];

        if (harness === "claude-code") {
          command = claudePath;
          args = ["--print"];
          // Use string cast to prevent TS narrowing from rejecting the "plan"
          // branch when typebox doesn't emit a proper TS union for the schema.
          const pm = permissionMode as string;
          if (pm === "bypassPermissions") {
            args.unshift("--dangerously-skip-permissions");
          } else if (pm === "plan") {
            // Plan mode: Claude Code proposes a plan and waits for approval before
            // executing any tools.  Useful for gated autonomous dispatch.
            args.push("--permission-mode", "plan");
          }
          if (params.model) {
            args.push("--model", params.model);
          }
          // Prompt goes via stdin
        } else {
          // codex
          command = codexPath;
          args = ["exec"];
          if (permissionMode === "bypassPermissions") {
            args.push("--dangerously-bypass-approvals-and-sandbox");
          }
          if (params.model) {
            args.push("--model", params.model);
          }
          // Prompt goes as positional arg
          args.push(params.prompt);
        }

        const session = await sessionManager.launch({
          name: params.name,
          command,
          args,
          workdir: effectiveWorkdir,
          harness,
          prompt: harness === "claude-code" ? params.prompt : undefined,
          timeoutSeconds,
          worktreePath:
            worktreeStrategy === "auto" ? effectiveWorkdir : undefined,
        });

        return {
          session_id: session.id,
          name: session.name,
          harness,
          workdir: effectiveWorkdir,
          worktree_pr_target_repo: params.worktree_pr_target_repo,
          status: session.status,
          message: `Launched ${harness} session "${params.name}" (${session.id}). Use agent_output to check progress.`,
        };
      },
    }),

    // ─── agent_output ───
    tool({
      name: "agent_output",
      description:
        "Get the current output from a running or completed coding session.",
      parameters: Type.Object({
        session_id: Type.String({
          description: "Session ID from agent_launch.",
        }),
        tail: Type.Optional(
          Type.Number({
            description:
              "Number of lines from the end to return. Default: 100.",
          }),
        ),
      }),
      async execute({ session_id, tail }) {
        const session = sessionManager.get(session_id);
        if (!session) {
          return { error: `Session ${session_id} not found.` };
        }

        const lines = tail ?? 100;
        const output = session.getOutput(lines);

        return {
          session_id,
          name: session.name,
          status: session.status,
          harness: session.harness,
          exit_code: session.exitCode,
          runtime_seconds: session.runtimeSeconds,
          output,
        };
      },
    }),

    // ─── agent_respond ───
    tool({
      name: "agent_respond",
      description:
        "Send input/response to a running coding session (e.g. answer a question or approve a plan).",
      parameters: Type.Object({
        session_id: Type.String({
          description: "Session ID from agent_launch.",
        }),
        input: Type.String({
          description: "Text to send to the session's stdin.",
        }),
      }),
      async execute({ session_id, input }) {
        const session = sessionManager.get(session_id);
        if (!session) {
          return { error: `Session ${session_id} not found.` };
        }
        if (session.status !== "running") {
          return {
            error: `Session ${session_id} is ${session.status}, cannot send input.`,
          };
        }

        session.sendInput(input);

        return {
          session_id,
          sent: input,
          message: `Input sent to session "${session.name}".`,
        };
      },
    }),

    // ─── agent_sessions ───
    tool({
      name: "agent_sessions",
      description: "List all active and recent coding sessions.",
      parameters: Type.Object({
        include_completed: Type.Optional(
          Type.Boolean({
            description:
              "Include completed/failed sessions. Default: false.",
          }),
        ),
      }),
      async execute({ include_completed }) {
        const sessions = sessionManager.list(include_completed ?? false);

        return {
          count: sessions.length,
          sessions: sessions.map((s) => ({
            session_id: s.id,
            name: s.name,
            harness: s.harness,
            status: s.status,
            workdir: s.workdir,
            exit_code: s.exitCode,
            runtime_seconds: s.runtimeSeconds,
            started_at: s.startedAt.toISOString(),
          })),
        };
      },
    }),

    // ─── agent_kill ───
    tool({
      name: "agent_kill",
      description: "Kill a running coding session.",
      parameters: Type.Object({
        session_id: Type.String({
          description: "Session ID to kill.",
        }),
      }),
      async execute({ session_id }) {
        const session = sessionManager.get(session_id);
        if (!session) {
          return { error: `Session ${session_id} not found.` };
        }

        session.kill();

        return {
          session_id,
          name: session.name,
          status: "killed",
          message: `Session "${session.name}" killed.`,
        };
      },
    }),

    // ─── agent_merge ───
    tool({
      name: "agent_merge",
      description:
        "Merge a worktree branch back into the target branch and clean up the worktree.",
      parameters: Type.Object({
        session_id: Type.String({
          description: "Session ID that used a worktree.",
        }),
        target_branch: Type.Optional(
          Type.String({
            description: 'Branch to merge into. Default: "main".',
          }),
        ),
        delete_worktree: Type.Optional(
          Type.Boolean({
            description:
              "Delete the worktree after merge. Default: true.",
          }),
        ),
      }),
      async execute({ session_id, target_branch, delete_worktree }) {
        const session = sessionManager.get(session_id);
        if (!session) {
          return { error: `Session ${session_id} not found.` };
        }
        if (!session.worktreePath) {
          return {
            error: `Session ${session_id} was not launched with worktree strategy.`,
          };
        }

        const { execSync } = await import("node:child_process");
        const target = target_branch ?? "main";
        const workdir = session.workdir;

        try {
          // Get the branch name from the worktree
          const branch = execSync("git branch --show-current", {
            cwd: session.worktreePath,
            encoding: "utf-8",
          }).trim();

          // Switch to target branch in the main repo
          execSync(`git checkout ${target}`, {
            cwd: workdir,
            stdio: "pipe",
          });
          execSync(`git merge ${branch}`, {
            cwd: workdir,
            stdio: "pipe",
          });

          // Optionally clean up worktree
          if (delete_worktree !== false) {
            execSync(`git worktree remove "${session.worktreePath}" --force`, {
              cwd: workdir,
              stdio: "pipe",
            });
          }

          return {
            session_id,
            merged: branch,
            into: target,
            worktree_removed: delete_worktree !== false,
            message: `Merged ${branch} into ${target}.`,
          };
        } catch (err) {
          return {
            error: `Merge failed: ${err instanceof Error ? err.message : String(err)}`,
          };
        }
      },
    }),

    // ─── agent_pr ───
    tool({
      name: "agent_pr",
      description:
        "Create a PR/MR from the session's branch. Auto-detects GitHub (gh) vs GitLab (glab).",
      parameters: Type.Object({
        session_id: Type.String({
          description: "Session ID.",
        }),
        title: Type.String({
          description: "PR/MR title.",
        }),
        body: Type.Optional(
          Type.String({
            description: "PR/MR body/description.",
          }),
        ),
        base: Type.Optional(
          Type.String({
            description: 'Target branch. Default: "main".',
          }),
        ),
        draft: Type.Optional(
          Type.Boolean({
            description: "Create as draft. Default: false.",
          }),
        ),
      }),
      async execute({ session_id, title, body, base, draft }) {
        const session = sessionManager.get(session_id);
        if (!session) {
          return { error: `Session ${session_id} not found.` };
        }

        const { execSync } = await import("node:child_process");
        const cwd = session.worktreePath ?? session.workdir;

        try {
          // Push the branch
          const branch = execSync("git branch --show-current", {
            cwd,
            encoding: "utf-8",
          }).trim();
          execSync(`git push -u origin ${branch}`, {
            cwd,
            stdio: "pipe",
          });

          // Detect forge
          const remoteUrl = execSync("git remote get-url origin", {
            cwd,
            encoding: "utf-8",
          }).trim();
          const isGitlab = /gitlab/i.test(remoteUrl);
          const targetBase = base ?? "main";

          let prUrl: string;
          if (isGitlab) {
            const args = [
              "mr",
              "create",
              "--title",
              JSON.stringify(title),
              "--target-branch",
              targetBase,
              "--remove-source-branch",
              "--yes",
            ];
            if (body) args.push("--description", JSON.stringify(body));
            if (draft) args.push("--draft");
            const out = execSync(`glab ${args.join(" ")}`, {
              cwd,
              encoding: "utf-8",
            });
            prUrl =
              out.match(/https:\/\/[^\s]+/)?.[0] ?? "MR created (URL not captured)";
          } else {
            const args = [
              "pr",
              "create",
              "--title",
              JSON.stringify(title),
              "--base",
              targetBase,
            ];
            if (body) args.push("--body", JSON.stringify(body));
            if (draft) args.push("--draft");
            const out = execSync(`gh ${args.join(" ")}`, {
              cwd,
              encoding: "utf-8",
            });
            prUrl =
              out.match(/https:\/\/github\.com[^\s]+/)?.[0] ??
              "PR created (URL not captured)";
          }

          return {
            session_id,
            branch,
            forge: isGitlab ? "gitlab" : "github",
            pr_url: prUrl,
            message: `PR/MR created: ${prUrl}`,
          };
        } catch (err) {
          return {
            error: `PR creation failed: ${err instanceof Error ? err.message : String(err)}`,
          };
        }
      },
    }),

    // ─── agent_worktree_status ───
    tool({
      name: "agent_worktree_status",
      description:
        "List all git worktrees in a repo and their associated session lifecycle state.",
      parameters: Type.Object({
        workdir: Type.String({
          description: "Absolute path to the repo root.",
        }),
      }),
      async execute({ workdir }) {
        const { execSync } = await import("node:child_process");
        try {
          const raw = execSync("git worktree list --porcelain", {
            cwd: workdir,
            encoding: "utf-8",
          });

          // Parse porcelain output into structured records
          const worktrees: Array<{
            path: string;
            branch: string | null;
            commit: string | null;
            bare: boolean;
          }> = [];

          let current: { path?: string; branch?: string; commit?: string; bare?: boolean } = {};
          for (const line of raw.split("\n")) {
            if (line.startsWith("worktree ")) {
              if (current.path) worktrees.push({ path: current.path, branch: current.branch ?? null, commit: current.commit ?? null, bare: current.bare ?? false });
              current = { path: line.slice("worktree ".length).trim() };
            } else if (line.startsWith("HEAD ")) {
              current.commit = line.slice("HEAD ".length).trim();
            } else if (line.startsWith("branch ")) {
              current.branch = line.slice("branch refs/heads/".length).trim();
            } else if (line === "bare") {
              current.bare = true;
            }
          }
          if (current.path) worktrees.push({ path: current.path, branch: current.branch ?? null, commit: current.commit ?? null, bare: current.bare ?? false });

          // Enrich with session data
          const sessions = sessionManager.list(true);
          const enriched = worktrees.map((wt) => {
            const linked = sessions.find((s) => s.worktreePath === wt.path);
            return {
              ...wt,
              session_id: linked?.id ?? null,
              session_status: linked?.status ?? null,
            };
          });

          return { count: enriched.length, worktrees: enriched };
        } catch (err) {
          return {
            error: `Failed to list worktrees: ${err instanceof Error ? err.message : String(err)}`,
          };
        }
      },
    }),

    // ─── agent_worktree_cleanup ───
    tool({
      name: "agent_worktree_cleanup",
      description:
        "Remove completed/failed/killed worktrees from a repo. By default, only removes worktrees whose associated session has ended.",
      parameters: Type.Object({
        workdir: Type.String({
          description: "Absolute path to the repo root.",
        }),
        force: Type.Optional(
          Type.Boolean({
            description:
              "Also remove worktrees whose session is still running. Default: false.",
          }),
        ),
      }),
      async execute({ workdir, force }) {
        const { execSync } = await import("node:child_process");
        const sessions = sessionManager.list(true);

        const raw = execSync("git worktree list --porcelain", {
          cwd: workdir,
          encoding: "utf-8",
        });

        const worktreePaths: string[] = [];
        for (const line of raw.split("\n")) {
          if (line.startsWith("worktree ")) {
            worktreePaths.push(line.slice("worktree ".length).trim());
          }
        }

        const removed: string[] = [];
        const skipped: string[] = [];

        for (const wtPath of worktreePaths.slice(1)) {
          // Skip the main worktree (first entry)
          const linked = sessions.find((s) => s.worktreePath === wtPath);
          const canRemove = !linked || linked.status !== "running" || force === true;

          if (!canRemove) {
            skipped.push(wtPath);
            continue;
          }

          try {
            execSync(`git worktree remove "${wtPath}" --force`, {
              cwd: workdir,
              stdio: "pipe",
            });
            removed.push(wtPath);
          } catch {
            skipped.push(wtPath);
          }
        }

        return {
          removed_count: removed.length,
          skipped_count: skipped.length,
          removed,
          skipped,
        };
      },
    }),

    // ─── agent_stats ───
    tool({
      name: "agent_stats",
      description:
        "Return usage and runtime statistics for all coding sessions in this gateway process lifecycle.",
      parameters: Type.Object({}),
      async execute() {
        const all = sessionManager.list(true);

        const byStatus: Record<string, number> = {};
        let totalRuntimeSeconds = 0;
        const byHarness: Record<string, number> = { "claude-code": 0, codex: 0 };

        for (const s of all) {
          byStatus[s.status] = (byStatus[s.status] ?? 0) + 1;
          totalRuntimeSeconds += s.runtimeSeconds;
          byHarness[s.harness] = (byHarness[s.harness] ?? 0) + 1;
        }

        return {
          total_sessions: all.length,
          by_status: byStatus,
          by_harness: byHarness,
          total_runtime_seconds: totalRuntimeSeconds,
          average_runtime_seconds:
            all.length > 0 ? Math.round(totalRuntimeSeconds / all.length) : 0,
        };
      },
    }),
  ],
});
