# Skills

[![Install with skills CLI](https://img.shields.io/badge/install-npx%20skills%20add%20indykite%2Fskills-000000?style=for-the-badge&logo=npm&logoColor=white)](https://www.skills.sh/indykite/skills)

A collection of skills for coding agents that work with [IndyKite](https://indykite.ai) — graph-based identity, authorization, and AI-agent integration.

A **skill** is a self-contained bundle of instructions (and optionally scripts, references, or assets) that an agent loads on demand to perform a specialized task.

## Contents

- [Glossary](#glossary)
- [Skills in this repo](#skills-in-this-repo)
- [Install](#install)
- [Bundle install](#bundle-install)
- [Supported agents](#supported-agents)
- [How skills activate](#how-skills-activate)
- [Authoring a skill](#authoring-a-skill)
- [Resources](#resources)
- [Contributing and security](#contributing-and-security)

## Glossary

Acronyms used throughout the skills, defined once here.

- **IndyKite** — the company behind these skills. UI at [eu.hub.indykite.com](https://eu.hub.indykite.com/) / [us.hub.indykite.com](https://us.hub.indykite.com/); REST API at `openapi.indykite.com`; docs at [developer.indykite.com](https://developer.indykite.com/).
- **IKG** — IndyKite Graph; the graph database holding identity, relationships, and properties for a project.
- **CIQ** — ContX IQ; an IndyKite context authorization policy plus its Knowledge Query, executed via `POST /contx-iq/v1/execute`.
- **Knowledge Query** — the parameterised read/write definition CIQ runs against the IKG.
- **AuthZEN** — IndyKite's policy-decision endpoint (`authzen_evaluate`).
- **IAG** — IndyKite Agent Gateway; enforces caller, workflow, and delegation-chain checks in front of A2A agents.
- **A2A** — agent-to-agent; one autonomous agent calling another.
- **MCP** — Model Context Protocol; the IndyKite MCP server exposes AuthZEN and CIQ tools to MCP-aware agents.

## Skills in this repo

Each row is one skill — what it does and a representative prompt it's *designed* to handle. **Activation isn't guaranteed**: which skill actually fires depends on the agent's matching algorithm, the model, and what else is installed. Verify routing in your own setup before relying on it.

| Skill | What it does | Example prompt |
|:------|:-------------|:---------------|
| [`indykite-agent-gateway`](indykite-agent-gateway/SKILL.md) | Deploy and configure IAG in front of A2A agents to enforce caller, workflow, and delegation-chain checks. | "Deploy IAG in front of my three A2A agents and wire up the workflow in the IKG." |
| [`indykite-mcp-server`](indykite-mcp-server/SKILL.md) | Call the IndyKite MCP server (initialize session, list tools, call AuthZEN and CIQ tools) and configure the MCP endpoint for a project. | "How do I initialise an MCP session against `eu.mcp.indykite.com` and call `authzen_evaluate`?" |
| [`indykite-ciq-read`](indykite-ciq-read/SKILL.md) | Author a read-only CIQ policy and Knowledge Query, then run it via `POST /contx-iq/v1/execute`. | "Expose `Person`-`OWNS`-`Car` as a parameterised read query through ContX IQ." |
| [`indykite-ciq-create-node`](indykite-ciq-create-node/SKILL.md) | Author a CIQ policy + Knowledge Query that creates a brand-new node in the IKG. | "Create a new `Track` node in the IKG with `title` and `loudness`, via CIQ." |
| [`indykite-ciq-create-relationship`](indykite-ciq-create-relationship/SKILL.md) | Author a CIQ policy + Knowledge Query that creates a brand-new relationship between two existing nodes. | "Add a `PLAYED_AT` relationship between an existing `Track` and an existing `Venue`." |
| [`indykite-ciq-create-node-with-link`](indykite-ciq-create-node-with-link/SKILL.md) | Author a CIQ policy + Knowledge Query that creates a new node AND links it to one or more existing nodes in a single atomic execute. | "Create a new `Contract` and atomically link it to an existing `Vehicle` and `Person`." |
| [`indykite-ciq-add-property`](indykite-ciq-add-property/SKILL.md) | Author a CIQ policy + Knowledge Query that sets one or more properties on an existing node. | "Let a `Person` update their own `music_mood` property." |
| [`indykite-ciq-add-relationship-property`](indykite-ciq-add-relationship-property/SKILL.md) | Author a CIQ policy + Knowledge Query that sets one or more properties on an existing relationship. | "Annotate an existing `PLAYED_AT` relationship with a `verified` flag and timestamp." |
| [`indykite-ciq-delete`](indykite-ciq-delete/SKILL.md) | Author a CIQ policy + Knowledge Query that deletes a node, a relationship, or one or more properties. | "Clear the `music_mood` property from a `Person` — GDPR-style erase." |

## Install

The recommended path is the [`skills`](https://skills.sh) CLI — one command, many agents. The CLI knows the per-agent install location and targets one (or all) via the `--agent` flag.

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
- `-a, --agent <name>` — limit to one or more agents (use `*` for all). A typo prints the full valid set.
- `-s, --skill <name>` — limit to one or more skills.
- `--copy` — copy files instead of symlinking (default is symlink so updates propagate).
- `-y, --yes` — skip confirmation prompts (handy in CI).

**After installing, restart the agent** (or reload its config) so it picks up the new skill directory. Verify with `npx skills list`.

**Quick verification:** install one skill, then ask the agent something its description matches. For `indykite-mcp-server`: anything about initialising an MCP session against `eu.mcp.indykite.com` / `us.mcp.indykite.com`, calling `authzen_evaluate` / `ciq_execute`, or debugging a `401` from the MCP server.

### Manual install

If you don't want the CLI, copy or symlink the skill directory into the agent's expected location. For **Claude Code** that's `~/.claude/skills/<skill-name>/` (user scope) or `.claude/skills/<skill-name>/` (project scope). For any other agent, consult its docs — most that don't read `SKILL.md` natively expect the *body* (everything after the YAML frontmatter) pasted into their own rule format.

## Bundle install

For agents that support a single labelled plugin install, this repo ships per-agent manifest files. They register every skill in this repo at once and prompt for credentials (`API_URL`, `API_KEY`, `BEARER_TOKEN`, `SERVICE_ACCOUNT_TOKEN`, `MCP_URL`, `PROJECT_GID`) at install time. Source of truth for the credential list is [`manifest.yaml`](manifest.yaml).

### Claude Code

Ships [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json) and [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json):

```text
# 1. Register this repo as a marketplace
/plugin marketplace add indykite/skills

# 2. Install the plugin from it
/plugin install indykite-skills
```

### Gemini CLI

Ships [`gemini-extension.json`](gemini-extension.json) at the repo root:

```bash
gemini extensions install https://github.com/indykite/skills
```

Gemini uses this `README.md` as its loaded context (`contextFileName`) and exposes each `settings` entry as an environment variable.

### Cherry-picking from a bundle

If you only want one or two skills, use `npx skills add indykite/skills --skill <name>` instead — see [Install](#install). The bundle prompts for all six credentials; per-skill installs leave credential management to env vars.

## Supported agents

The `skills` CLI is a **cross-agent installer** — `npx skills add indykite/skills --agent <name>` drops files in the right place for whatever agent `<name>` the CLI knows about. The CLI's `--agent` list is the source of truth and stays current as new agents are added.

Verified end-to-end in this repo: **Claude Code**, **Gemini CLI**.

For every other agent the CLI lists, files arrive at the right path — but **native `SKILL.md` triggering is a property of the agent, not the CLI**. Whether an agent activates a skill automatically (matching the prompt against `description`), via a slash command, or by explicit selection depends on that agent. Check its docs when automatic activation matters.

## How skills activate

A skill is **passive until invoked**. Supported agents activate skills *automatically* by matching the user's prompt against each installed skill's `description` field — the one-line summary in `SKILL.md`'s frontmatter. When the description fits the request, the agent loads the rest of the skill into context before answering. The `## When to use` section is also read by the agent and determines whether activation fires — that's why the skills here list both positive triggers and explicit anti-triggers.

If a skill doesn't activate when you expect it to, check three things:

1. **The agent loaded it.** `npx skills list` shows what's installed for the current scope. A skill that isn't installed cannot activate.
2. **The description fits the prompt.** Open `SKILL.md` and re-read `description` and `## When to use`. Vague descriptions get vague triggering — sharpen the wording, reinstall, retry. If two skills could match the same prompt, the agent picks one; tighten one description to disambiguate.
3. **Manual fallback.** Most agents let you invoke a skill by name (`/<skill-name>` in Claude Code, or explicit selection in Cursor / Copilot). Useful when automatic routing is uncertain — also tells you whether the skill is loaded at all.

To **disable** a misbehaving skill: remove the directory (`npx skills remove <name>`, or delete from the agent's skills folder), or set `metadata.internal: true` in its frontmatter so it stays installed but hidden from automatic discovery (it surfaces only when `INSTALL_INTERNAL_SKILLS=1`).

## Authoring a skill

At-a-glance reference; full submission flow lives in [`CONTRIBUTING.md`](CONTRIBUTING.md).

### Structure

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

## Resources

- IndyKite Hub UI: [eu.hub.indykite.com](https://eu.hub.indykite.com/) / [us.hub.indykite.com](https://us.hub.indykite.com/)
- IndyKite REST API: `openapi.indykite.com`
- Developer docs: [developer.indykite.com](https://developer.indykite.com/)
- Skills CLI: [skills.sh](https://skills.sh) ([`vercel-labs/skills`](https://github.com/vercel-labs/skills))
- Agent Skills specification: [agentskills.io/specification](https://agentskills.io/specification)

## Contributing and security

- Add a new skill, fix one, or change conventions → [`CONTRIBUTING.md`](CONTRIBUTING.md) covers the quality bar, style, testing checklist, [Agent Skills specification](https://agentskills.io/specification) compliance, submission process, and code of conduct.
- Exercise the skills (structural validation, dry-run smoke tests, live API roundtrips) → [`testing/README.md`](testing/README.md). Harness: `./testing/e2e-ciq.sh`.
- Found a security issue → [`responsible_disclosure.md`](responsible_disclosure.md) before opening a public issue.
- The `LICENSE` at the repo root applies to every file in the tree.
