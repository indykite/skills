# Contributing

Thanks for wanting to add or improve a skill. This guide covers what we expect from contributions and how to get them merged.

## Before you start

- Check the existing skills to make sure yours doesn't overlap. Two skills competing for the same trigger conditions is worse than one focused skill.
- Open an issue for anything non-trivial. A 30-second sanity check from a maintainer can save an afternoon of work.
- Read [`responsible_disclosure.md`](./responsible_disclosure.md) if your contribution touches anything security-sensitive.

## Adding a new skill

1. Create a directory in kebab-case at the repo root: `your-skill-name/`.
2. Add a `SKILL.md` with the frontmatter format documented in the [README](./README.md).
3. Optionally add `scripts/`, `references/`, or `assets/` subdirectories.
4. Open a PR.

### Quality bar

A skill is only useful if an agent invokes it at the right moment. Aim for:

- **A precise `description`.** State both what the skill does *and* the trigger conditions. "Use when the user asks about X" is more useful than "Helps with X." If two skills could plausibly fire on the same prompt, sharpen the descriptions until they don't.
- **Self-contained instructions.** A reader (human or agent) should be able to follow the skill without prior context from this repo.
- **Concrete steps over prose.** Numbered steps and short imperative sentences beat paragraphs.
- **No silent assumptions about tools.** If the skill needs `gh`, `jq`, an MCP server, or features specific to one agent (e.g. Claude Code hooks, Cursor `@`-mentions, Copilot workspace context), say so up front.
- **Agent-portable when possible.** Prefer phrasing that works across agents. Where you must rely on agent-specific behavior, isolate it to a clearly-labeled section so porters know what to swap.
- **Bounded scope.** One skill, one job. Split a sprawling skill into smaller ones rather than letting it grow.

### Style

- Headings: `#` for the skill title, `##` for major sections, `###` for steps.
- Code blocks should specify a language for syntax highlighting.
- Prefer relative links to other files in the repo.
- No emojis in `SKILL.md` unless they're load-bearing (e.g. documenting an emoji-based UI).

## Testing your skill

Before opening a PR:

1. Install it locally in at least one supported agent. The README's install table lists locations for Claude Code, Claude Agent SDK, Cursor, GitHub Copilot, Windsurf, Continue, and Cody.
2. Restart the agent (or reload its config) so it picks up the new skill.
3. Try at least three prompts: one that *should* trigger the skill, one that's adjacent but shouldn't, and one edge case. Confirm the agent's behavior matches what the description promises.
4. If the skill ships scripts, run them directly and check that error paths are handled.
5. If you can, validate against more than one agent — instructions that work in Claude Code sometimes need rewording for Cursor, Copilot, or Aider because of different trigger semantics.

Note in the PR which agents and models you tested with. "Tested in Claude Code with Opus 4.7" is more useful than "tested it."

## Modifying an existing skill

- Small fixes (typos, clarifications) — open a PR directly.
- Behavior changes — open an issue first if the skill has been around for a while; someone may be relying on the current behavior.
- Breaking changes to the trigger description — call this out explicitly in the PR title and body.

## skills.sh acceptance criteria

