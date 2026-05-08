# Skills

A collection of skills for coding agents.

A skill is a self-contained bundle of instructions — and optionally scripts, references, or assets — that an agent can load on demand to perform a specialized task.

## Supported agents

The `SKILL.md` format is consumed natively by:

- **Claude Code** (Anthropic CLI) — drop a skill into `~/.claude/skills/<name>/`.
- **Claude Agent SDK** — register the skill directory with the SDK loader.

The markdown body of a skill is portable and can be adapted to other coding agents that support custom instructions or rules:

- **Cursor** — paste the body into a `.cursor/rules/<name>.mdc` file (Cursor's frontmatter uses `globs` instead of `description`).
- **GitHub Copilot** — adapt the instructions into `.github/copilot-instructions.md` or repo-level custom instructions.
- **Aider** — reference the skill body from `.aider.conf.yml` or include it in a conventions file.
- **Continue** — wire the skill into a custom slash command or context provider in `~/.continue/config.json`.
- **Cody (Sourcegraph)** — adapt to a custom command in `.vscode/cody.json`.
- **Windsurf** — paste into `.windsurfrules` at the repo root.
- **OpenAI Codex CLI / Goose / Gemini CLI** — load the skill body as a system prompt or pre-prompt.

When porting, you usually only need to adjust the frontmatter; the instructions themselves are agent-agnostic if written cleanly.

## Available skills

| Skill                                                                  | What it does                                                                                          |
| :--------------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------- |
| [`indykite-agent-gateway`](skills/indykite-agent-gateway/SKILL.md)     | Deploy and configure Indykite Agent Gateway (IAG) in front of A2A agents to enforce caller, workflow, and delegation-chain checks. |
| [`indykite-mcp-server`](skills/indykite-mcp-server/SKILL.md)           | Call the IndyKite MCP server (initialize session, list tools, call AuthZEN and ContX IQ tools) and configure the MCP server endpoint for a project. |
| [`indykite-ciq-read`](skills/indykite-ciq-read/SKILL.md)               | Author a read-only IndyKite ContX IQ (CIQ) policy and Knowledge Query, then run it via `POST /contx-iq/v1/execute`. |

## Structure

Each skill lives in its own directory with a `SKILL.md` file:

```text
/
├── skill-name/
│   ├── SKILL.md
│   ├── scripts/      (optional)
│   ├── references/   (optional)
│   └── assets/       (optional)
└── another-skill/
    └── SKILL.md
```

## SKILL.md format

```markdown
---
name: your-skill-name
description: What it does. Use when [trigger conditions].
---

# Your Skill Name

## Instructions

### Step 1: ...
### Step 2: ...
```

## Conventions

- Folder names are kebab-case (e.g. `my-cool-skill`).
- The file must be named exactly `SKILL.md` (case-sensitive).
- The `description` should state both what the skill does and when to invoke it — agents use it to decide whether the skill is relevant.
- Keep `SKILL.md` focused on core instructions; put longer docs in `references/` and helper code in `scripts/`.

## Installing

Copy or symlink a skill directory into the agent's expected location:

| Agent             | Location                                        |
| :---------------- | :---------------------------------------------- |
| Claude Code       | `~/.claude/skills/<skill-name>/`                |
| Claude Agent SDK  | wherever you point the SDK's skill loader       |
| Cursor            | `.cursor/rules/<skill-name>.mdc` (per repo)     |
| GitHub Copilot    | `.github/copilot-instructions.md` (per repo)    |
| Windsurf          | `.windsurfrules` (per repo)                     |
| Continue / Cody   | configured via the agent's settings file        |

For agents that expect a single instruction file rather than a folder, use only the body of `SKILL.md` (drop the YAML frontmatter or convert it to the agent's own format).
