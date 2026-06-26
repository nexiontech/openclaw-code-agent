import { describe, expect, it } from "vitest";
import entry from "./index.js";
import { getToolPluginMetadata } from "openclaw/plugin-sdk/tool-plugin";

const EXPECTED_TOOLS = [
  "agent_launch",
  "agent_output",
  "agent_respond",
  "agent_sessions",
  "agent_kill",
  "agent_merge",
  "agent_pr",
];

describe("code-agent", () => {
  it("declares correct tool names", () => {
    expect(
      getToolPluginMetadata(entry)?.tools.map((tool) => tool.name),
    ).toEqual(EXPECTED_TOOLS);
  });

  it("plugin id is code-agent", () => {
    expect(getToolPluginMetadata(entry)?.id).toBe("code-agent");
  });
});