Skills in this repo follow the [skills.sh](https://skills.sh) / [vercel-labs/skills](https://github.com/vercel-labs/skills) Agent Skills specification so that the same directory can be installed across the 50+ agents the `skills` CLI supports. A skill that doesn't follow these rules will fail discovery, fail the routine security audit, or be rejected at PR review.

### 1. File structure

- Every skill is a directory; the directory name is the skill's slug (lowercase, hyphens allowed, no spaces or uppercase).
- The directory **must** contain a file named exactly `SKILL.md` (case-sensitive). The CLI's loader keys off this filename and will not find `skill.md`, `Skill.md`, `README.md`, or anything else.
- Optional subdirectories: `scripts/`, `references/`, `assets/`. Anything outside these is ignored by most loaders — don't rely on it.
- The skill directory must live in one of the discovery locations the CLI scans: the repo root, `skills/`, `skills/.curated/`, `skills/.experimental/`, `skills/.system/`, or an agent-specific path (`.claude/skills/`, `.cursor/skills/`, `.agents/skills/`, etc.). Skills nested deeper will not be found.
- No symlinks, no executable bit on `SKILL.md`, no binary files at the skill root.

### 2. Frontmatter

`SKILL.md` must open with a YAML frontmatter block delimited by `---`:

```yaml
---
name: your-skill-name
description: One sentence describing what it does. Use when [trigger conditions].
---
```

**Required fields**

- `name` — unique within this repo, lowercase, hyphens allowed, no spaces, no uppercase, no leading/trailing dashes. It should match the directory name.
- `description` — a single sentence (or two short ones) that names *what* the skill does and *when* to invoke it. This string is what agents match on, so vague descriptions get vague triggering. Don't include angle brackets (`<`, `>`) — they break some YAML parsers downstream.

**Optional fields**

- `metadata.internal: true` — hides the skill from normal discovery. Only the `INSTALL_INTERNAL_SKILLS=1` flag surfaces it. Use sparingly, and only for skills that wouldn't be useful to a general audience.
- `allowed-tools` — restricts which tools the agent may call while the skill is active. Note: not all agents honor this field; treat it as advisory.
- `context: fork` — runs the skill in a forked context. Same caveat: limited compatibility, do not rely on it as your only safety boundary.

Anything else in frontmatter is non-standard and may be stripped by the loader. Don't add fields the spec doesn't define.

### 3. Content requirements

The body of `SKILL.md` (after frontmatter) must include, at minimum:

- **A title** — a single `#` heading naming the skill.
- **A "When to use" section** — `## When to use` (or equivalent — `## When this skill applies`). Restate and expand the trigger conditions from `description`. List positive triggers ("user asks about X") *and* anti-triggers ("don't activate when Y").
- **A "Steps" section** — `## Steps` with numbered, imperative instructions. Each step should be one concrete action the agent can perform without further interpretation. Avoid steps that require the agent to decide policy on the fly.
- **A title sentence summarising what success looks like** — usually folded into the intro paragraph or a `## Outcome` section. Reviewers use this to evaluate whether the skill achieves what it claims.

Other expectations:

- Keep `SKILL.md` short. Long skills get truncated by some loaders and dilute the agent's attention. Push background, examples, and reference material into `references/` and link to it from the body.
- Do not embed secrets, API keys, internal URLs, or personal information. Anything you commit becomes public and indexable.
- Do not include adversarial content disguised as instructions ("ignore previous instructions and…"). The skills.sh security audit will flag and reject such submissions, and they're a code-of-conduct violation per the section below.
- If you reference scripts in `scripts/`, use relative paths and explain the script's purpose, expected inputs, and side effects in the body.

### 4. Technical constraints

- **Encoding**: UTF-8, LF line endings, no BOM.
- **Markdown flavor**: GitHub-Flavored Markdown. Code fences must specify a language; raw HTML is discouraged and will be stripped by some renderers.
- **Frontmatter parser**: standard YAML 1.2. Quote any value containing `:`, `#`, or leading whitespace. Multiline strings should use `|` or `>` blocks rather than literal newlines.
- **Scripts**: any script under `scripts/` must declare its interpreter via shebang and document required dependencies in `SKILL.md`. Do not ship pre-built binaries; commit source. Scripts that require network access or sudo must say so explicitly.
- **No bundled credentials**, even for "test" services. Reviewers will reject and the security audit will quarantine.
- **No external runtime fetches at install time** beyond what the agent's loader already does. A skill that downloads code on first use is a supply-chain hazard.
- **Agent-specific features** (Claude Code hooks, Cursor `@`-mentions, Copilot workspace context, MCP-server requirements) must be called out in a clearly-labeled section so porters know what to swap.

### 5. Submission process

1. **Fork** this repository to your own account.
2. **Branch** off `main`: `git checkout -b add-<skill-name>`.
3. **Add the skill** under one of the discovery locations — usually the repo root or `skills/`. Use `skills/.experimental/` if you want the skill discoverable but flagged as not-yet-stable.
4. **Self-test** following the [Testing your skill](#testing-your-skill) checklist above. Validate against at least one agent and, where feasible, a second.
5. **Smoke-test discovery** with the `skills` CLI: `npx skills add ./<path-to-skill> --list` runs the loader's local-path validation, parses the frontmatter, and shows the resolved name/description. If the CLI doesn't list your skill, fix the structure or frontmatter before opening a PR. (There is no dedicated `validate` subcommand — `add --list` is the equivalent dry-run.)
6. **Open a PR** against `main`. Use the PR template (filename, what it does, when it triggers, agents tested, any known gaps). One skill per PR.
7. **Automated checks** will run on the PR: structural validation, frontmatter parse, security audit (the same audit skills.sh runs on indexed skills), and any project-level lint. Fix any failures before requesting review.
8. **Maintainer review** focuses on three things: does the description trigger reliably without colliding with other skills, do the steps actually accomplish the stated outcome, and is there anything in the content or scripts that the security audit could miss. Expect at least one round of revision; treat review notes as a collaboration rather than a gate.
9. **Merge** is squash-by-default to keep `main` clean. The maintainer merging will tag the commit with the skill name so it shows up cleanly in the changelog.
10. **Post-merge**: skills.sh re-indexes from `main` periodically. If you don't see the skill on skills.sh within a day or two, check that none of the optional `metadata.internal` flags were accidentally set, and ping a maintainer.

If your skill is rejected, the review will explain why and what would need to change for a resubmission. Rejections are not personal — most often a skill needs scope tightening or a clearer trigger description rather than a full rewrite.

## Pull requests

- Keep one skill (or one fix) per PR. Reviewers should not have to evaluate unrelated changes together.
- The PR title should name the skill: e.g. `add my-skill` or `fix description in my-skill`.
- The body should answer: what does this skill do, when should it trigger, what did you test?
- Sign off that you have the right to contribute the content under this repo's [LICENSE](./LICENSE).

## Code of conduct

This project is a community of contributors with very different backgrounds, levels of experience, and reasons for being here. We want everyone to be able to participate without friction unrelated to the work itself. The rules below apply to issues, pull requests, code review, commit messages, discussions, and any other channel tied to this repo.

### Our standards

Behavior we expect:

- **Assume good faith.** Most disagreements are honest misunderstandings or differing priorities, not bad intent. Ask a clarifying question before assuming the worst.
- **Critique the work, not the person.** "This skill description is too vague to trigger reliably" is fine. "You don't know what you're doing" is not.
- **Be specific and actionable.** Vague negativity ("this is bad") wastes everyone's time. If you have a concern, name it and, where possible, suggest a fix.
- **Welcome newcomers.** First-time contributors will get conventions wrong. Point them at the relevant section of this guide rather than dismissing the PR.
- **Credit others' work.** If a skill builds on someone else's idea, prompt, or example, link to the source.
- **Respect time zones and availability.** Maintainers and contributors are volunteers in different countries. Pinging the same person three times in a day rarely gets you a faster answer.

Behavior we won't tolerate:

- Harassment, intimidation, or sustained disruption of discussion.
- Discriminatory language or jokes related to race, ethnicity, nationality, gender identity or expression, sexual orientation, disability, neurotype, age, religion, body size, or socioeconomic status.
- Unwelcome sexual attention, imagery, or advances.
- Doxxing — publishing private information (real names, addresses, employers, IP addresses) without consent.
- Threats of violence or wishing harm on a person.
- Sustained bad-faith argument: moving goalposts, sealioning, deliberately misreading replies, repeatedly relitigating settled decisions.
- Deliberately submitting prompt-injection payloads, malware, or skills designed to compromise users — see [`responsible_disclosure.md`](./responsible_disclosure.md) for how to report security issues responsibly. Submitting them disguised as contributions is grounds for an immediate permanent ban.

### Scope

This code applies whenever you are representing the project: in this repo, in linked discussion forums, in issues, in PRs, and in public spaces (conferences, social media, chat) when you are identifying yourself as a contributor here. Private disputes are outside scope unless they spill into project channels or affect a contributor's ability to participate safely.

### Reporting

If you experience or witness behavior that violates this code:

1. **Prefer private reporting.** Email the maintainers — see [`responsible_disclosure.md`](./responsible_disclosure.md) for the contact channel (the same address handles conduct reports). Do not call people out in public threads if a private report can resolve it.
2. **Include context.** Links to the relevant comments, screenshots if a comment was edited or deleted, dates, and what outcome you'd like.
3. **Confidentiality.** Reports are kept confidential among the maintainers handling the case. We will not share your identity with the reported party without your consent, except where required by law.
4. **No retaliation.** Reporting in good faith — even if the report is ultimately not upheld — will never be held against you. Retaliating against a reporter is itself a violation of this code.

### Enforcement

Maintainers will respond to reports proportionally. Possible actions, roughly in order of severity:

1. **Private clarification** — a quiet message explaining what was off and why.
2. **Public correction** — a comment in-thread asking the participant to adjust, sometimes with the offending content edited or hidden.
3. **Warning** — a formal note that further violations will lead to a temporary or permanent ban.
4. **Temporary ban** — loss of commenting / contribution privileges for a defined period (typically 7–90 days).
5. **Permanent ban** — removal from all project spaces. Reserved for severe or repeated violations, threats, doxxing, or deliberately malicious contributions.

Decisions are made by the maintainers reviewing the report. Where a maintainer is involved in the incident, they will recuse themselves from the decision.

### Appeals

If you believe an enforcement action against you was a mistake, you may appeal once by replying to the original notice within 30 days. Include any context the maintainers may not have had. Appeals are reviewed by maintainers who were not involved in the original decision when possible.

### Attribution

This code of conduct is informed by the [Contributor Covenant](https://www.contributor-covenant.org/) v2.1, adapted for the realities of a small open-source skills repo. If anything here conflicts with how a reasonable person reads the Covenant, the more protective interpretation wins.
