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

## Validating your skill

Behavioural testing in an agent (above) confirms the skill *triggers and runs*. The checks below confirm it meets the [Agent Skills specification](https://agentskills.io/specification) and the technical constraints listed in [§ Agent Skills specification compliance](#agent-skills-specification-compliance) — encoding, frontmatter parse, script syntax, asset validity. Run them from the repo root before opening a PR.

```bash
# 1. Spec-compliance check (canonical).
#    `skills-ref` is the reference validator from agentskills.io. It checks
#    the YAML frontmatter against the spec (name format, length limits,
#    required fields). Install once via `pipx`; reuse across repos.
skills-ref validate ./<skill-name>

# 2. Loader dry-run — confirms the `skills` CLI (skills.sh ecosystem,
#    one of the most common consumer loaders) discovers the skill.
#    Catches some structural issues skills-ref doesn't (e.g. discovery-
#    location mistakes when nested too deep).
npx skills add ./<skill-name> --list

# 3. Shell script syntax (only if the skill ships scripts).
bash -n <skill-name>/scripts/*.sh

# 4. JSON asset validity (only if the skill ships JSON assets).
jq empty <skill-name>/assets/*.json

# 5. File hygiene — UTF-8 / LF / no BOM.
file <skill-name>/SKILL.md           # expect "ASCII text" or "UTF-8 Unicode text"
grep -rl $'\r' <skill-name>/ || true # expect no output (no CRLF anywhere); grep exits 1 when nothing matches, which is the success case here — `|| true` keeps CI scripts happy.
head -c 3 <skill-name>/SKILL.md | od -An -tx1
                                     # expect content bytes (e.g. 2d 2d 2d for `---`)
                                     # — if you see ef bb bf, strip the UTF-8 BOM
```

If any check fails, fix the underlying issue rather than working around it. `skills-ref` and the loader dry-run together cover spec compliance and discovery; the remaining commands cover encoding, scripts, and assets that neither tool flags.

To validate the whole repo at once:

```bash
for s in */; do skills-ref validate "$s" 2>&1; done   # spec
npx skills add . --list                                # loader

# Or use the all-in-one harness:
./testing/e2e-ciq.sh
```

## Modifying an existing skill

- Small fixes (typos, clarifications) — open a PR directly.
- Behavior changes — open an issue first if the skill has been around for a while; someone may be relying on the current behavior.
- Breaking changes to the trigger description — call this out explicitly in the PR title and body.

## Agent Skills specification compliance

Skills in this repo conform to the [Agent Skills specification](https://agentskills.io/specification) hosted at agentskills.io. The canonical validator is `skills-ref` (Python; `pipx install <agentskills-repo>/skills-ref`); the [`skills`](https://skills.sh) CLI / [`vercel-labs/skills`](https://github.com/vercel-labs/skills) is one of 50+ consumer agents that loads skills following the same spec. A skill that doesn't satisfy the spec will fail `skills-ref validate`, fail the loader's discovery scan, or be rejected at PR review.

### 1. File structure

- Every skill is a directory; the directory name is the skill's slug.
- The directory **must** contain a file named exactly `SKILL.md` (case-sensitive). The loader keys off this filename and will not find `skill.md`, `Skill.md`, `README.md`, or anything else.
- Optional subdirectories named by the spec: `scripts/`, `references/`, `assets/`. Additional files and directories are allowed by the spec, though most loaders ignore them.
- The skill directory should live in one of the discovery locations the `skills` CLI scans (when used as the loader): the repo root, `skills/`, `skills/.curated/`, `skills/.experimental/`, `skills/.system/`, or an agent-specific path (`.claude/skills/`, `.cursor/skills/`, `.agents/skills/`, etc.). This repo places skills at the root.
- No symlinks, no executable bit on `SKILL.md`, no binary files at the skill root.

### 2. Frontmatter

`SKILL.md` must open with a YAML frontmatter block delimited by `---`:

```yaml
---
name: your-skill-name
description: One or two sentences describing what it does and when to invoke it.
license: Apache-2.0
compatibility: Requires curl, bash 4+, and network access to the relevant IndyKite endpoints.
---
```

**Required fields** (per [the spec](https://agentskills.io/specification)):

- `name` — 1–64 characters, lowercase letters / digits / hyphens only, no leading/trailing/consecutive hyphens. **Must match the parent directory name.**
- `description` — 1–1024 characters, non-empty. Must describe what the skill does *and* when to invoke it; the agent matches on this string, so vague descriptions get vague triggering. Aim for a precise two-sentence form.

**Optional fields** (per the spec):

- `license` — short license name or reference to a bundled file. This repo uses `Apache-2.0`.
- `compatibility` — 1–500 characters describing environment requirements (intended product, system packages, network access). Most CIQ skills here use `"Requires curl, bash 4+, and jq. Network access to the regional IndyKite REST API …"`. Omit if your skill has no real requirements.
- `metadata` — arbitrary key-value mapping. The spec recommends reasonably-unique keys to avoid collisions. Some loaders (e.g. the `skills` CLI) recognise `metadata.internal: true` as "hide from default discovery" — that's a loader extension, not a core spec field.
- `allowed-tools` — space-separated string of pre-approved tools (experimental; honoured by some agents, ignored by others).

Anything not listed above is non-standard. Don't invent new top-level fields; use `metadata.<key>` for project-specific extensions.

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
5. **Validate locally.** Run the checks in [§ Validating your skill](#validating-your-skill) above — the loader dry-run plus script syntax, JSON validity, and file-hygiene commands. The loader alone does not catch CRLF line endings, an unlabelled code fence, or a broken shell script.
6. **Open a PR** against `main`. The repo's [PR template](.github/PULL_REQUEST_TEMPLATE.md) auto-fills — fill in *what this PR does*, *when the skill should activate* (quoting the `description` and `## When to use`), *agents and models tested*, and any *known gaps*. One skill per PR.
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
