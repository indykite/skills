# Skills

A collection of skills for coding agents, focused on [IndyKite](https://indykite.ai) — graph-based identity, authorization, and AI-agent integration. Manage your IndyKite project in the Hub UI ([eu.hub.indykite.com](https://eu.hub.indykite.com/) / [us.hub.indykite.com](https://us.hub.indykite.com/)); developer docs at [developer.indykite.com](https://developer.indykite.com/).

A skill is a self-contained bundle of instructions — and optionally scripts, references, or assets — that an agent can load on demand to perform a specialized task.

## Available skills

| Skill                                                                  | What it does                                                                                          |
| :--------------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------- |
| [`indykite-agent-gateway`](indykite-agent-gateway/SKILL.md)     | Deploy and configure Indykite Agent Gateway (IAG) in front of A2A agents to enforce caller, workflow, and delegation-chain checks. |
| [`indykite-mcp-server`](indykite-mcp-server/SKILL.md)           | Call the IndyKite MCP server (initialize session, list tools, call AuthZEN and ContX IQ tools) and configure the MCP server endpoint for a project. |
| [`indykite-ciq-read`](indykite-ciq-read/SKILL.md)               | Author a read-only IndyKite ContX IQ (CIQ) policy and Knowledge Query, then run it via `POST /contx-iq/v1/execute`. |

## Supported agents

The skills here are installed by the [`skills`](https://skills.sh) CLI, which supports **50+ agents** — Claude Code, Cursor, GitHub Copilot, Continue, Windsurf, Cline, Roo, OpenCode, Goose, Aider-Desk, Codex CLI, Gemini CLI, and many others. Run `npx skills add <repo> --agent <name>` for a specific agent, or omit `--agent` to install into every supported agent detected in the current environment. Passing an unknown name (e.g. `--agent foobar`) makes the CLI print the full valid list.

**Native `SKILL.md` support** — meaning the agent reads the YAML frontmatter and activates skills *automatically* by matching the user's prompt against `description` — is a property of the agent, not the CLI. **Claude Code** is the canonical example. Other agents may already have native skill support, or they activate the installed skill via slash commands, explicit selection, or pasted instructions; check the agent's own documentation if automatic activation matters for your workflow.

## Quickstart

The fastest way from zero to a skill activating in your agent:

```bash
# 1. Install one skill from this repo (project-scoped, into the right per-agent location)
npx skills add indykite/skills --skill indykite-mcp-server --agent claude-code

# 2. Restart the agent so it picks up the new skill directory.

# 3. Verify it loaded
npx skills list
```

Then, in the agent, ask something the skill's description matches — for `indykite-mcp-server`, that is anything about initializing an MCP session against `eu.mcp.indykite.com` / `us.mcp.indykite.com`, calling `authzen_evaluate` / `ciq_execute`, or debugging a `401` from the MCP server. The agent should pick the skill up automatically; if it doesn't, see [How skills activate](#how-skills-activate) below.

To install **all** the skills in this repo at once, drop the `--skill` and `--agent` flags:

```bash
npx skills add indykite/skills
```

## Installing

The recommended path is the [`skills`](https://skills.sh) CLI, which installs the same directory into the right location for whichever agent(s) you use:

```bash
# All skills in this repo, into the project's local agent directories
npx skills add indykite/skills

# All skills, globally for the current user
npx skills add indykite/skills -g

# Just one skill, into one agent
npx skills add indykite/skills --skill indykite-mcp-server --agent claude-code

# Show what's in the repo without installing
npx skills add indykite/skills --list
```

Useful flags:

- `-g, --global` — install at user scope instead of project scope.
- `-a, --agent <name>` — limit to one or more agents (use `*` for all).
- `-s, --skill <name>` — limit to one or more skills.
- `--copy` — copy files instead of symlinking (the default is a symlink so updates propagate).
- `-y, --yes` — skip confirmation prompts (handy in CI).

Restart the agent (or reload its config) after installing so it picks up the new skill directory.

### Manual installation

If you don't want the CLI, copy or symlink the skill directory into the agent's expected location.

For **Claude Code**, that location is `~/.claude/skills/<skill-name>/` (user scope) or `.claude/skills/<skill-name>/` (project scope) — Claude Code reads `SKILL.md` directly from there.

For any other agent, consult that agent's own documentation for where it expects rules, instructions, or skills files. Most agents that don't read `SKILL.md` natively expect the *body* of the file (everything after the YAML frontmatter) pasted into their own rule format.

## How skills activate

A skill is **passive until invoked**. Most supported agents activate skills *automatically* by matching the user's prompt against each installed skill's `description` field — the one-line summary in `SKILL.md`'s frontmatter. When the description fits the request, the agent loads the rest of the skill into context before answering. The `## When to use` section in each `SKILL.md` is read by the agent (not just the human) and is what determines whether activation actually fires for a given prompt — that is why the existing skills here list both positive triggers and explicit anti-triggers.

If you expect a skill to activate but it doesn't, check three things:

1. **The agent loaded it.** Ask the agent which skills are available, or run `npx skills list` (or `npx skills ls`) to see what is installed for the current scope. A skill that isn't installed cannot activate.
2. **The description fits the prompt.** Open `SKILL.md` and re-read the `description` and `## When to use`. Vague descriptions get vague triggering — sharpen the wording, reinstall, and try again. If two skills could plausibly match the same prompt, the agent will pick one and you may need to disambiguate by tightening one of the descriptions.
3. **Manual fallback.** Most agents let you invoke a skill by name (e.g. `/<skill-name>` in Claude Code, or selecting it explicitly in Cursor / Copilot). Use that when automatic routing is uncertain — it also tells you whether the skill itself is loaded and working independently of the description match.

To **disable** a misbehaving skill: remove the directory (`npx skills remove <name>`, or delete it from the agent's skills folder), or set `metadata.internal: true` in its frontmatter so it stays installed but is hidden from automatic discovery (it will only surface if `INSTALL_INTERNAL_SKILLS=1` is set).

## Authoring a skill

Reference for anyone writing or forking a skill in this repo. The full submission flow lives in [`contributing.md`](contributing.md) — this section is the at-a-glance summary.

### Structure

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

### SKILL.md format

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

### Conventions

- Folder names are kebab-case (e.g. `my-cool-skill`).
- The file must be named exactly `SKILL.md` (case-sensitive).
- The `description` should state both what the skill does and when to invoke it — agents use it to decide whether the skill is relevant.
- Keep `SKILL.md` focused on core instructions; put longer docs in `references/` and helper code in `scripts/`.

## Contributing & security

- Want to add a new skill, fix one, or change the conventions? See [`contributing.md`](contributing.md) — it covers the quality bar, style, testing checklist, the skills.sh acceptance criteria, the submission process, and the code of conduct.
- Found a security issue (a skill that produces unsafe instructions, leaks secrets, or could be used to attack consumers)? See [`responsible_disclosure.md`](responsible_disclosure.md) before opening a public issue.
- The `LICENSE` at the repo root applies to every file in the tree.
