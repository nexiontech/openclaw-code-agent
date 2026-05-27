import { spawn, type ChildProcess } from "node:child_process";
import { randomUUID } from "node:crypto";

export type SessionStatus =
  | "running"
  | "completed"
  | "failed"
  | "killed"
  | "timeout";

export interface CodeSession {
  id: string;
  name: string;
  harness: "claude-code" | "codex";
  status: SessionStatus;
  workdir: string;
  worktreePath?: string;
  exitCode: number | null;
  startedAt: Date;
  endedAt?: Date;
  runtimeSeconds: number;
  getOutput(tailLines?: number): string;
  sendInput(text: string): void;
  kill(): void;
}

interface ManagedSession {
  id: string;
  name: string;
  harness: "claude-code" | "codex";
  status: SessionStatus;
  workdir: string;
  worktreePath?: string;
  exitCode: number | null;
  startedAt: Date;
  endedAt?: Date;
  process: ChildProcess;
  outputBuffer: string[];
  timeoutHandle?: ReturnType<typeof setTimeout>;
}

export interface LaunchOptions {
  name: string;
  command: string;
  args: string[];
  workdir: string;
  harness: "claude-code" | "codex";
  prompt?: string; // For claude-code, piped to stdin
  timeoutSeconds: number;
  worktreePath?: string;
}

export class SessionManager {
  private sessions = new Map<string, ManagedSession>();

  async launch(opts: LaunchOptions): Promise<CodeSession> {
    const id = randomUUID().slice(0, 8);

    const child = spawn(opts.command, opts.args, {
      cwd: opts.workdir,
      stdio: ["pipe", "pipe", "pipe"],
      env: {
        ...process.env,
        // Ensure non-interactive mode
        CI: "true",
        TERM: "dumb",
      },
      detached: false,
    });

    const session: ManagedSession = {
      id,
      name: opts.name,
      harness: opts.harness,
      status: "running",
      workdir: opts.workdir,
      worktreePath: opts.worktreePath,
      exitCode: null,
      startedAt: new Date(),
      process: child,
      outputBuffer: [],
    };

    // Capture stdout
    child.stdout?.on("data", (chunk: Buffer) => {
      const lines = chunk.toString("utf-8").split("\n");
      for (const line of lines) {
        if (line.length > 0) {
          session.outputBuffer.push(line);
          // Keep buffer bounded at 10000 lines
          if (session.outputBuffer.length > 10000) {
            session.outputBuffer.splice(0, session.outputBuffer.length - 10000);
          }
        }
      }
    });

    // Capture stderr (merge into output)
    child.stderr?.on("data", (chunk: Buffer) => {
      const lines = chunk.toString("utf-8").split("\n");
      for (const line of lines) {
        if (line.length > 0) {
          session.outputBuffer.push(`[stderr] ${line}`);
          if (session.outputBuffer.length > 10000) {
            session.outputBuffer.splice(0, session.outputBuffer.length - 10000);
          }
        }
      }
    });

    // Handle process exit
    child.on("close", (code) => {
      session.exitCode = code;
      session.endedAt = new Date();
      if (session.status === "running") {
        session.status = code === 0 ? "completed" : "failed";
      }
      if (session.timeoutHandle) {
        clearTimeout(session.timeoutHandle);
      }
    });

    child.on("error", (err) => {
      session.outputBuffer.push(`[error] Process error: ${err.message}`);
      session.status = "failed";
      session.endedAt = new Date();
    });

    // Send prompt via stdin for claude-code
    if (opts.prompt && child.stdin) {
      child.stdin.write(opts.prompt);
      child.stdin.end();
    }

    // Set timeout
    if (opts.timeoutSeconds > 0) {
      session.timeoutHandle = setTimeout(() => {
        if (session.status === "running") {
          session.status = "timeout";
          session.endedAt = new Date();
          session.outputBuffer.push(
            `[system] Session timed out after ${opts.timeoutSeconds}s`,
          );
          child.kill("SIGTERM");
          // Force kill after 10s if still alive
          setTimeout(() => {
            if (!child.killed) {
              child.kill("SIGKILL");
            }
          }, 10000);
        }
      }, opts.timeoutSeconds * 1000);
    }

    this.sessions.set(id, session);

    return this.toPublic(session);
  }

  get(id: string): CodeSession | undefined {
    const session = this.sessions.get(id);
    if (!session) return undefined;
    return this.toPublic(session);
  }

  list(includeCompleted: boolean): CodeSession[] {
    const results: CodeSession[] = [];
    for (const session of this.sessions.values()) {
      if (!includeCompleted && session.status !== "running") continue;
      results.push(this.toPublic(session));
    }
    return results;
  }

  private toPublic(session: ManagedSession): CodeSession {
    const now = new Date();
    const endTime = session.endedAt ?? now;
    const runtimeSeconds = Math.round(
      (endTime.getTime() - session.startedAt.getTime()) / 1000,
    );

    return {
      id: session.id,
      name: session.name,
      harness: session.harness,
      status: session.status,
      workdir: session.workdir,
      worktreePath: session.worktreePath,
      exitCode: session.exitCode,
      startedAt: session.startedAt,
      endedAt: session.endedAt,
      runtimeSeconds,
      getOutput(tailLines = 100) {
        const buf = session.outputBuffer;
        const start = Math.max(0, buf.length - tailLines);
        return buf.slice(start).join("\n");
      },
      sendInput(text: string) {
        if (session.process.stdin && !session.process.stdin.destroyed) {
          session.process.stdin.write(text + "\n");
        }
      },
      kill() {
        session.status = "killed";
        session.endedAt = new Date();
        session.process.kill("SIGTERM");
        setTimeout(() => {
          if (!session.process.killed) {
            session.process.kill("SIGKILL");
          }
        }, 5000);
      },
    };
  }
}
