# Skills

A collection of skills for coding agents, focused on [IndyKite](https://indykite.ai) — graph-based identity, authorization, and AI-agent integration. Manage your IndyKite project in the Hub UI ([eu.hub.indykite.com](https://eu.hub.indykite.com/) / [us.hub.indykite.com](https://us.hub.indykite.com/)); developer docs at [developer.indykite.com](https://developer.indykite.com/).

A skill is a self-contained bundle of instructions — and optionally scripts, references, or assets — that an agent can load on demand to perform a specialized task.

## Available skills

| Skill                                                                  | What it does                                                                                          |
| :--------------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------- |
| [`indykite-agent-gateway`](indykite-agent-gateway/SKILL.md)     | Deploy and configure Indykite Agent Gateway (IAG) in front of A2A agents to enforce caller, workflow, and delegation-chain checks. |
| [`indykite-mcp-server`](indykite-mcp-server/SKILL.md)           | Call the IndyKite MCP server (initialize session, list tools, call AuthZEN and ContX IQ tools) and configure the MCP server endpoint for a project. |
| [`indykite-ciq-read`](indykite-ciq-read/SKILL.md)               | Author a read-only IndyKite ContX IQ (CIQ) policy and Knowledge Query, then run it via `POST /contx-iq/v1/execute`. |
| [`indykite-ciq-create-node`](indykite-ciq-create-node/SKILL.md) | Author an IndyKite CIQ policy + Knowledge Query that creates a brand-new node in the IKG, then run it via `POST /contx-iq/v1/execute`. |
| [`indykite-ciq-create-relationship`](indykite-ciq-create-relationship/SKILL.md) | Author an IndyKite CIQ policy + Knowledge Query that creates a brand-new relationship between two existing nodes in the IKG, then run it via `POST /contx-iq/v1/execute`. |
| [`indykite-ciq-add-property`](indykite-ciq-add-property/SKILL.md) | Author an IndyKite CIQ policy + Knowledge Query that sets one or more properties on an existing node in the IKG, then run it via `POST /contx-iq/v1/execute`. |
| [`indykite-ciq-add-relationship-property`](indykite-ciq-add-relationship-property/SKILL.md) | Author an IndyKite CIQ policy + Knowledge Query that sets one or more properties on an existing relationship in the IKG, then run it via `POST /contx-iq/v1/execute`. |
| [`indykite-ciq-delete`](indykite-ciq-delete/SKILL.md) | Author an IndyKite CIQ policy + Knowledge Query that deletes a node, a relationship, or one or more properties from the IKG, then run it via `POST /contx-iq/v1/execute`. |
| [`indykite-ciq-create-node-with-link`](indykite-ciq-create-node-with-link/SKILL.md) | Author an IndyKite CIQ policy + Knowledge Query that creates a brand-new node AND links it to one or more existing nodes via new relationships in a single atomic execute. |

## Examples gallery

Sample prompts each skill is *designed* to handle. Derived from each skill's `description` and `## When to use` — they describe the kinds of asks the skill targets. **Activation isn't guaranteed**: which skill actually fires depends on the agent's matching algorithm, the model, and which other skills are installed. Verify routing in your own setup before relying on it.

| Skill                                       | Example prompt                                                                                          |
|---------------------------------------------|---------------------------------------------------------------------------------------------------------|
| `indykite-agent-gateway`                     | "Deploy IAG in front of my three A2A agents and wire up the workflow in the IKG."                       |
| `indykite-mcp-server`                        | "How do I initialise an MCP session against `eu.mcp.indykite.com` and call `authzen_evaluate`?"          |
| `indykite-ciq-read`                          | "Expose `Person`-`OWNS`-`Car` as a parameterised read query through ContX IQ."                          |
| `indykite-ciq-create-node`                   | "Create a new `Track` node in the IKG with `title` and `loudness`, via CIQ."                            |
| `indykite-ciq-create-relationship`           | "Add a `PLAYED_AT` relationship between an existing `Track` and an existing `Venue`."                    |
| `indykite-ciq-create-node-with-link`         | "Create a new `Contract` and atomically link it to an existing `Vehicle` and `Person`."                   |
| `indykite-ciq-add-property`                  | "Let a `Person` update their own `music_mood` property."                                                |
| `indykite-ciq-add-relationship-property`     | "Annotate an existing `PLAYED_AT` relationship with a `verified` flag and timestamp."                    |
| `indykite-ciq-delete`                        | "Clear the `music_mood` property from a `Person` — GDPR-style erase."                                   |

## Supported agents

These skills are installed via the [`skills`](https://skills.sh) CLI (skills.sh / [`vercel-labs/skills`](https://github.com/vercel-labs/skills)) — a **cross-agent installer**. One command, many agents: the CLI knows the per-agent install location for every agent it supports, and you target one (or all of them) via the `--agent` flag.

```bash
# Install into every agent the CLI detects on your machine
npx skills add <repo>

# Install for a specific agent
npx skills add <repo> --agent claude-code

# See which agent names the CLI accepts in your installed version
# (a typo prints the full valid set, so you discover it on demand)
npx skills add <repo> --agent foobar
```

The CLI accepts **many** agent names — far more than this repo has been tested against. Treat the CLI's own `--agent` list as the source of truth; it stays current as new agents are added.

What we've verified end-to-end in this repo:

- **Claude Code** — `npx skills add <repo> --agent claude-code` installs each skill into `~/.claude/skills/<name>/` (global) or `.claude/skills/<name>/` (project). Claude Code reads `SKILL.md` directly and activates skills automatically by matching the user's prompt against `description`. There is also a bundle-install path via the Claude Code plugin marketplace using [`.claude-plugin/`](.claude-plugin/) — see [Bundle install](#bundle-install-claude-code-plugin--gemini-extension).

For **Gemini CLI**, install via the [`gemini-extension.json`](gemini-extension.json) at the repo root instead — Gemini's extension system has its own loader, independent of the `skills` CLI.

For every other agent the `skills` CLI lists, `npx skills add <repo> --agent <name>` should drop the files in the right place — but **native `SKILL.md` triggering is a property of the agent, not the CLI**. The CLI guarantees files arrive at the right path; whether the agent then activates a skill automatically (by matching the prompt against `description`), via a slash command, or by explicit selection depends on that agent. Check the agent's own documentation when automatic activation matters.

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

## Bundle install (Claude Code plugin / Gemini extension)

For agents that support a single labelled plugin install, this repo ships per-agent manifest files. They register all 9 skills at once and prompt the user for credentials (`API_URL`, `API_KEY`, `BEARER_TOKEN`, `SERVICE_ACCOUNT_TOKEN`, `MCP_URL`, `PROJECT_GID`) at install time.

### Claude Code

The repo ships [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json) and [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json). Install via Claude Code's plugin marketplace in two steps:

```text
# 1. Register this repo as a marketplace
/plugin marketplace add indykite/skills

# 2. Install the plugin from it
/plugin install indykite-skills
```

### Gemini CLI

The repo ships [`gemini-extension.json`](gemini-extension.json) at the root. Install via Gemini CLI's extension command:

```bash
gemini extensions install https://github.com/indykite/skills
```

Gemini reads the extension manifest, uses `contextFileName` (the repo's `README.md`) as loaded context, and exposes each entry in `settings` as an environment variable. The six configuration values (`API_URL`, `API_KEY`, `BEARER_TOKEN`, `SERVICE_ACCOUNT_TOKEN`, `MCP_URL`, `PROJECT_GID`) are the same as the Claude Code `userConfig` schema, sharing one source of truth in `manifest.yaml`.

### Per-skill install via the `skills` CLI

If you only want one or two of the skills, or your agent doesn't have a plugin marketplace, use `npx skills add indykite/skills --agent <name>` — see [Supported agents](#supported-agents) above. The bundle install registers all 9 skills with credential prompts; the per-skill install lets you cherry-pick and leaves credentials to env vars.

## How skills activate

A skill is **passive until invoked**. Most supported agents activate skills *automatically* by matching the user's prompt against each installed skill's `description` field — the one-line summary in `SKILL.md`'s frontmatter. When the description fits the request, the agent loads the rest of the skill into context before answering. The `## When to use` section in each `SKILL.md` is read by the agent (not just the human) and is what determines whether activation actually fires for a given prompt — that is why the existing skills here list both positive triggers and explicit anti-triggers.

If you expect a skill to activate but it doesn't, check three things:

1. **The agent loaded it.** Ask the agent which skills are available, or run `npx skills list` (or `npx skills ls`) to see what is installed for the current scope. A skill that isn't installed cannot activate.
2. **The description fits the prompt.** Open `SKILL.md` and re-read the `description` and `## When to use`. Vague descriptions get vague triggering — sharpen the wording, reinstall, and try again. If two skills could plausibly match the same prompt, the agent will pick one and you may need to disambiguate by tightening one of the descriptions.
3. **Manual fallback.** Most agents let you invoke a skill by name (e.g. `/<skill-name>` in Claude Code, or selecting it explicitly in Cursor / Copilot). Use that when automatic routing is uncertain — it also tells you whether the skill itself is loaded and working independently of the description match.

To **disable** a misbehaving skill: remove the directory (`npx skills remove <name>`, or delete it from the agent's skills folder), or set `metadata.internal: true` in its frontmatter so it stays installed but is hidden from automatic discovery (it will only surface if `INSTALL_INTERNAL_SKILLS=1` is set).

## Authoring a skill

Reference for anyone writing or forking a skill in this repo. The full submission flow lives in [`CONTRIBUTING.md`](CONTRIBUTING.md) — this section is the at-a-glance summary.

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

- Want to add a new skill, fix one, or change the conventions? See [`CONTRIBUTING.md`](CONTRIBUTING.md) — it covers the quality bar, style, testing checklist, [Agent Skills specification](https://agentskills.io/specification) compliance, the submission process, and the code of conduct.
- Want to *exercise* the skills (structural validation, dry-run smoke tests, or live API roundtrips)? See [`testing/README.md`](testing/README.md). The runnable harness is `./testing/e2e-ciq.sh`.
- Found a security issue (a skill that produces unsafe instructions, leaks secrets, or could be used to attack consumers)? See [`responsible_disclosure.md`](responsible_disclosure.md) before opening a public issue.
- The `LICENSE` at the repo root applies to every file in the tree.
